use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
};

use serde::{Deserialize, Deserializer, de};
use serde_json::{Map, Value as JsonValue, json};
use tachiko_storage::{from_bytes, load_roproj, to_canonical_string};
use tachiko_workspace_engine::{
    Document, Entity, EntityId, FieldDefinition, FieldId, FieldType, Number, Schema, SchemaId,
    Value, validate,
};

const PREFIX: &str = "RICHMAN4_GODS_ORACLE=";
const COUNT: i64 = 15;
const MAX_SAFE_INTEGER: i64 = 9_007_199_254_740_991;
const SCHEMA_ID: &str = "schema-gods";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Candidate {
    gods: Vec<God>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(deny_unknown_fields)]
struct God {
    legacy_id: i64,
    display_name: String,
    pair_legacy_id: i64,
    duration_days: i64,
    role_key: String,
}

#[derive(Debug, Deserialize)]
struct Runtime {
    entities: BTreeMap<String, RuntimeEntity>,
}

#[derive(Debug, Deserialize)]
struct RuntimeEntity {
    fields: BTreeMap<String, JsonValue>,
}

/* Deserialize JSON through a visitor so duplicate object keys are rejected
 * before the typed candidate is admitted. serde_json also rejects non-finite
 * values when they reach visit_f64. */
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
            fn visit_bool<E>(self, value: bool) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Bool(value))
            }
            fn visit_i64<E>(self, value: i64) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Number(value.into()))
            }
            fn visit_u64<E>(self, value: u64) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::Number(value.into()))
            }
            fn visit_f64<E>(self, value: f64) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                serde_json::Number::from_f64(value)
                    .map(JsonValue::Number)
                    .ok_or_else(|| E::custom("non-finite JSON number"))
            }
            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::String(value.to_owned()))
            }
            fn visit_string<E>(self, value: String) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(JsonValue::String(value))
            }
            fn visit_seq<A>(self, mut access: A) -> Result<Self::Value, A::Error>
            where
                A: de::SeqAccess<'de>,
            {
                let mut values = Vec::new();
                while let Some(value) = access.next_element_seed(Seed)? {
                    values.push(value);
                }
                Ok(JsonValue::Array(values))
            }
            fn visit_map<A>(self, mut access: A) -> Result<Self::Value, A::Error>
            where
                A: de::MapAccess<'de>,
            {
                let mut values = Map::new();
                while let Some(key) = access.next_key::<String>()? {
                    if values.contains_key(&key) {
                        return Err(de::Error::custom(format!("duplicate JSON key: {key}")));
                    }
                    values.insert(key, access.next_value_seed(Seed)?);
                }
                Ok(JsonValue::Object(values))
            }
        }

        struct Seed;
        impl<'de> de::DeserializeSeed<'de> for Seed {
            type Value = JsonValue;

            fn deserialize<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
            where
                D: Deserializer<'de>,
            {
                deserializer.deserialize_any(Visitor)
            }
        }

        deserializer.deserialize_any(Visitor).map(Self)
    }
}

fn fail(message: impl Into<String>) -> ! {
    eprintln!("tachiko_gods_mirror: {}", message.into());
    std::process::exit(1)
}

fn read(path: &Path) -> Vec<u8> {
    fs::read(path).unwrap_or_else(|error| fail(format!("read {}: {error}", path.display())))
}

fn write_new(path: &Path, bytes: &[u8]) {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .unwrap_or_else(|error| fail(format!("create {}: {error}", path.display())));
    file.write_all(bytes)
        .and_then(|_| file.sync_all())
        .unwrap_or_else(|error| fail(format!("write {}: {error}", path.display())));
}

fn parse(bytes: &[u8]) -> JsonValue {
    if bytes.len() > 128 * 1024 {
        fail("JSON input exceeds 128 KiB")
    }
    serde_json::from_slice::<Strict>(bytes)
        .unwrap_or_else(|error| fail(format!("strict JSON parse failed: {error}")))
        .0
}

fn candidate(bytes: &[u8]) -> Candidate {
    let candidate = serde_json::from_value(parse(bytes))
        .unwrap_or_else(|error| fail(format!("god schema rejected: {error}")));
    validate_candidate(&candidate);
    candidate
}

