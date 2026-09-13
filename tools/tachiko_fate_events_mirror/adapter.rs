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

const PREFIX: &str = "RICHMAN4_FATE_EVENTS_ORACLE=";
const COUNT: i64 = 37;
const MAX_SAFE_INTEGER: i64 = 9_007_199_254_740_991;
const MAX_TEXT_LENGTH: usize = 256;
const SCHEMA_ID: &str = "schema-fate-events";
const RUNTIME_FORMAT_VERSION: u32 = 2;
const RUNTIME_DOCUMENT_ID: &str = "richman4-tachiko-fate-events-mirror";
const RUNTIME_TITLE: &str = "Richman4 Tachiko fate event mirror";
const RUNTIME_SCHEMA_KEY: &str = "fate_names";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Candidate {
    fate_names: Vec<Event>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(deny_unknown_fields)]
struct Event {
    #[serde(deserialize_with = "deserialize_integral")]
    fate_id: i64,
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
    #[serde(rename = "fate_id")]
    _fate_id: JsonNumber,
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
    eprintln!("tachiko_fate_events_mirror: {}", message.into());
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
}

/* The temporary M7 manifest does not enable serde_json arbitrary precision,
 * so runtime numbers must be checked from their source lexemes.  This avoids
 * accepting a decimal/exponent value merely because f64 rounded it to an int.
 */
fn runtime_exact_integral(lexeme: &str) -> Option<i64> {
    let bytes = lexeme.as_bytes();
    let mut position = 0;
    let negative = bytes.get(position) == Some(&b'-');
    if negative {
        position += 1;
    }

    let integer_start = position;
    while bytes.get(position).is_some_and(|byte| byte.is_ascii_digit()) {
        position += 1;
    }
    if position == integer_start {
        return None;
    }
    let integer_digits = &bytes[integer_start..position];

    let fractional_digits = if bytes.get(position) == Some(&b'.') {
        position += 1;
        let start = position;
        while bytes.get(position).is_some_and(|byte| byte.is_ascii_digit()) {
            position += 1;
        }
        if position == start {
            return None;
        }
        &bytes[start..position]
    } else {
        &[]
    };

    let exponent = if bytes
        .get(position)
        .is_some_and(|byte| *byte == b'e' || *byte == b'E')
    {
        position += 1;
        let exponent_negative = match bytes.get(position) {
            Some(b'-') => {
                position += 1;
                true
            }
            Some(b'+') => {
                position += 1;
                false
            }
            _ => false,
        };
        let start = position;
        let mut value = 0i64;
        while let Some(byte) = bytes.get(position) {
            if !byte.is_ascii_digit() {
                break;
            }
            value = value.checked_mul(10)?.checked_add(i64::from(byte - b'0'))?;
            position += 1;
        }
        if position == start {
            return None;
        }
        if exponent_negative {
            value.checked_neg()?
        } else {
            value
        }
    } else {
        0
    };
    if position != bytes.len() {
        return None;
    }

    let coefficient_len = integer_digits.len() + fractional_digits.len();
    let decimal_position = integer_digits.len() as i128 + i128::from(exponent);
    let coefficient = integer_digits
        .iter()
        .chain(fractional_digits.iter())
        .copied()
        .collect::<Vec<_>>();
    if coefficient.iter().all(|digit| *digit == b'0') {
        return Some(0);
    }
    if decimal_position <= 0 {
        return None;
    }

    let significant_end = usize::try_from(decimal_position.min(coefficient_len as i128)).ok()?;
    if coefficient[significant_end..]
        .iter()
        .any(|digit| *digit != b'0')
    {
        return None;
    }

    let mut magnitude = 0i128;
    for digit in &coefficient[..significant_end] {
        magnitude = magnitude
            .checked_mul(10)?
            .checked_add(i128::from(digit - b'0'))?;
    }
    let trailing_zeroes = decimal_position - coefficient_len as i128;
    if trailing_zeroes > 0 {
        if trailing_zeroes > 38 {
            return None;
        }
        for _ in 0..usize::try_from(trailing_zeroes).ok()? {
            magnitude = magnitude.checked_mul(10)?;
        }
    }
    let signed = if negative { -magnitude } else { magnitude };
    i64::try_from(signed).ok()
}

/* Keep only the raw numbers needed after the strict typed parse. */
enum RawJson {
    Object(BTreeMap<String, RawJson>),
    Array(Vec<RawJson>),
    Number(String),
    Other,
}

struct RawParser<'a> {
    bytes: &'a [u8],
    position: usize,
    reject_non_integral_numbers: bool,
}

