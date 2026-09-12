use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
};

use serde::{de, Deserialize, Deserializer, Serialize};
use serde_json::{json, Map, Value as JsonValue};
use tachiko_storage::{load_roproj, to_canonical_string};
use tachiko_workspace_engine::{
    validate, Document, Entity, EntityId, FieldDefinition, FieldId, FieldType, Number, Schema,
    SchemaId, Value,
};

const PREFIX: &str = "RICHMAN4_CHARACTER_ORACLE=";
const COUNT: usize = 12;
const SAFE_INTEGER_MIN: i64 = -9_007_199_254_740_991;
const SAFE_INTEGER_MAX: i64 = 9_007_199_254_740_991;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Candidate {
    characters: Vec<Character>,
}
#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(deny_unknown_fields)]
struct Character {
    legacy_id: i64,
    display_name: String,
}
#[derive(Debug, Serialize)]
struct Identity {
    document_id: String,
    records: Vec<IdentityRecord>,
}
#[derive(Debug, Serialize)]
struct IdentityRecord {
    legacy_id: i64,
    semantic_id: String,
}
#[derive(Debug, Deserialize)]
struct Runtime {
    entities: BTreeMap<String, RuntimeEntity>,
}
#[derive(Debug, Deserialize)]
struct RuntimeEntity {
    fields: BTreeMap<String, JsonValue>,
}

struct Strict(JsonValue);
impl<'de> Deserialize<'de> for Strict {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct Visitor;
        impl<'de> de::Visitor<'de> for Visitor {
            type Value = JsonValue;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("JSON")
            }
            fn visit_unit<E>(self) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Null)
            }
            fn visit_bool<E>(self, v: bool) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Bool(v))
            }
            fn visit_i64<E>(self, v: i64) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Number(v.into()))
            }
            fn visit_u64<E>(self, v: u64) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Number(v.into()))
            }
            fn visit_f64<E>(self, v: f64) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                serde_json::Number::from_f64(v)
                    .map(JsonValue::Number)
                    .ok_or_else(|| E::custom("non-finite JSON number"))
            }
            fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::String(v.to_owned()))
            }
            fn visit_string<E>(self, v: String) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::String(v))
            }
            fn visit_seq<A>(self, mut a: A) -> Result<Self::Value, A::Error>
            where
                A: de::SeqAccess<'de>,
            {
                let mut out = Vec::new();
                while let Some(v) = a.next_element_seed(Seed)? {
                    out.push(v);
                }
                Ok(JsonValue::Array(out))
            }
            fn visit_map<A>(self, mut a: A) -> Result<Self::Value, A::Error>
            where
                A: de::MapAccess<'de>,
            {
                let mut out = Map::new();
                while let Some(key) = a.next_key::<String>()? {
                    if out.contains_key(&key) {
                        return Err(de::Error::custom(format!("duplicate JSON key: {key}")));
                    }
                    out.insert(key, a.next_value_seed(Seed)?);
                }
                Ok(JsonValue::Object(out))
            }
        }
        struct Seed;
        impl<'de> de::DeserializeSeed<'de> for Seed {
            type Value = JsonValue;
            fn deserialize<D>(self, d: D) -> Result<Self::Value, D::Error>
            where
                D: Deserializer<'de>,
            {
                d.deserialize_any(Visitor)
            }
        }
        deserializer.deserialize_any(Visitor).map(Self)
    }
}