fn validate_candidate(candidate: &Candidate) {
    if candidate.gods.len() != COUNT as usize {
        fail(format!("expected exactly {COUNT} gods"));
    }

    let mut ids = BTreeSet::new();
    for god in &candidate.gods {
        if !(1..=COUNT).contains(&god.legacy_id) || !ids.insert(god.legacy_id) {
            fail("legacy_id must be unique and exactly 1..15");
        }
        if god.display_name.trim().is_empty() {
            fail("display_name must be non-empty");
        }
        if !(0..=COUNT).contains(&god.pair_legacy_id) {
            fail("pair_legacy_id must be an integer in 0..15");
        }
        if god.pair_legacy_id == god.legacy_id {
            fail("pair_legacy_id must not self-reference");
        }
        if !(0..=MAX_SAFE_INTEGER).contains(&god.duration_days) {
            fail("duration_days must be a safe non-negative integer");
        }
        if god.role_key.trim().is_empty() {
            fail("role_key must be non-empty");
        }
    }
    if ids != (1..=COUNT).collect::<BTreeSet<_>>() {
        fail("legacy_id set must be exactly 1..15");
    }

    let by_id: BTreeMap<_, _> = candidate
        .gods
        .iter()
        .map(|god| (god.legacy_id, god))
        .collect();
    for god in &candidate.gods {
        if god.pair_legacy_id != 0 && by_id[&god.pair_legacy_id].pair_legacy_id != god.legacy_id {
            fail("pair_legacy_id references must be reciprocal");
        }
    }
}

fn field_id(key: &str) -> FieldId {
    format!("field-god-{key}").into()
}

fn entity_id(legacy_id: i64) -> EntityId {
    format!("sid-god-{legacy_id:02}").into()
}

fn number(value: i64, field: &str) -> Number {
    if !(0..=MAX_SAFE_INTEGER).contains(&value) {
        fail(format!("{field} outside Tachiko safe-integer range"));
    }
    Number::new(value as f64).unwrap_or_else(|error| fail(format!("{field}: {error}")))
}

fn schema() -> Schema {
    let id: SchemaId = SCHEMA_ID.into();
    let fields = [
        ("legacy_id", FieldType::Number, true),
        ("display_name", FieldType::Text, true),
        (
            "pair_legacy_id",
            FieldType::Reference {
                schema: SCHEMA_ID.into(),
            },
            false,
        ),
        ("duration_days", FieldType::Number, true),
        ("role_key", FieldType::Text, true),
    ]
    .into_iter()
    .map(|(key, field_type, required)| {
        let id = field_id(key);
        (
            id.clone(),
            FieldDefinition {
                id,
                key: key.into(),
                field_type,
                required,
            },
        )
    })
    .collect();
    Schema {
        id,
        key: "gods".into(),
        fields,
    }
}

fn document(candidate: &Candidate) -> Document {
    validate_candidate(candidate);
    let schema = schema();
    let mut schemas = BTreeMap::new();
    schemas.insert(schema.id.clone(), schema);

    let mut entities = BTreeMap::new();
    let mut rows = candidate.gods.clone();
    rows.sort_by_key(|god| god.legacy_id);
    for god in rows {
        let id = entity_id(god.legacy_id);
        let mut fields = BTreeMap::new();
        fields.insert(
            field_id("legacy_id"),
            Value::Number(number(god.legacy_id, "legacy_id")),
        );
        fields.insert(
            field_id("display_name"),
            Value::Text(god.display_name.clone()),
        );
        if god.pair_legacy_id != 0 {
            fields.insert(
                field_id("pair_legacy_id"),
                Value::Reference(entity_id(god.pair_legacy_id)),
            );
        }
        fields.insert(
            field_id("duration_days"),
            Value::Number(number(god.duration_days, "duration_days")),
        );
        fields.insert(field_id("role_key"), Value::Text(god.role_key.clone()));
        entities.insert(
            id.clone(),
            Entity {
                id,
                key: format!("god_{:02}", god.legacy_id).into(),
                schema: SCHEMA_ID.into(),
                fields,
            },
        );
    }
    Document {
        id: "richman4-tachiko-gods-mirror".into(),
        title: "Richman4 Tachiko god mirror".into(),
        schemas,
        entities,
    }
}