impl<'a> RawParser<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self {
            bytes,
            position: 0,
            reject_non_integral_numbers: true,
        }
    }

    fn for_candidate(bytes: &'a [u8]) -> Self {
        Self {
            bytes,
            position: 0,
            reject_non_integral_numbers: false,
        }
    }

    fn whitespace(&mut self) {
        while self
            .bytes
            .get(self.position)
            .is_some_and(|byte| byte.is_ascii_whitespace())
        {
            self.position += 1;
        }
    }

    fn string(&mut self) -> String {
        let start = self.position;
        self.position += 1;
        while let Some(byte) = self.bytes.get(self.position) {
            match byte {
                b'\\' => self.position += 2,
                b'"' => {
                    self.position += 1;
                    return serde_json::from_slice(&self.bytes[start..self.position])
                        .unwrap_or_else(|error| fail(format!("runtime JSON string rejected: {error}")));
                }
                _ => self.position += 1,
            }
        }
        fail("runtime JSON string is unterminated")
    }

    fn value(&mut self) -> RawJson {
        self.whitespace();
        match self.bytes.get(self.position) {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => {
                self.string();
                RawJson::Other
            }
            Some(byte) if *byte == b'-' || byte.is_ascii_digit() => {
                let start = self.position;
                while self.bytes.get(self.position).is_some_and(|byte| {
                    byte.is_ascii_digit()
                        || matches!(*byte, b'-' | b'+' | b'.' | b'e' | b'E')
                }) {
                    self.position += 1;
                }
                let lexeme = String::from_utf8(self.bytes[start..self.position].to_vec())
                    .unwrap_or_else(|error| fail(format!("runtime number rejected: {error}")));
                if self.reject_non_integral_numbers && runtime_exact_integral(&lexeme).is_none() {
                    fail("runtime JSON contains a non-integral or ambiguous number");
                }
                RawJson::Number(lexeme)
            }
            Some(_) => {
                while self.bytes.get(self.position).is_some_and(|byte| {
                    !byte.is_ascii_whitespace() && !matches!(*byte, b',' | b']' | b'}')
                }) {
                    self.position += 1;
                }
                RawJson::Other
            }
            None => fail("runtime JSON value missing"),
        }
    }

    fn object(&mut self) -> RawJson {
        self.position += 1;
        let mut values = BTreeMap::new();
        loop {
            self.whitespace();
            if self.bytes.get(self.position) == Some(&b'}') {
                self.position += 1;
                return RawJson::Object(values);
            }
            if self.bytes.get(self.position) != Some(&b'"') {
                fail("runtime JSON object key missing");
            }
            let key = self.string();
            self.whitespace();
            if self.bytes.get(self.position) != Some(&b':') {
                fail("runtime JSON object colon missing");
            }
            self.position += 1;
            let value = self.value();
            values.insert(key, value);
            self.whitespace();
            match self.bytes.get(self.position) {
                Some(b',') => self.position += 1,
                Some(b'}') => {
                    self.position += 1;
                    return RawJson::Object(values);
                }
                _ => fail("runtime JSON object separator missing"),
            }
        }
    }

    fn array(&mut self) -> RawJson {
        self.position += 1;
        let mut values = Vec::new();
        loop {
            self.whitespace();
            if self.bytes.get(self.position) == Some(&b']') {
                self.position += 1;
                return RawJson::Array(values);
            }
            values.push(self.value());
            self.whitespace();
            match self.bytes.get(self.position) {
                Some(b',') => self.position += 1,
                Some(b']') => {
                    self.position += 1;
                    return RawJson::Array(values);
                }
                _ => fail("runtime JSON array separator missing"),
            }
        }
    }
}

fn candidate_exact_integral(lexeme: &str) -> Option<i64> {
    let bytes = lexeme.as_bytes();
    if bytes.is_empty() {
        return None;
    }
    let digits = if bytes[0] == b'-' {
        &bytes[1..]
    } else {
        bytes
    };
    if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
        return None;
    }
    lexeme.parse::<i64>().ok()
}

fn candidate_raw_ids(bytes: &[u8]) -> Vec<i64> {
    let mut parser = RawParser::for_candidate(bytes);
    let root = parser.value();
    parser.whitespace();
    if parser.position != bytes.len() {
        fail("candidate JSON has trailing data");
    }
    let rows = match root {
        RawJson::Object(mut object) => match object.remove("fate_names") {
            Some(RawJson::Array(rows)) => rows,
            _ => fail("fate_names array missing"),
        },
        _ => fail("candidate JSON root must be an object"),
    };
    rows.into_iter()
        .map(|row| {
            let mut fields = match row {
                RawJson::Object(fields) => fields,
                _ => fail("fate event row must be an object"),
            };
            match fields.remove("fate_id") {
                Some(RawJson::Number(lexeme)) => candidate_exact_integral(&lexeme)
                    .unwrap_or_else(|| fail("fate_id must use canonical integer syntax")),
                _ => fail("fate_id number missing"),
            }
        })
        .collect()
}

