use std::{collections::{BTreeMap, BTreeSet}, env, fs::{self, OpenOptions}, io::Write, path::Path};

use serde::{de, Deserialize, Deserializer, Serialize};
use serde_json::{json, Map, Value as JsonValue};
use tachiko_storage::{load_roproj, to_canonical_string};
use tachiko_workspace_engine::{validate, Document, Entity, EntityId, FieldDefinition, FieldId, FieldType, Number, Schema, SchemaId, Value};

const PREFIX: &str = "RICHMAN4_CATALOG_ORACLE=";
const CARD_COUNT: usize = 30;
const TOOL_COUNT: usize = 13;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Catalog { card_capacity: i64, tool_capacity_per_type: i64, cards: Vec<Record>, tools: Vec<Record> }

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record { id: String, name: String, source_id: i64, initial_supply: i64, price: i64, source_flags: [i64; 2] }

#[derive(Debug, Deserialize)]
struct Runtime { entities: BTreeMap<String, RuntimeEntity> }

#[derive(Debug, Deserialize)]
struct RuntimeEntity { fields: BTreeMap<String, JsonValue> }

#[derive(Debug, Serialize)]
struct Manifest { document_id: String, source: String, records: Vec<ManifestRecord> }

#[derive(Debug, Serialize)]
struct ManifestRecord { category: String, source_id: i64, legacy_id: String, semantic_id: String }

struct Strict(JsonValue);

impl<'de> Deserialize<'de> for Strict {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where D: Deserializer<'de> {
        struct Visitor;
        impl<'de> de::Visitor<'de> for Visitor {
            type Value = JsonValue;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str("JSON") }
            fn visit_unit<E>(self) -> Result<Self::Value, E> where E: de::Error { Ok(JsonValue::Null) }
            fn visit_bool<E>(self, v: bool) -> Result<Self::Value, E> where E: de::Error { Ok(JsonValue::Bool(v)) }
            fn visit_i64<E>(self, v: i64) -> Result<Self::Value, E> where E: de::Error { Ok(JsonValue::Number(v.into())) }
            fn visit_u64<E>(self, v: u64) -> Result<Self::Value, E> where E: de::Error { Ok(JsonValue::Number(v.into())) }
            fn visit_f64<E>(self, v: f64) -> Result<Self::Value, E> where E: de::Error {
                serde_json::Number::from_f64(v).map(JsonValue::Number).ok_or_else(|| E::custom("non-finite JSON number"))
            }
            fn visit_str<E>(self, v: &str) -> Result<Self::Value, E> where E: de::Error { Ok(JsonValue::String(v.to_owned())) }
            fn visit_string<E>(self, v: String) -> Result<Self::Value, E> where E: de::Error { Ok(JsonValue::String(v)) }
            fn visit_seq<A>(self, mut a: A) -> Result<Self::Value, A::Error>
            where A: de::SeqAccess<'de> {
                let mut out = Vec::new();
                while let Some(value) = a.next_element_seed(Seed)? { out.push(value); }
                Ok(JsonValue::Array(out))
            }
            fn visit_map<A>(self, mut a: A) -> Result<Self::Value, A::Error>
            where A: de::MapAccess<'de> {
                let mut out = Map::new();
                while let Some(key) = a.next_key::<String>()? {
                    if out.contains_key(&key) { return Err(de::Error::custom(format!("duplicate JSON key: {key}"))); }
                    out.insert(key, a.next_value_seed(Seed)?);
                }
                Ok(JsonValue::Object(out))
            }
        }
        struct Seed;
        impl<'de> de::DeserializeSeed<'de> for Seed {
            type Value = JsonValue;
            fn deserialize<D>(self, d: D) -> Result<Self::Value, D::Error>
            where D: Deserializer<'de> { d.deserialize_any(Visitor) }
        }
        deserializer.deserialize_any(Visitor).map(Self)
    }
}