fn publish(candidate: &Candidate, path: &Path) {
    let document = document(candidate);
    validate(&document)
        .unwrap_or_else(|error| fail(format!("Rust validation rejected document: {error}")));
    let bytes = to_canonical_string(&document)
        .unwrap_or_else(|error| fail(format!("Rust storage encoding failed: {error}")));
    write_new(path, bytes.as_bytes());
}

fn import_log(path: &Path) -> Candidate {
    let data = read(path);
    let records: Vec<&[u8]> = data
        .split(|byte| *byte == b'\n')
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

fn runtime_number(value: &JsonValue, field: &str) -> i64 {
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|number| i64::try_from(number).ok()))
        .or_else(|| {
            value.as_f64().and_then(|number| {
                if number.is_finite()
                    && number.fract() == 0.0
                    && number >= 0.0
                    && number <= MAX_SAFE_INTEGER as f64
                {
                    Some(number as i64)
                } else {
                    None
                }
            })
        })
        .unwrap_or_else(|| fail(format!("runtime {field} must be a safe integer")));
    if !(0..=MAX_SAFE_INTEGER).contains(&number) {
        fail(format!("runtime {field} outside safe integer range"));
    }
    number
}

fn runtime_text(value: &JsonValue, field: &str) -> String {
    value
        .as_str()
        .filter(|text| !text.trim().is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| fail(format!("runtime {field} must be non-empty text")))
}

fn runtime_pair(value: Option<&JsonValue>, field: &str) -> i64 {
    let Some(value) = value else { return 0 };
    let reference = value
        .get("reference")
        .and_then(JsonValue::as_str)
        .unwrap_or_else(|| fail(format!("runtime {field} must be a Tachiko reference")));
    let id = reference
        .strip_prefix("god_")
        .and_then(|suffix| suffix.parse::<i64>().ok())
        .unwrap_or_else(|| fail(format!("runtime {field} has unknown reference {reference}")));
    if !(1..=COUNT).contains(&id) {
        fail(format!("runtime {field} reference outside 1..15"));
    }
    id
}

fn normalize(path: &Path, output: &Path) {
    let runtime: Runtime = serde_json::from_slice(&read(path))
        .unwrap_or_else(|error| fail(format!("runtime JSON rejected: {error}")));

    let expected_entities: BTreeSet<String> =
        (1..=COUNT).map(|id| format!("god_{id:02}")).collect();
    let actual_entities: BTreeSet<String> = runtime.entities.keys().cloned().collect();
    if actual_entities != expected_entities {
        fail(format!(
            "runtime entities must be exactly god_01 through god_15; got {actual_entities:?}"
        ));
    }
    for id in 1..=COUNT {
        let key = format!("god_{id:02}");
        let fields = &runtime.entities[&key].fields;
        let mut expected_fields: BTreeSet<String> =
            ["legacy_id", "display_name", "duration_days", "role_key"]
                .into_iter()
                .map(str::to_owned)
                .collect();
        if id <= 12 {
            expected_fields.insert("pair_legacy_id".to_owned());
        }
        let actual_fields: BTreeSet<String> = fields.keys().cloned().collect();
        if actual_fields != expected_fields {
            fail(format!(
                "runtime entity {key} fields must be exactly {expected_fields:?}; got {actual_fields:?}"
            ));
        }
    }

    let mut rows = Vec::new();
    for id in 1..=COUNT {
        let key = format!("god_{id:02}");
        let entity = runtime
            .entities
            .get(&key)
            .unwrap_or_else(|| fail(format!("runtime entity missing: {key}")));
        let fields = &entity.fields;
        let legacy_id = runtime_number(
            fields
                .get("legacy_id")
                .unwrap_or_else(|| fail("runtime legacy_id missing")),
            "legacy_id",
        );
        if legacy_id != id {
            fail(format!(
                "runtime entity key/value mismatch: {key} has legacy_id {legacy_id}"
            ));
        }
        rows.push(json!({
            "legacy_id": legacy_id,
            "display_name": runtime_text(fields.get("display_name").unwrap_or_else(|| fail("runtime display_name missing")), "display_name"),
            "pair_legacy_id": runtime_pair(fields.get("pair_legacy_id"), "pair_legacy_id"),
            "duration_days": runtime_number(fields.get("duration_days").unwrap_or_else(|| fail("runtime duration_days missing")), "duration_days"),
            "role_key": runtime_text(fields.get("role_key").unwrap_or_else(|| fail("runtime role_key missing")), "role_key"),
        }));
    }
    write_new(
        output,
        serde_json::to_vec_pretty(&json!({"gods": rows}))
            .unwrap_or_else(|error| fail(format!("projection encoding failed: {error}")))
            .as_slice(),
    );
}