fn runtime_raw_numbers(bytes: &[u8]) -> BTreeMap<String, String> {
    let mut parser = RawParser::new(bytes);
    let root = parser.value();
    parser.whitespace();
    if parser.position != bytes.len() {
        fail("runtime JSON has trailing data");
    }
    let entities = match root {
        RawJson::Object(mut object) => match object.remove("entities") {
            Some(RawJson::Object(entities)) => entities,
            _ => fail("runtime entities object missing"),
        },
        _ => fail("runtime JSON root must be an object"),
    };
    entities
        .into_iter()
        .map(|(key, entity)| {
            let fields = match entity {
                RawJson::Object(mut entity) => match entity.remove("fields") {
                    Some(RawJson::Object(fields)) => fields,
                    _ => fail(format!("runtime entity {key} fields object missing")),
                },
                _ => fail(format!("runtime entity {key} must be an object")),
            };
            let fate_id = match fields.get("fate_id") {
                Some(RawJson::Number(value)) => value.clone(),
                _ => fail(format!("runtime entity {key} fate_id number missing")),
            };
            (key, fate_id)
        })
        .collect()
}

fn deserialize_integral<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: Deserializer<'de>,
{
    let value = JsonNumber::deserialize(deserializer)?;
    exact_integral(&value).ok_or_else(|| de::Error::custom("expected an exact finite integer"))
}

fn candidate(bytes: &[u8]) -> Candidate {
    let mut parsed = parse(bytes);
    let raw_ids = candidate_raw_ids(bytes);
    let rows = parsed
        .get_mut("fate_names")
        .and_then(JsonValue::as_array_mut)
        .unwrap_or_else(|| fail("fate_names array missing"));
    if rows.len() != raw_ids.len() {
        fail("fate_names row count mismatch");
    }
    for (row, fate_id) in rows.iter_mut().zip(raw_ids) {
        let fields = row
            .as_object_mut()
            .unwrap_or_else(|| fail("fate event row must be an object"));
        fields.insert("fate_id".to_owned(), JsonValue::Number(fate_id.into()));
    }
    let candidate = serde_json::from_value(parsed)
        .unwrap_or_else(|error| fail(format!("fate-event schema rejected: {error}")));
    validate_candidate(&candidate);
    candidate
}

/* Python's frozen checker uses str.strip(), whose whitespace set includes
 * the four C0 information separators that Rust's char::is_whitespace omits.
 * Keep this source-local predicate shared by candidate and runtime text
 * admission so both paths reject the same blank display names. */
fn is_blank_text(value: &str) -> bool {
    value
        .chars()
        .all(|character| character.is_whitespace() || matches!(character, '\u{001c}'..='\u{001f}'))
}

fn validate_candidate(candidate: &Candidate) {
    if candidate.fate_names.len() != COUNT as usize {
        fail(format!("expected exactly {COUNT} fate event rows"));
    }
    let mut codes = BTreeSet::new();
    for event in &candidate.fate_names {
        if !(0..COUNT).contains(&event.fate_id) || !codes.insert(event.fate_id) {
            fail("fate_id must be unique and exactly 0..36");
        }
        if is_blank_text(&event.display_name) {
            fail("display_name must be non-empty");
        }
        if event.display_name.chars().count() > MAX_TEXT_LENGTH {
            fail(format!("display_name exceeds {MAX_TEXT_LENGTH} characters"));
        }
    }
    if codes != (0..COUNT).collect::<BTreeSet<_>>() {
        fail("fate_id set must be exactly 0..36");
    }
}

fn field_id(key: &str) -> FieldId {
    format!("field-fate-event-{key}").into()
}

fn entity_id(fate_id: i64) -> EntityId {
    format!("sid-fate-event-{fate_id:02}").into()
}

