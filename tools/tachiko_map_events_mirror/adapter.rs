use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
};

use serde::{de, Deserialize, Deserializer};
use serde_json::{json, Map, Number as JsonNumber, Value as JsonValue};
use tachiko_storage::{from_bytes, load_roproj, to_canonical_string};
use tachiko_workspace_engine::{
    validate, Document, Entity, EntityId, FieldDefinition, FieldId, FieldType, Number, Schema,
    SchemaId, Value,
};

const PREFIX: &str = "RICHMAN4_MAP_EVENTS_ORACLE=";
const COUNT: i64 = 17;
const MAX_SAFE_INTEGER: i64 = 9_007_199_254_740_991;
const SCHEMA_ID: &str = "schema-map-events";
const RUNTIME_FORMAT_VERSION: u32 = 2;
const RUNTIME_DOCUMENT_ID: &str = "richman4-tachiko-map-events-mirror";
const RUNTIME_TITLE: &str = "Richman4 Tachiko map event mirror";
const RUNTIME_SCHEMA_KEY: &str = "event_names";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Candidate {
    event_names: Vec<Event>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(deny_unknown_fields)]
struct Event {
    #[serde(deserialize_with = "deserialize_integral")]
    event_code: i64,
    display_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Runtime {
    format_version: u32,
    document_id: String,
    title: String,
    entities: BTreeMap<String, RuntimeEntity>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RuntimeEntity {
    schema: String,
    fields: RuntimeFields,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RuntimeFields {
    event_code: JsonNumber,
    display_name: String,
}

/* Deserialize through a visitor so duplicate object keys are rejected before
 * typed admission. serde_json rejects non-finite JSON constants. */
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
            fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
                Ok(JsonValue::Null)
            }
            fn visit_bool<E: de::Error>(self, value: bool) -> Result<Self::Value, E> {
                Ok(JsonValue::Bool(value))
            }
            fn visit_i64<E: de::Error>(self, value: i64) -> Result<Self::Value, E> {
                Ok(JsonValue::Number(value.into()))
            }
            fn visit_u64<E: de::Error>(self, value: u64) -> Result<Self::Value, E> {
                Ok(JsonValue::Number(value.into()))
            }
            fn visit_f64<E: de::Error>(self, value: f64) -> Result<Self::Value, E> {
                serde_json::Number::from_f64(value)
                    .map(JsonValue::Number)
                    .ok_or_else(|| E::custom("non-finite JSON number"))
            }
            fn visit_str<E: de::Error>(self, value: &str) -> Result<Self::Value, E> {
                Ok(JsonValue::String(value.to_owned()))
            }
            fn visit_string<E: de::Error>(self, value: String) -> Result<Self::Value, E> {
                Ok(JsonValue::String(value))
            }
            fn visit_seq<A: de::SeqAccess<'de>>(
                self,
                mut access: A,
            ) -> Result<Self::Value, A::Error> {
                let mut values = Vec::new();
                while let Some(value) = access.next_element_seed(Seed)? {
                    values.push(value);
                }
                Ok(JsonValue::Array(values))
            }
            fn visit_map<A: de::MapAccess<'de>>(
                self,
                mut access: A,
            ) -> Result<Self::Value, A::Error> {
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
    eprintln!("tachiko_map_events_mirror: {}", message.into());
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

fn exact_integral(value: &JsonNumber) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|value| i64::try_from(value).ok()))
        .or_else(|| {
            value.as_f64().and_then(|value| {
                if value.is_finite() && value.fract() == 0.0 {
                    i64::try_from(value as i128).ok()
                } else {
                    None
                }
            })
        })
}

fn deserialize_integral<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: Deserializer<'de>,
{
    let value = JsonNumber::deserialize(deserializer)?;
    exact_integral(&value).ok_or_else(|| de::Error::custom("expected an exact finite integer"))
}

fn candidate(bytes: &[u8]) -> Candidate {
    let candidate = serde_json::from_value(parse(bytes))
        .unwrap_or_else(|error| fail(format!("map-event schema rejected: {error}")));
    validate_candidate(&candidate);
    candidate
}