fn fail(message: impl Into<String>) -> ! {
    eprintln!("tachiko_character_mirror: {}", message.into());
    std::process::exit(1)
}
fn read(path: &Path) -> Vec<u8> {
    fs::read(path).unwrap_or_else(|e| fail(format!("read {}: {e}", path.display())))
}
fn write_new(path: &Path, bytes: &[u8]) {
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .unwrap_or_else(|e| fail(format!("create {}: {e}", path.display())));
    f.write_all(bytes)
        .and_then(|_| f.sync_all())
        .unwrap_or_else(|e| fail(format!("write {}: {e}", path.display())));
}
fn json(bytes: &[u8]) -> JsonValue {
    serde_json::from_slice::<Strict>(bytes)
        .unwrap_or_else(|e| fail(format!("strict JSON parse failed: {e}")))
        .0
}
fn candidate(bytes: &[u8]) -> Candidate {
    serde_json::from_value(json(bytes))
        .unwrap_or_else(|e| fail(format!("character schema rejected: {e}")))
}
fn validate_candidate(c: &Candidate) {
    if c.characters.len() != COUNT {
        fail(format!("expected {COUNT} characters"));
    }
    let mut ids = BTreeSet::new();
    for row in &c.characters {
        if !(0..COUNT as i64).contains(&row.legacy_id) || !ids.insert(row.legacy_id) {
            fail("legacy_id must be unique and exactly 0..11");
        }
        if row.display_name.is_empty() {
            fail("display_name must be non-empty");
        }
    }
    if ids != (0..COUNT as i64).collect() {
        fail("legacy_id set must be exactly 0..11");
    }
}
fn fid(key: &str) -> FieldId {
    format!("field-character-{key}").into()
}
fn eid(legacy_id: i64) -> EntityId {
    let mut hash = 14_695_981_039_346_656_037_u64;
    for byte in b"richman4/tachiko/character/entity/v2:"
        .iter()
        .chain(legacy_id.to_string().as_bytes())
    {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    format!("sid-{hash:016x}").into()
}
fn schema() -> Schema {
    let id: SchemaId = "schema-character".into();
    let fields = [
        ("legacy_id", FieldType::Number),
        ("display_name", FieldType::Text),
    ]
    .into_iter()
    .map(|(key, field_type)| {
        let id = fid(key);
        (
            id.clone(),
            FieldDefinition {
                id,
                key: key.into(),
                field_type,
                required: true,
            },
        )
    })
    .collect();
    Schema {
        id,
        key: "characters".into(),
        fields,
    }
}
fn document(c: &Candidate) -> Document {
    validate_candidate(c);
    let schema = schema();
    let mut schemas = BTreeMap::new();
    schemas.insert(schema.id.clone(), schema);
    let mut entities = BTreeMap::new();
    for row in &c.characters {
        let id = eid(row.legacy_id);
        let mut fields = BTreeMap::new();
        fields.insert(
            fid("legacy_id"),
            Value::Number(
                Number::new(row.legacy_id as f64).unwrap_or_else(|e| fail(e.to_string())),
            ),
        );
        fields.insert(fid("display_name"), Value::Text(row.display_name.clone()));
        entities.insert(
            id.clone(),
            Entity {
                id,
                key: format!("character_{:02}", row.legacy_id).into(),
                schema: "schema-character".into(),
                fields,
            },
        );
    }
    Document {
        id: "richman4-tachiko-character-mirror".into(),
        title: "Richman4 Tachiko character mirror".into(),
        schemas,
        entities,
    }
}
fn publish(c: &Candidate, path: &Path) {
    let d = document(c);
    validate(&d).unwrap_or_else(|e| fail(format!("Rust validation rejected document: {e}")));
    let bytes = to_canonical_string(&d)
        .unwrap_or_else(|e| fail(format!("Rust storage encoding failed: {e}")));
    write_new(path, bytes.as_bytes());
}
fn import_log(path: &Path) -> Candidate {
    let data = read(path);
    let records: Vec<&[u8]> = data
        .split(|b| *b == b'\n')
        .filter_map(|line| line.strip_prefix(PREFIX.as_bytes()))
        .collect();
    if records.len() != 1 {
        fail(format!(
            "expected one {PREFIX} record, found {}",
            records.len()
        ));
    }
    candidate(records[0])
}
fn text(e: &RuntimeEntity, key: &str) -> String {
    e.fields
        .get(key)
        .and_then(JsonValue::as_str)
        .map(str::to_owned)
        .unwrap_or_else(|| fail(format!("runtime field missing or not text: {key}")))
}
fn integer(e: &RuntimeEntity, key: &str) -> i64 {
    let v = e
        .fields
        .get(key)
        .unwrap_or_else(|| fail(format!("runtime field missing: {key}")));
    let n = v
        .as_i64()
        .or_else(|| v.as_u64().and_then(|n| i64::try_from(n).ok()))
        .or_else(|| {
            v.as_f64().and_then(|n| {
                if n.is_finite()
                    && n.fract() == 0.0
                    && n >= SAFE_INTEGER_MIN as f64
                    && n <= SAFE_INTEGER_MAX as f64
                {
                    Some(n as i64)
                } else {
                    None
                }
            })
        })
        .unwrap_or_else(|| fail(format!("runtime field not integer: {key}")));
    if !(SAFE_INTEGER_MIN..=SAFE_INTEGER_MAX).contains(&n) {
        fail(format!("runtime {key} outside safe integer range"));
    }
    n
}
fn projection(r: &Runtime) -> JsonValue {
    let mut rows = Vec::new();
    for i in 0..COUNT {
        let e = r
            .entities
            .values()
            .find(|e| e.fields.get("legacy_id").and_then(JsonValue::as_f64) == Some(i as f64))
            .unwrap_or_else(|| fail(format!("runtime character legacy_id missing: {i}")));
        rows.push(
            json!({"legacy_id": integer(e, "legacy_id"), "display_name": text(e, "display_name")}),
        );
    }
    let mut root = Map::new();
    root.insert("characters".into(), JsonValue::Array(rows));
    JsonValue::Object(root)
}
fn identity(input: &Path, output: &Path) {
    let d = load_roproj(input).unwrap_or_else(|e| fail(format!("load .roproj failed: {e}")));
    let mut records = Vec::new();
    for e in d.entities.values() {
        if !e.key.as_str().starts_with("character_") {
            continue;
        }
        let n = match e.fields.get(&fid("legacy_id")) {
            Some(Value::Number(n)) if n.get().fract() == 0.0 => n.get() as i64,
            _ => fail(format!("{} has no typed legacy_id", e.key)),
        };
        records.push(IdentityRecord {
            legacy_id: n,
            semantic_id: e.id.to_string(),
        });
    }
    records.sort_by_key(|r| r.legacy_id);
    write_new(
        output,
        serde_json::to_vec_pretty(&Identity {
            document_id: d.id.to_string(),
            records,
        })
        .unwrap_or_else(|e| fail(e.to_string()))
        .as_slice(),
    );
}
fn mutant(input: &Path, output: &Path, kind: &str) {
    if kind == "duplicate-key" {
        write_new(
            output,
            br#"{"characters":[{"legacy_id":0,"legacy_id":1,"display_name":"x"}]}"#,
        );
        return;
    }
    let mut root = json(&read(input));
    let row = root
        .get_mut("characters")
        .and_then(JsonValue::as_array_mut)
        .and_then(|a| a.first_mut())
        .and_then(JsonValue::as_object_mut)
        .unwrap_or_else(|| fail("characters[0] missing"));
    match kind {
        "missing-identity" => {
            row.remove("legacy_id");
        }
        "duplicate-id" => {
            row.insert("legacy_id".into(), json!(1));
        }
        "out-of-range" => {
            row.insert("legacy_id".into(), json!(12));
        }
        "wrong-id-type" => {
            row.insert("legacy_id".into(), json!("0"));
        }
        "wrong-name-type" => {
            row.insert("display_name".into(), json!(7));
        }
        "empty-name" => {
            row.insert("display_name".into(), json!(""));
        }
        "unknown-field" => {
            row.insert("unexpected".into(), json!(true));
        }
        "gameplay-leak" => {
            row.insert("init_cash_ratio".into(), json!(50));
        }
        _ => fail(format!("unknown mutant: {kind}")),
    }
    write_new(
        output,
        serde_json::to_vec_pretty(&root)
            .unwrap_or_else(|e| fail(e.to_string()))
            .as_slice(),
    );
}
fn main() {
    let mut a = env::args().skip(1);
    match a.next().as_deref() {
        Some("import-log") => {
            let c = import_log(Path::new(&a.next().unwrap_or_else(|| fail("log missing"))));
            publish(
                &c,
                Path::new(&a.next().unwrap_or_else(|| fail("ro output missing"))),
            );
            identity_from_candidate(
                &c,
                Path::new(&a.next().unwrap_or_else(|| fail("identity output missing"))),
            );
        }
        Some("candidate") => {
            let c = candidate(&read(Path::new(
                &a.next().unwrap_or_else(|| fail("candidate missing")),
            )));
            publish(
                &c,
                Path::new(&a.next().unwrap_or_else(|| fail("ro output missing"))),
            );
        }
        Some("normalize") => {
            let r: Runtime = serde_json::from_slice(&read(Path::new(
                &a.next().unwrap_or_else(|| fail("runtime missing")),
            )))
            .unwrap_or_else(|e| fail(format!("runtime rejected: {e}")));
            write_new(
                Path::new(&a.next().unwrap_or_else(|| fail("projection missing"))),
                serde_json::to_vec_pretty(&projection(&r))
                    .unwrap_or_else(|e| fail(e.to_string()))
                    .as_slice(),
            );
        }
        Some("identity") => identity(
            Path::new(&a.next().unwrap_or_else(|| fail("roproj missing"))),
            Path::new(&a.next().unwrap_or_else(|| fail("identity output missing"))),
        ),
        Some("mutant") => mutant(
            Path::new(&a.next().unwrap_or_else(|| fail("input missing"))),
            Path::new(&a.next().unwrap_or_else(|| fail("output missing"))),
            &a.next().unwrap_or_else(|| fail("kind missing")),
        ),
        Some(other) => fail(format!("unknown command: {other}")),
        None => fail("usage: import-log|candidate|normalize|identity|mutant"),
    }
}
fn identity_from_candidate(c: &Candidate, path: &Path) {
    let mut records = c
        .characters
        .iter()
        .map(|r| IdentityRecord {
            legacy_id: r.legacy_id,
            semantic_id: eid(r.legacy_id).to_string(),
        })
        .collect::<Vec<_>>();
    records.sort_by_key(|r| r.legacy_id);
    write_new(
        path,
        serde_json::to_vec_pretty(&Identity {
            document_id: "richman4-tachiko-character-mirror".into(),
            records,
        })
        .unwrap_or_else(|e| fail(e.to_string()))
        .as_slice(),
    );
}