fn identity_document(document: &Document, output: &Path) {
    let schema = document
        .schemas
        .values()
        .find(|schema| schema.key.as_str() == "gods")
        .unwrap_or_else(|| fail("gods schema missing from storage"));
    let mut field_ids = Map::new();
    for (key, expected_type, expected_required) in [
        ("legacy_id", FieldType::Number, true),
        ("display_name", FieldType::Text, true),
        (
            "pair_legacy_id",
            FieldType::Reference {
                schema: SCHEMA_ID.into(),
            },
            false,
        ),
        ("duration_days", FieldType::Number, true),
        ("role_key", FieldType::Text, true),
    ] {
        let field = schema
            .fields
            .values()
            .find(|field| field.key.as_str() == key)
            .unwrap_or_else(|| fail(format!("god field missing from storage: {key}")));
        if field.field_type != expected_type || field.required != expected_required {
            fail(format!(
                "god field has wrong stored type or required flag: {key}"
            ));
        }
        field_ids.insert(key.to_owned(), JsonValue::String(field.id.to_string()));
    }

    let mut rows = Vec::new();
    for entity in document.entities.values() {
        if !entity.key.as_str().starts_with("god_") {
            continue;
        }
        let expected_key =
            match entity
                .fields
                .get(&field_id("legacy_id"))
                .and_then(|value| match value {
                    Value::Number(number) => Some(number.get() as i64),
                    _ => None,
                }) {
                Some(legacy_id) if (1..=COUNT).contains(&legacy_id) => {
                    format!("god_{legacy_id:02}")
                }
                _ => fail(format!("{} has invalid typed legacy_id", entity.key)),
            };
        if entity.key.as_str() != expected_key {
            fail(format!(
                "god entity key/value mismatch: {} is not {expected_key}",
                entity.key
            ));
        }
        let legacy_id = match entity.fields.get(&field_id("legacy_id")) {
            Some(Value::Number(value)) => value.get() as i64,
            _ => fail(format!("{} has no typed legacy_id", entity.key)),
        };
        if !(1..=COUNT).contains(&legacy_id) {
            fail("stored legacy_id outside 1..15");
        }
        rows.push(json!({"legacy_id": legacy_id, "entity_id": entity.id.to_string()}));
    }
    rows.sort_by_key(|row| row["legacy_id"].as_i64().unwrap_or(0));
    if rows.len() != COUNT as usize {
        fail("stored god entity count mismatch");
    }
    write_new(
        output,
        serde_json::to_vec_pretty(&json!({
            "document_id": document.id,
            "schema_id": schema.id,
            "field_ids": field_ids,
            "rows": rows,
        }))
        .unwrap_or_else(|error| fail(format!("identity encoding failed: {error}")))
        .as_slice(),
    );
}

fn identity_ro(input: &Path, output: &Path) {
    let document =
        from_bytes(&read(input)).unwrap_or_else(|error| fail(format!("load .ro failed: {error}")));
    identity_document(&document, output);
}

fn identity_project(input: &Path, output: &Path) {
    let document =
        load_roproj(input).unwrap_or_else(|error| fail(format!("load .roproj failed: {error}")));
    identity_document(&document, output);
}

fn compare_ro_roproj(ro_path: &Path, project_path: &Path) {
    let ro = from_bytes(&read(ro_path))
        .unwrap_or_else(|error| fail(format!("load .ro failed: {error}")));
    let project = load_roproj(project_path)
        .unwrap_or_else(|error| fail(format!("load .roproj failed: {error}")));
    if ro != project {
        fail(".ro and .roproj semantic documents differ");
    }
}