fn validate_candidate(candidate: &Candidate) {
    if candidate.event_names.len() != COUNT as usize {
        fail(format!("expected exactly {COUNT} map event rows"));
    }
    let mut codes = BTreeSet::new();
    for event in &candidate.event_names {
        if !(0..COUNT).contains(&event.event_code) || !codes.insert(event.event_code) {
            fail("event_code must be unique and exactly 0..16");
        }
        if event.display_name.trim().is_empty() {
            fail("display_name must be non-empty");
        }
    }
    if codes != (0..COUNT).collect::<BTreeSet<_>>() {
        fail("event_code set must be exactly 0..16");
    }
}

fn field_id(key: &str) -> FieldId {
    format!("field-map-event-{key}").into()
}

fn entity_id(event_code: i64) -> EntityId {
    format!("sid-map-event-{event_code:02}").into()
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
        ("event_code", FieldType::Number, true),
        ("display_name", FieldType::Text, true),
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
        key: RUNTIME_SCHEMA_KEY.into(),
        fields,
    }
}

fn document(candidate: &Candidate) -> Document {
    validate_candidate(candidate);
    let schema = schema();
    let mut schemas = BTreeMap::new();
    schemas.insert(schema.id.clone(), schema);
    let mut entities = BTreeMap::new();
    let mut rows = candidate.event_names.clone();
    rows.sort_by_key(|event| event.event_code);
    for event in rows {
        let id = entity_id(event.event_code);
        let fields = BTreeMap::from([
            (
                field_id("event_code"),
                Value::Number(number(event.event_code, "event_code")),
            ),
            (field_id("display_name"), Value::Text(event.display_name)),
        ]);
        entities.insert(
            id.clone(),
            Entity {
                id,
                key: format!("event_{:02}", event.event_code).into(),
                schema: SCHEMA_ID.into(),
                fields,
            },
        );
    }
    Document {
        id: RUNTIME_DOCUMENT_ID.into(),
        title: RUNTIME_TITLE.into(),
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

fn runtime_number(value: &JsonNumber) -> i64 {
    let number =
        exact_integral(value).unwrap_or_else(|| fail("runtime event_code must be an integer"));
    if !(0..COUNT).contains(&number) {
        fail("runtime event_code outside 0..16");
    }
    number
}

fn runtime_text(value: &str) -> String {
    if value.trim().is_empty() {
        fail("runtime display_name must be non-empty text");
    }
    value.to_owned()
}

fn normalize(path: &Path, output: &Path) {
    let runtime: Runtime = serde_json::from_value(parse(&read(path)))
        .unwrap_or_else(|error| fail(format!("runtime JSON rejected: {error}")));
    if runtime.format_version != RUNTIME_FORMAT_VERSION
        || runtime.document_id != RUNTIME_DOCUMENT_ID
        || runtime.title != RUNTIME_TITLE
    {
        fail("runtime metadata does not match M5 document contract");
    }
    let expected: BTreeSet<String> = (0..COUNT).map(|code| format!("event_{code:02}")).collect();
    if runtime.entities.keys().cloned().collect::<BTreeSet<_>>() != expected {
        fail("runtime entities must be exactly event_00 through event_16");
    }
    let mut rows = Vec::new();
    for code in 0..COUNT {
        let key = format!("event_{code:02}");
        let entity = &runtime.entities[&key];
        if entity.schema != RUNTIME_SCHEMA_KEY {
            fail(format!("runtime entity {key} schema mismatch"));
        }
        let actual_code = runtime_number(&entity.fields.event_code);
        if actual_code != code {
            fail(format!(
                "runtime entity key/value mismatch: {key} has {actual_code}"
            ));
        }
        rows.push(json!({
            "event_code": actual_code,
            "display_name": runtime_text(&entity.fields.display_name),
        }));
    }
    write_new(
        output,
        serde_json::to_vec_pretty(&json!({"event_names": rows}))
            .unwrap_or_else(|error| fail(format!("projection encoding failed: {error}")))
            .as_slice(),
    );
}

fn identity_document(document: &Document, output: &Path) {
    let schema = document
        .schemas
        .values()
        .find(|schema| schema.key.as_str() == RUNTIME_SCHEMA_KEY)
        .unwrap_or_else(|| fail("event_names schema missing from storage"));
    if schema.fields.len() != 2 {
        fail("event_names schema has unexpected field count");
    }
    let mut field_ids = Map::new();
    for (key, expected_type) in [
        ("event_code", FieldType::Number),
        ("display_name", FieldType::Text),
    ] {
        let field = schema
            .fields
            .values()
            .find(|field| field.key.as_str() == key)
            .unwrap_or_else(|| fail(format!("event field missing from storage: {key}")));
        if field.field_type != expected_type || !field.required {
            fail(format!(
                "event field has wrong stored type or required flag: {key}"
            ));
        }
        field_ids.insert(key.to_owned(), JsonValue::String(field.id.to_string()));
    }
    let mut rows = Vec::new();
    for code in 0..COUNT {
        let expected_key = format!("event_{code:02}");
        let entity = document
            .entities
            .values()
            .find(|entity| entity.key.as_str() == expected_key)
            .unwrap_or_else(|| fail(format!("stored entity missing: {expected_key}")));
        if entity.schema.as_str() != SCHEMA_ID || entity.fields.len() != 2 {
            fail(format!(
                "stored entity has unexpected schema/fields: {expected_key}"
            ));
        }
        let stored_code = match entity.fields.get(&field_id("event_code")) {
            Some(Value::Number(value)) => value.get() as i64,
            _ => fail(format!("{expected_key} has no typed event_code")),
        };
        if stored_code != code || entity.id != entity_id(code) {
            fail(format!("stored event identity mismatch: {expected_key}"));
        }
        rows.push(json!({"event_code": code, "entity_id": entity.id.to_string()}));
    }
    if document.entities.len() != COUNT as usize {
        fail("stored event entity count mismatch");
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
    if before.entities.len() != COUNT as usize || after.entities != before.entities {
        let target = entity_id(16);
        let before_entity = before
            .entities
            .get(&target)
            .unwrap_or_else(|| fail("target event entity missing"));
        let after_entity = after
            .entities
            .get(&target)
            .unwrap_or_else(|| fail("edited target event entity missing"));
        if before.entities.len() != after.entities.len()
            || before.entities.keys().ne(after.entities.keys())
        {
            fail("edited document changed entity membership");
        }
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
                    .unwrap_or_else(|| fail(format!("edited field missing: {id}")));
                if id == &target && field == &field_id("display_name") {
                    if before_value != &Value::Text("魔法屋".into())
                        || after_value != &Value::Text("魔法屋（M5驗證）".into())
                    {
                        fail("edited target field has an unexpected value");
                    }
                } else if before_value != after_value {
                    fail(format!("unexpected edited field value: {id}/{field}"));
                }
            }
        }
        if before_entity.id != after_entity.id {
            fail("edited target identity changed");
        }
    } else {
        fail("edited document did not contain the isolated M5 change");
    }
}

fn reorder(input: &Path, output: &Path) {
    let mut root = parse(&read(input));
    let rows = root
        .get_mut("event_names")
        .and_then(JsonValue::as_array_mut)
        .unwrap_or_else(|| fail("event_names missing"));
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
            let input = args.next().unwrap_or_else(|| fail("candidate input missing"));
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
            let output = args.next().unwrap_or_else(|| fail("projection output missing"));
            normalize(Path::new(&input), Path::new(&output));
        }
        Some("identity") => {
            let input = args.next().unwrap_or_else(|| fail(".roproj input missing"));
            let output = args.next().unwrap_or_else(|| fail("identity output missing"));
            identity_project(Path::new(&input), Path::new(&output));
        }
        Some("identity-ro") => {
            let input = args.next().unwrap_or_else(|| fail(".ro input missing"));
            let output = args.next().unwrap_or_else(|| fail("identity output missing"));
            identity_ro(Path::new(&input), Path::new(&output));
        }
        Some("check-edit") => {
            let before = args.next().unwrap_or_else(|| fail("base .roproj input missing"));
            let after = args.next().unwrap_or_else(|| fail("edited .roproj input missing"));
            check_edit(Path::new(&before), Path::new(&after));
        }
        Some("compare-ro-roproj") => {
            let ro = args.next().unwrap_or_else(|| fail(".ro input missing"));
            let project = args.next().unwrap_or_else(|| fail(".roproj input missing"));
            compare_ro_roproj(Path::new(&ro), Path::new(&project));
        }
        Some("reorder") => {
            let input = args.next().unwrap_or_else(|| fail("candidate input missing"));
            let output = args.next().unwrap_or_else(|| fail("candidate output missing"));
            reorder(Path::new(&input), Path::new(&output));
        }
        Some(command) => fail(format!("unknown command: {command}")),
        None => fail("usage: candidate|import-log|normalize|identity|identity-ro|check-edit|compare-ro-roproj|reorder"),
    }
}