fn stored_fate_id(value: &Number) -> Option<i64> {
    let value = value.get();
    if !value.is_finite() || value.fract() != 0.0 || !(0.0..COUNT as f64).contains(&value) {
        return None;
    }
    Some(value as i64)
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
        ("fate_id", FieldType::Number, true),
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
    let mut rows = candidate.fate_names.clone();
    rows.sort_by_key(|event| event.fate_id);
    for event in rows {
        let id = entity_id(event.fate_id);
        let fields = BTreeMap::from([
            (
                field_id("fate_id"),
                Value::Number(number(event.fate_id, "fate_id")),
            ),
            (field_id("display_name"), Value::Text(event.display_name)),
        ]);
        entities.insert(
            id.clone(),
            Entity {
                id,
                key: format!("fate_event_{:02}", event.fate_id).into(),
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

fn runtime_number(lexeme: &str) -> i64 {
    let number = runtime_exact_integral(lexeme)
        .unwrap_or_else(|| fail("runtime fate_id must be an integer"));
    if !(0..COUNT).contains(&number) {
        fail("runtime fate_id outside 0..36");
    }
    number
}

fn runtime_text(value: &str) -> String {
    if is_blank_text(value) {
        fail("runtime display_name must be non-empty text");
    }
    if value.chars().count() > MAX_TEXT_LENGTH {
        fail(format!(
            "runtime display_name exceeds {MAX_TEXT_LENGTH} characters"
        ));
    }
    value.to_owned()
}

fn normalize(path: &Path, output: &Path) {
    let bytes = read(path);
    let parsed = parse(&bytes);
    let raw_numbers = runtime_raw_numbers(&bytes);
    let runtime: Runtime = serde_json::from_value(parsed)
        .unwrap_or_else(|error| fail(format!("runtime JSON rejected: {error}")));
    if runtime.format_version != RUNTIME_FORMAT_VERSION
        || runtime.document_id != RUNTIME_DOCUMENT_ID
        || runtime.title != RUNTIME_TITLE
    {
        fail("runtime metadata does not match M7 document contract");
    }
    let expected: BTreeSet<String> = (0..COUNT)
        .map(|code| format!("fate_event_{code:02}"))
        .collect();
    if runtime.entities.keys().cloned().collect::<BTreeSet<_>>() != expected {
        fail("runtime entities must be exactly fate_event_00 through fate_event_36");
    }
    let mut rows = Vec::new();
    for code in 0..COUNT {
        let key = format!("fate_event_{code:02}");
        let entity = &runtime.entities[&key];
        if entity.schema != RUNTIME_SCHEMA_KEY {
            fail(format!("runtime entity {key} schema mismatch"));
        }
        let raw_fate_id = raw_numbers
            .get(&key)
            .unwrap_or_else(|| fail(format!("runtime entity {key} fate_id number missing")));
        let actual_code = runtime_number(raw_fate_id);
        if actual_code != code {
            fail(format!(
                "runtime entity key/value mismatch: {key} has {actual_code}"
            ));
        }
        rows.push(json!({
            "fate_id": actual_code,
            "display_name": runtime_text(&entity.fields.display_name),
        }));
    }
    write_new(
        output,
        serde_json::to_vec_pretty(&json!({"fate_names": rows}))
            .unwrap_or_else(|error| fail(format!("projection encoding failed: {error}")))
            .as_slice(),
    );
}

fn identity_document(document: &Document, output: &Path) {
    if document.id.as_str() != RUNTIME_DOCUMENT_ID {
        fail("stored document identity mismatch");
    }
    let schema = document
        .schemas
        .values()
        .find(|schema| schema.key.as_str() == RUNTIME_SCHEMA_KEY)
        .unwrap_or_else(|| fail("fate_names schema missing from storage"));
    if schema.id.as_str() != SCHEMA_ID {
        fail("fate_names schema identity mismatch");
    }
    if schema.fields.len() != 2 {
        fail("fate_names schema has unexpected field count");
    }
    let mut field_ids = Map::new();
    for (key, expected_type) in [
        ("fate_id", FieldType::Number),
        ("display_name", FieldType::Text),
    ] {
        let field = schema
            .fields
            .values()
            .find(|field| field.key.as_str() == key)
            .unwrap_or_else(|| fail(format!("fate event field missing from storage: {key}")));
        if field.field_type != expected_type || !field.required {
            fail(format!(
                "fate event field has wrong stored type or required flag: {key}"
            ));
        }
        field_ids.insert(key.to_owned(), JsonValue::String(field.id.to_string()));
    }
    let mut rows = Vec::new();
    for code in 0..COUNT {
        let expected_key = format!("fate_event_{code:02}");
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
        let stored_code = match entity.fields.get(&field_id("fate_id")) {
            Some(Value::Number(value)) => stored_fate_id(value)
                .unwrap_or_else(|| fail(format!("{expected_key} has an invalid typed fate_id"))),
            _ => fail(format!("{expected_key} has no typed fate_id")),
        };
        if stored_code != code || entity.id != entity_id(code) {
            fail(format!(
                "stored fate event identity mismatch: {expected_key}"
            ));
        }
        rows.push(json!({"fate_id": code, "entity_id": entity.id.to_string()}));
    }
    if document.entities.len() != COUNT as usize {
        fail("stored fate event entity count mismatch");
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
        let target = entity_id(36);
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
                    if before_value != &Value::Text("違規入獄".into())
                        || after_value != &Value::Text("違規入獄（M7驗證）".into())
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
        fail("edited document did not contain the isolated M7 change");
    }
}

fn reorder(input: &Path, output: &Path) {
    let mut root = parse(&read(input));
    let rows = root
        .get_mut("fate_names")
        .and_then(JsonValue::as_array_mut)
        .unwrap_or_else(|| fail("fate_names missing"));
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
            if let Some(identity_output) = args.next() {
                identity_ro(Path::new(&output), Path::new(&identity_output));
            }
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