fn check_edit(before_path: &Path, after_path: &Path) {
    let before = load_roproj(before_path)
        .unwrap_or_else(|error| fail(format!("load base .roproj failed: {error}")));
    let after = load_roproj(after_path)
        .unwrap_or_else(|error| fail(format!("load edited .roproj failed: {error}")));
    if before.id != after.id || before.title != after.title || before.schemas != after.schemas {
        fail("edited document changed document metadata or schema");
    }
    if before.entities.len() != COUNT as usize
        || before.entities.len() != after.entities.len()
        || before.entities.keys().ne(after.entities.keys())
    {
        fail("edited document changed entity membership");
    }

    let target_entity = entity_id(1);
    let target_field = field_id("display_name");
    let mut target_changed = false;
    for (id, before_entity) in &before.entities {
        let after_entity = after
            .entities
            .get(id)
            .unwrap_or_else(|| fail(format!("edited entity missing: {id}")));
        if before_entity.id != after_entity.id
            || before_entity.key != after_entity.key
            || before_entity.schema != after_entity.schema
            || before_entity.fields.keys().ne(after_entity.fields.keys())
        {
            fail(format!("edited entity metadata changed: {id}"));
        }
        for (field, before_value) in &before_entity.fields {
            let after_value = after_entity
                .fields
                .get(field)
                .unwrap_or_else(|| fail(format!("edited field missing: {id}/{field}")));
            if id == &target_entity && field == &target_field {
                if before_value != &Value::Text("小財神".into())
                    || after_value != &Value::Text("小財神（M4驗證）".into())
                {
                    fail("edited target field has an unexpected value");
                }
                target_changed = true;
            } else if before_value != after_value {
                fail(format!("unexpected edited field value: {id}/{field}"));
            }
        }
    }
    if !target_changed {
        fail("expected god_01.display_name edit was not observed");
    }
}

fn reorder(input: &Path, output: &Path) {
    let mut root = parse(&read(input));
    let rows = root
        .get_mut("gods")
        .and_then(JsonValue::as_array_mut)
        .unwrap_or_else(|| fail("gods missing"));
    rows.reverse();
    write_new(
        output,
        serde_json::to_vec_pretty(&root)
            .unwrap_or_else(|error| fail(format!("reordered candidate encoding failed: {error}")))
            .as_slice(),
    );
}

fn main() {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("candidate") => {
            let input = args
                .next()
                .unwrap_or_else(|| fail("candidate input missing"));
            let output = args.next().unwrap_or_else(|| fail(".ro output missing"));
            publish(&candidate(&read(Path::new(&input))), Path::new(&output));
        }
        Some("import-log") => {
            let input = args.next().unwrap_or_else(|| fail("Godot log missing"));
            let output = args.next().unwrap_or_else(|| fail(".ro output missing"));
            publish(&import_log(Path::new(&input)), Path::new(&output));
        }
        Some("normalize") => {
            let input = args.next().unwrap_or_else(|| fail("runtime input missing"));
            let output = args
                .next()
                .unwrap_or_else(|| fail("projection output missing"));
            normalize(Path::new(&input), Path::new(&output));
        }
        Some("identity") => {
            let input = args.next().unwrap_or_else(|| fail(".roproj input missing"));
            let output = args
                .next()
                .unwrap_or_else(|| fail("identity output missing"));
            identity_project(Path::new(&input), Path::new(&output));
        }
        Some("identity-ro") => {
            let input = args.next().unwrap_or_else(|| fail(".ro input missing"));
            let output = args
                .next()
                .unwrap_or_else(|| fail("identity output missing"));
            identity_ro(Path::new(&input), Path::new(&output));
        }
        Some("check-edit") => {
            let before = args
                .next()
                .unwrap_or_else(|| fail("base .roproj input missing"));
            let after = args
                .next()
                .unwrap_or_else(|| fail("edited .roproj input missing"));
            check_edit(Path::new(&before), Path::new(&after));
        }
        Some("compare-ro-roproj") => {
            let ro = args.next().unwrap_or_else(|| fail(".ro input missing"));
            let project = args.next().unwrap_or_else(|| fail(".roproj input missing"));
            compare_ro_roproj(Path::new(&ro), Path::new(&project));
        }
        Some("reorder") => {
            let input = args
                .next()
                .unwrap_or_else(|| fail("candidate input missing"));
            let output = args
                .next()
                .unwrap_or_else(|| fail("candidate output missing"));
            reorder(Path::new(&input), Path::new(&output));
        }
        Some(command) => fail(format!("unknown command: {command}")),
        None => fail(
            "usage: candidate|import-log|normalize|identity|identity-ro|check-edit|compare-ro-roproj|reorder",
        ),
    }
}