fn fail(message: impl Into<String>) -> ! { eprintln!("tachiko_mirror: {}", message.into()); std::process::exit(1) }
fn read(path: &Path) -> Vec<u8> { fs::read(path).unwrap_or_else(|e| fail(format!("read {}: {e}", path.display()))) }
fn write_new(path: &Path, bytes: &[u8]) {
    let mut f = OpenOptions::new().write(true).create_new(true).open(path)
        .unwrap_or_else(|e| fail(format!("create {}: {e}", path.display())));
    f.write_all(bytes).and_then(|_| f.sync_all()).unwrap_or_else(|e| fail(format!("write {}: {e}", path.display())));
}
fn json(bytes: &[u8]) -> JsonValue {
    serde_json::from_slice::<Strict>(bytes).unwrap_or_else(|e| fail(format!("strict JSON parse failed: {e}"))).0
}
fn catalog(bytes: &[u8]) -> Catalog {
    serde_json::from_value(json(bytes)).unwrap_or_else(|e| fail(format!("catalog schema rejected: {e}")))
}
fn log_catalog(path: &Path) -> Catalog {
    let data = read(path);
    let records: Vec<&[u8]> = data.split(|b| *b == b'\n').filter_map(|line| line.strip_prefix(PREFIX.as_bytes())).collect();
    if records.len() != 1 { fail(format!("expected one {PREFIX} record, found {}", records.len())); }
    catalog(records[0])
}
fn consumer_check(c: &Catalog) {
    if c.card_capacity != 15 || c.tool_capacity_per_type != 9 || c.cards.len() != CARD_COUNT || c.tools.len() != TOOL_COUNT { fail("consumer count/capacity mismatch"); }
    for (category, rows) in [("card", &c.cards), ("tool", &c.tools)] {
        let mut ids = BTreeSet::new();
        for (i, row) in rows.iter().enumerate() {
            if row.id.is_empty() || !ids.insert(row.id.as_str()) { fail(format!("{category} identity missing/duplicated at {}", i + 1)); }
            if row.source_id != i as i64 + 1 { fail(format!("{category} source_id mismatch at {}", i + 1)); }
            if row.initial_supply < 0 || row.price < 0 { fail(format!("{category} negative numeric at {}", i + 1)); }
        }
    }
}
fn num(v: i64) -> Number { Number::new(v as f64).unwrap_or_else(|e| fail(format!("number rejected: {e}"))) }
fn fid(category: &str, key: &str) -> FieldId { format!("field-{category}-{key}").into() }
fn eid(category: &str, legacy_id: &str) -> EntityId {
    let mut hash = 14_695_981_039_346_656_037_u64;
    for byte in b"richman4/tachiko/catalog/entity/v2:".iter().chain(category.as_bytes()).chain([0_u8].iter()).chain(legacy_id.as_bytes()) {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    format!("sid-{hash:016x}").into()
}
fn make_schema(category: &str) -> (SchemaId, Schema) {
    let id: SchemaId = format!("schema-{category}").into();
    let fields = [
        ("legacy_id", FieldType::Text), ("display_name", FieldType::Text),
        ("source_id", FieldType::Number), ("initial_supply", FieldType::Number),
        ("point_price", FieldType::Number), ("source_flag_0", FieldType::Number),
        ("source_flag_1", FieldType::Number),
    ].into_iter().map(|(key, field_type)| {
        let id = fid(category, key);
        (id.clone(), FieldDefinition { id, key: key.into(), field_type, required: true })
    }).collect();
    (id.clone(), Schema { id, key: format!("catalog_{category}").into(), fields })
}
fn make_entity(category: &str, row: &Record) -> Entity {
    let id = eid(category, &row.id);
    let mut fields = BTreeMap::new();
    fields.insert(fid(category, "legacy_id"), Value::Text(row.id.clone()));
    fields.insert(fid(category, "display_name"), Value::Text(row.name.clone()));
    fields.insert(fid(category, "source_id"), Value::Number(num(row.source_id)));
    fields.insert(fid(category, "initial_supply"), Value::Number(num(row.initial_supply)));
    fields.insert(fid(category, "point_price"), Value::Number(num(row.price)));
    fields.insert(fid(category, "source_flag_0"), Value::Number(num(row.source_flags[0])));
    fields.insert(fid(category, "source_flag_1"), Value::Number(num(row.source_flags[1])));
    Entity { id, key: format!("{category}_{:02}", row.source_id).into(), schema: format!("schema-{category}").into(), fields }
}
fn document(c: &Catalog) -> Document {
    consumer_check(c);
    let (card_id, card) = make_schema("card");
    let (tool_id, tool) = make_schema("tool");
    let settings_id: SchemaId = "schema-settings".into();
    let settings_fields = [("card_capacity", FieldType::Number), ("tool_capacity_per_type", FieldType::Number)]
        .into_iter().map(|(key, field_type)| {
            let id: FieldId = format!("field-settings-{key}").into();
            (id.clone(), FieldDefinition { id, key: key.into(), field_type, required: true })
        }).collect();
    let settings = Schema { id: settings_id.clone(), key: "catalog_settings".into(), fields: settings_fields };
    let mut schemas = BTreeMap::new();
    schemas.insert(card_id, card); schemas.insert(tool_id, tool); schemas.insert(settings_id.clone(), settings);
    let mut entities = BTreeMap::new();
    for row in &c.cards { let e = make_entity("card", row); entities.insert(e.id.clone(), e); }
    for row in &c.tools { let e = make_entity("tool", row); entities.insert(e.id.clone(), e); }
    let settings_entity_id: EntityId = "opaque-settings".into();
    let mut fields = BTreeMap::new();
    fields.insert("field-settings-card_capacity".into(), Value::Number(num(c.card_capacity)));
    fields.insert("field-settings-tool_capacity_per_type".into(), Value::Number(num(c.tool_capacity_per_type)));
    entities.insert(settings_entity_id.clone(), Entity { id: settings_entity_id, key: "settings".into(), schema: settings_id, fields });
    Document { id: "richman4-tachiko-catalog-pilot".into(), title: "Richman4 Tachiko catalog pilot".into(), schemas, entities }
}
fn publish(d: &Document, path: &Path) {
    validate(d).unwrap_or_else(|e| fail(format!("Rust validation rejected document: {e}")));
    let bytes = to_canonical_string(d).unwrap_or_else(|e| fail(format!("Rust storage encoding failed: {e}")));
    write_new(path, bytes.as_bytes());
}
fn manifest(c: &Catalog, path: &Path) {
    let mut records = Vec::new();
    for (category, rows) in [("card", &c.cards), ("tool", &c.tools)] {
        for row in rows { records.push(ManifestRecord { category: category.into(), source_id: row.source_id, legacy_id: row.id.clone(), semantic_id: eid(category, &row.id).to_string() }); }
    }
    let m = Manifest { document_id: "richman4-tachiko-catalog-pilot".into(), source: "Godot public catalogue via source_oracle.gd".into(), records };
    write_new(path, serde_json::to_vec_pretty(&m).unwrap_or_else(|e| fail(e.to_string())).as_slice());
}
fn identity_from_roproj(input: &Path, output: &Path) {
    let document = load_roproj(input).unwrap_or_else(|e| fail(format!("load .roproj failed: {e}")));
    let mut records = Vec::new();
    for entity in document.entities.values() {
        let key = entity.key.as_str();
        let category = if key.starts_with("card_") { "card" } else if key.starts_with("tool_") { "tool" } else { continue };
        let legacy_id = match entity.fields.get(&fid(category, "legacy_id")) {
            Some(Value::Text(value)) => value.clone(),
            _ => fail(format!("{key} has no typed legacy_id")),
        };
        let source_id = match entity.fields.get(&fid(category, "source_id")) {
            Some(Value::Number(value)) if value.get().fract() == 0.0 => value.get() as i64,
            _ => fail(format!("{key} has no integer source_id")),
        };
        records.push(ManifestRecord { category: category.into(), source_id, legacy_id, semantic_id: entity.id.to_string() });
    }
    records.sort_by(|left, right| (&left.category, left.source_id).cmp(&(&right.category, right.source_id)));
    let mapping = Manifest { document_id: document.id.to_string(), source: "Tachiko .roproj typed identity projection".into(), records };
    write_new(output, serde_json::to_vec_pretty(&mapping).unwrap_or_else(|e| fail(e.to_string())).as_slice());
}
fn value(e: &RuntimeEntity, key: &str) -> JsonValue { e.fields.get(key).cloned().unwrap_or_else(|| fail(format!("runtime field missing: {key}"))) }
fn integer(v: JsonValue, key: &str) -> i64 {
    let n = v.as_f64().unwrap_or_else(|| fail(format!("runtime {key} is not numeric")));
    if !n.is_finite() || n.fract() != 0.0 || n < i64::MIN as f64 || n > i64::MAX as f64 { fail(format!("runtime {key} is not exact integer")); }
    n as i64
}
fn text(v: JsonValue, key: &str) -> String { v.as_str().map(str::to_owned).unwrap_or_else(|| fail(format!("runtime {key} is not text"))) }
fn projection(r: &Runtime) -> JsonValue {
    let settings = r.entities.get("settings").unwrap_or_else(|| fail("runtime settings missing"));
    let mut root = Map::new();
    root.insert("card_capacity".into(), integer(value(settings, "card_capacity"), "card_capacity").into());
    root.insert("tool_capacity_per_type".into(), integer(value(settings, "tool_capacity_per_type"), "tool_capacity_per_type").into());
    for (category, count) in [("card", CARD_COUNT), ("tool", TOOL_COUNT)] {
        let mut rows = Vec::new();
        for i in 1..=count {
            let key = format!("{category}_{i:02}");
            let e = r.entities.get(&key).unwrap_or_else(|| fail(format!("runtime entity missing: {key}")));
            rows.push(json!({
                "id": text(value(e, "legacy_id"), "legacy_id"),
                "name": text(value(e, "display_name"), "display_name"),
                "source_id": integer(value(e, "source_id"), "source_id"),
                "initial_supply": integer(value(e, "initial_supply"), "initial_supply"),
                "price": integer(value(e, "point_price"), "point_price"),
                "source_flags": [integer(value(e, "source_flag_0"), "source_flag_0"), integer(value(e, "source_flag_1"), "source_flag_1")]
            }));
        }
        root.insert(format!("{category}s"), JsonValue::Array(rows));
    }
    JsonValue::Object(root)
}
fn mutant(input: &Path, output: &Path, kind: &str) {
    if kind == "duplicate" {
        write_new(output, br#"{"card_capacity":15,"tool_capacity_per_type":9,"cards":[{"id":"x","id":"y","name":"x","source_id":1,"initial_supply":1,"price":1,"source_flags":[0,0]}],"tools":[]}"#);
        return;
    }
    let mut root = json(&read(input));
    let row = root.get_mut("cards").and_then(JsonValue::as_array_mut).and_then(|a| a.first_mut()).and_then(JsonValue::as_object_mut).unwrap_or_else(|| fail("cards[0] missing"));
    match kind {
        "missing-identity" => { row.remove("id"); }
        "wrong-type" => { row.insert("price".into(), JsonValue::String("200".into())); }
        "fraction" => { row.insert("price".into(), json!(200.5)); }
        "negative-supply" => { row.insert("initial_supply".into(), json!(-1)); }
        "unknown-field" => { row.insert("unexpected".into(), JsonValue::Bool(true)); }
        _ => fail(format!("unknown mutant: {kind}")),
    }
    write_new(output, serde_json::to_vec_pretty(&root).unwrap_or_else(|e| fail(e.to_string())).as_slice());
}
fn main() {
    let mut a = env::args().skip(1);
    match a.next().as_deref() {
        Some("import-log") => {
            let c = log_catalog(Path::new(&a.next().unwrap_or_else(|| fail("log missing"))));
            let d = document(&c);
            publish(&d, Path::new(&a.next().unwrap_or_else(|| fail("ro output missing"))));
            manifest(&c, Path::new(&a.next().unwrap_or_else(|| fail("manifest missing"))));
        }
        Some("candidate") => {
            let c = catalog(&read(Path::new(&a.next().unwrap_or_else(|| fail("candidate missing")))));
            publish(&document(&c), Path::new(&a.next().unwrap_or_else(|| fail("ro output missing"))));
        }
        Some("normalize") => {
            let r: Runtime = serde_json::from_slice(&read(Path::new(&a.next().unwrap_or_else(|| fail("runtime missing"))))).unwrap_or_else(|e| fail(format!("runtime rejected: {e}")));
            write_new(Path::new(&a.next().unwrap_or_else(|| fail("projection missing"))), serde_json::to_vec_pretty(&projection(&r)).unwrap_or_else(|e| fail(e.to_string())).as_slice());
        }
        Some("identity") => identity_from_roproj(Path::new(&a.next().unwrap_or_else(|| fail("roproj missing"))), Path::new(&a.next().unwrap_or_else(|| fail("identity output missing")))),
        Some("mutant") => mutant(Path::new(&a.next().unwrap_or_else(|| fail("input missing"))), Path::new(&a.next().unwrap_or_else(|| fail("output missing"))), &a.next().unwrap_or_else(|| fail("kind missing"))),
        Some(other) => fail(format!("unknown command: {other}")),
        None => fail("usage: import-log|candidate|normalize|mutant"),
    }
}
