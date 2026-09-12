use serde::{Deserialize, Deserializer, de};
use serde_json::{Map, Value as JsonValue, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
};
use tachiko_storage::{load_roproj, to_canonical_string};
use tachiko_workspace_engine::{
    Document, Entity, EntityId, FieldDefinition, FieldId, FieldType, Number, Schema, SchemaId,
    Value, validate,
};

const PREFIX: &str = "RICHMAN4_SETUP_ORACLE=";
const MAX: i64 = 9_007_199_254_740_991;
const KINDS: [&str; 3] = ["initial_fund", "day_limit", "wealth_multiplier"];

fn fail(s: impl Into<String>) -> ! {
    eprintln!("tachiko_setup_mirror: {}", s.into());
    std::process::exit(1)
}
fn read(p: &Path) -> Vec<u8> {
    fs::read(p).unwrap_or_else(|e| fail(format!("read {}: {e}", p.display())))
}
fn write_new(p: &Path, b: &[u8]) {
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(p)
        .unwrap_or_else(|e| fail(format!("create {}: {e}", p.display())));
    f.write_all(b)
        .and_then(|_| f.sync_all())
        .unwrap_or_else(|e| fail(format!("write {}: {e}", p.display())));
}

/* Reject lossy numeric spellings before serde_json can turn them into binary64. */
fn check_numbers(b: &[u8]) {
    let mut i = 0;
    let mut string = false;
    let mut esc = false;
    while i < b.len() {
        let c = b[i];
        if string {
            if esc {
                esc = false
            } else if c == b'\\' {
                esc = true
            } else if c == b'"' {
                string = false
            };
            i += 1;
            continue;
        }
        if c == b'"' {
            string = true;
            i += 1;
            continue;
        }
        if c == b'-' || c.is_ascii_digit() {
            let start = i;
            if c == b'-' {
                i += 1
            };
            if i >= b.len() {
                fail("invalid number")
            };
            if b[i] == b'0' {
                i += 1
            } else if b[i].is_ascii_digit() {
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1
                }
            } else {
                fail("invalid number")
            }
            let mut frac = false;
            let mut nonzero = false;
            if i < b.len() && b[i] == b'.' {
                frac = true;
                i += 1;
                let s = i;
                while i < b.len() && b[i].is_ascii_digit() {
                    if b[i] != b'0' {
                        nonzero = true
                    };
                    i += 1
                }
                if i == s {
                    fail("invalid number")
                }
            }
            if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
                i += 1;
                if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
                    i += 1;
                }
                let s = i;
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
                if i == s {
                    fail("invalid exponent")
                }
            }
            let token =
                std::str::from_utf8(&b[start..i]).unwrap_or_else(|_| fail("invalid number"));
            /* Exact decimal arithmetic below deliberately precedes any f64 conversion. */
            let n = token;
            if n.starts_with('-') {
                continue;
            }
            if frac && nonzero {
                fail("number is not an exact safe integer")
            }
            let unsigned = token.strip_prefix('-').unwrap_or(token);
            let (mantissa, exponent) = unsigned.split_once(['e', 'E']).unwrap_or((unsigned, "0"));
            if exponent.len() > 7 {
                fail("exponent is outside bounded safe range")
            }
            let exponent: i32 = exponent
                .parse()
                .unwrap_or_else(|_| fail("invalid exponent"));
            if exponent > 16 || exponent < -(mantissa.len() as i32 + 16) {
                fail("exponent is outside bounded safe range")
            }
            let mut digits = String::new();
            let mut decimals = 0i32;
            for (part_no, part) in mantissa.split('.').enumerate() {
                digits.push_str(part);
                if part_no == 1 {
                    decimals = part.len() as i32;
                }
            }
            let digits = digits.trim_start_matches('0');
            let shift = exponent - decimals;
            let (whole, fraction) = if shift >= 0 {
                (
                    format!("{}{}", digits, "0".repeat(shift as usize)),
                    String::new(),
                )
            } else if digits.len() as i32 > -shift {
                let at = (digits.len() as i32 + shift) as usize;
                (digits[..at].to_owned(), digits[at..].to_owned())
            } else {
                (
                    "0".to_owned(),
                    format!("{}{}", "0".repeat((-shift as usize) - digits.len()), digits),
                )
            };
            if fraction.chars().any(|x| x != '0') {
                fail("fractional number is not admitted")
            }
            let whole = whole.trim_start_matches('0');
            if whole.len() > 16 || (whole.len() == 16 && whole > "9007199254740991") {
                fail("number outside safe integer range")
            }
        } else {
            i += 1
        }
    }
}
struct Strict(JsonValue);
impl<'de> Deserialize<'de> for Strict {
    fn deserialize<D>(d: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct V;
        impl<'de> de::Visitor<'de> for V {
            type Value = JsonValue;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("JSON")
            }
            fn visit_unit<E: de::Error>(self) -> Result<JsonValue, E> {
                Ok(JsonValue::Null)
            }
            fn visit_bool<E: de::Error>(self, v: bool) -> Result<JsonValue, E> {
                Ok(JsonValue::Bool(v))
            }
            fn visit_i64<E: de::Error>(self, v: i64) -> Result<JsonValue, E> {
                Ok(json!(v))
            }
            fn visit_u64<E: de::Error>(self, v: u64) -> Result<JsonValue, E> {
                Ok(json!(v))
            }
            fn visit_f64<E: de::Error>(self, v: f64) -> Result<JsonValue, E> {
                serde_json::Number::from_f64(v)
                    .map(JsonValue::Number)
                    .ok_or_else(|| E::custom("non-finite JSON number"))
            }
            fn visit_str<E: de::Error>(self, v: &str) -> Result<JsonValue, E> {
                Ok(json!(v))
            }
            fn visit_string<E: de::Error>(self, v: String) -> Result<JsonValue, E> {
                Ok(json!(v))
            }
            fn visit_seq<A: de::SeqAccess<'de>>(self, mut a: A) -> Result<JsonValue, A::Error> {
                let mut v = Vec::new();
                while let Some(x) = a.next_element_seed(S)? {
                    v.push(x)
                }
                Ok(JsonValue::Array(v))
            }
            fn visit_map<A: de::MapAccess<'de>>(self, mut a: A) -> Result<JsonValue, A::Error> {
                let mut m = Map::new();
                while let Some(k) = a.next_key::<String>()? {
                    if m.contains_key(&k) {
                        return Err(de::Error::custom(format!("duplicate JSON key: {k}")));
                    }
                    m.insert(k, a.next_value_seed(S)?);
                }
                Ok(JsonValue::Object(m))
            }
        }
        struct S;
        impl<'de> de::DeserializeSeed<'de> for S {
            type Value = JsonValue;
            fn deserialize<D: Deserializer<'de>>(self, d: D) -> Result<JsonValue, D::Error> {
                d.deserialize_any(V)
            }
        }
        Ok(Self(d.deserialize_any(V)?))
    }
}
fn parse(b: &[u8]) -> JsonValue {
    if b.len() > 128 * 1024 {
        fail("JSON input exceeds 128 KiB")
    };
    check_numbers(b);
    serde_json::from_slice::<Strict>(b)
        .unwrap_or_else(|e| fail(format!("strict JSON parse failed: {e}")))
        .0
}
#[derive(Clone)]
struct Row {
    kind: String,
    index: i64,
    value: i64,
}
fn int(v: &JsonValue) -> i64 {
    if let Some(n) = v.as_i64() {
        if n >= 0 && n <= MAX {
            return n;
        }
    }
    if let Some(n) = v.as_f64() {
        if n.is_finite() && n.fract() == 0.0 && n >= 0.0 && n <= MAX as f64 {
            return n as i64;
        }
    }
    fail("value must be a safe nonnegative integer")
}
fn candidate(b: &[u8]) -> Vec<Row> {
    let root = parse(b);
    let obj = root
        .as_object()
        .unwrap_or_else(|| fail("candidate root must be object"));
    if obj.len() != 1 || !obj.contains_key("setup_options") {
        fail("candidate root must contain only setup_options")
    };
    let arr = obj["setup_options"]
        .as_array()
        .unwrap_or_else(|| fail("setup_options must be array"));
    if arr.len() != 18 {
        fail("expected exactly 18 setup options")
    };
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for x in arr {
        let o = x
            .as_object()
            .unwrap_or_else(|| fail("setup record must be object"));
        if o.len() != 3
            || !o.contains_key("kind")
            || !o.contains_key("legacy_index")
            || !o.contains_key("value")
        {
            fail("setup record has unknown or missing fields")
        };
        let kind = o["kind"]
            .as_str()
            .unwrap_or_else(|| fail("kind must be text"));
        if !KINDS.contains(&kind) {
            fail("unknown setup kind")
        };
        let index = int(&o["legacy_index"]);
        if index > 5 || !seen.insert((kind.to_owned(), index)) {
            fail("duplicate or out-of-range setup identity")
        };
        out.push(Row {
            kind: kind.to_owned(),
            index,
            value: int(&o["value"]),
        });
    }
    if seen.len() != 18 {
        fail("missing setup identity")
    };
    out.sort_by_key(|r| (KINDS.iter().position(|k| *k == r.kind).unwrap(), r.index));
    out
}
fn fid(k: &str) -> FieldId {
    format!("field-setup-{k}").into()
}
fn sid(r: &Row) -> EntityId {
    format!("sid-{}-{:02}", r.kind, r.index).into()
}
fn schema() -> Schema {
    let id: SchemaId = "schema-setup-options".into();
    let fields = [
        ("kind", FieldType::Text),
        ("legacy_index", FieldType::Number),
        ("value", FieldType::Number),
    ]
    .into_iter()
    .map(|(k, t)| {
        let id = fid(k);
        (
            id.clone(),
            FieldDefinition {
                id,
                key: k.into(),
                field_type: t,
                required: true,
            },
        )
    })
    .collect();
    Schema {
        id,
        key: "setup_options".into(),
        fields,
    }
}
fn document(rows: &[Row]) -> Document {
    let s = schema();
    let mut ss = BTreeMap::new();
    ss.insert(s.id.clone(), s);
    let mut es = BTreeMap::new();
    for r in rows {
        let id = sid(r);
        let mut f = BTreeMap::new();
        f.insert(fid("kind"), Value::Text(r.kind.clone()));
        f.insert(
            fid("legacy_index"),
            Value::Number(Number::new(r.index as f64).unwrap_or_else(|e| fail(e.to_string()))),
        );
        f.insert(
            fid("value"),
            Value::Number(Number::new(r.value as f64).unwrap_or_else(|e| fail(e.to_string()))),
        );
        es.insert(
            id.clone(),
            Entity {
                id,
                key: format!("setup_option_{}_{}", r.kind, r.index).into(),
                schema: "schema-setup-options".into(),
                fields: f,
            },
        );
    }
    Document {
        id: "richman4-tachiko-setup-mirror".into(),
        title: "Richman4 Tachiko setup mirror".into(),
        schemas: ss,
        entities: es,
    }
}
fn publish(rows: &[Row], p: &Path) {
    let d = document(rows);
    validate(&d).unwrap_or_else(|e| fail(format!("Rust validation rejected document: {e}")));
    write_new(
        p,
        to_canonical_string(&d)
            .unwrap_or_else(|e| fail(e.to_string()))
            .as_bytes(),
    )
}
fn import_log(p: &Path) -> Vec<Row> {
    let b = read(p);
    let mut found = None;
    for l in b
        .split(|x| *x == b'\n')
        .filter(|l| l.starts_with(PREFIX.as_bytes()))
    {
        if found.is_some() {
            fail("expected one witness marker")
        };
        found = Some(&l[PREFIX.len()..]);
    }
    candidate(found.unwrap_or_else(|| fail("witness marker missing")))
}
fn map_rows(rows: &[Row], doc: &str) -> JsonValue {
    json!({"document_id":doc,"schema_id":"schema-setup-options","field_ids":{"kind":fid("kind").to_string(),"legacy_index":fid("legacy_index").to_string(),"value":fid("value").to_string()},"rows":rows.iter().map(|r|json!({"kind":r.kind,"legacy_index":r.index,"entity_id":sid(r).to_string()})).collect::<Vec<_>>()})
}
fn identity_candidate(rows: &[Row], p: &Path) {
    write_new(
        p,
        serde_json::to_vec_pretty(&map_rows(rows, "richman4-tachiko-setup-mirror"))
            .unwrap()
            .as_slice(),
    )
}
fn identity_project(p: &Path, out: &Path) {
    let d = load_roproj(p).unwrap_or_else(|e| fail(format!("load .roproj failed: {e}")));
    let schema = d
        .schemas
        .values()
        .find(|s| s.key.as_str() == "setup_options")
        .unwrap_or_else(|| fail("setup_options schema missing from storage"));
    let mut field_ids = Map::new();
    for key in ["kind", "legacy_index", "value"] {
        let field = schema
            .fields
            .values()
            .find(|f| f.key.as_str() == key)
            .unwrap_or_else(|| fail(format!("setup field missing from storage: {key}")));
        let expected = if key == "kind" {
            FieldType::Text
        } else {
            FieldType::Number
        };
        if field.field_type != expected || !field.required {
            fail(format!("setup field has wrong stored type: {key}"));
        }
        field_ids.insert(key.to_owned(), JsonValue::String(field.id.to_string()));
    }
    let mut rows = Vec::new();
    for e in d.entities.values() {
        if !e.key.as_str().starts_with("setup_option_") {
            continue;
        }
        let k = match e.fields.get(&fid("kind")) {
            Some(Value::Text(x)) => x.to_string(),
            _ => fail("project kind is not typed text"),
        };
        let i = match e.fields.get(&fid("legacy_index")) {
            Some(Value::Number(n)) => n.get() as i64,
            _ => fail("project index is not typed number"),
        };
        rows.push(json!({"kind":k,"legacy_index":i,"entity_id":e.id.to_string()}));
    }
    rows.sort_by_key(|r| {
        (
            r["kind"]
                .as_str()
                .and_then(|x| KINDS.iter().position(|k| *k == x))
                .unwrap_or(99),
            r["legacy_index"].as_i64().unwrap_or(-1),
        )
    });
    write_new(
        out,
        serde_json::to_vec_pretty(
            &json!({"document_id":d.id,"schema_id":schema.id,"field_ids":field_ids,"rows":rows}),
        )
        .unwrap()
        .as_slice(),
    )
}
fn normalize(p: &Path, out: &Path) {
    let raw = read(p);
    if raw.len() > 128 * 1024 {
        fail("runtime JSON exceeds 128 KiB");
    }
    let root: JsonValue = serde_json::from_slice(&raw)
        .unwrap_or_else(|e| fail(format!("runtime JSON rejected: {e}")));
    let es = root["entities"]
        .as_object()
        .unwrap_or_else(|| fail("runtime entities missing"));
    let mut rows = Vec::new();
    for e in es.values() {
        let f = e["fields"]
            .as_object()
            .unwrap_or_else(|| fail("runtime fields missing"));
        let k = f["kind"]
            .as_str()
            .unwrap_or_else(|| fail("runtime kind missing"));
        let i = int(&f["legacy_index"]);
        let v = int(&f["value"]);
        rows.push(Row {
            kind: k.to_owned(),
            index: i,
            value: v,
        });
    }
    rows.sort_by_key(|r| {
        (
            KINDS.iter().position(|k| *k == r.kind).unwrap_or(99),
            r.index,
        )
    });
    if rows.len() != 18 {
        fail("runtime setup option count mismatch")
    };
    let a = rows
        .iter()
        .map(|r| json!({"kind":r.kind,"legacy_index":r.index,"value":r.value}))
        .collect::<Vec<_>>();
    write_new(
        out,
        serde_json::to_vec_pretty(&json!({"setup_options":a}))
            .unwrap()
            .as_slice(),
    )
}

fn check_diff(p: &Path) {
    let text =
        String::from_utf8(read(p)).unwrap_or_else(|e| fail(format!("diff is not UTF-8: {e}")));
    let lines = text
        .lines()
        .filter(|line| !line.trim().is_empty())
        .collect::<Vec<_>>();
    if lines != ["Setup Options Setup Option Day Limit 5", "value: 30 -> 31"] {
        fail("semantic diff must contain exactly day_limit/index 5 value 30 -> 31");
    }
}
fn reorder(p: &Path, out: &Path) {
    let mut root = parse(&read(p));
    let rows = root["setup_options"]
        .as_array_mut()
        .unwrap_or_else(|| fail("setup_options missing"));
    rows.reverse();
    write_new(out, serde_json::to_vec_pretty(&root).unwrap().as_slice());
}
fn main() {
    let mut a = env::args().skip(1);
    match a.next().as_deref() {
        Some("candidate") => {
            let input = a.next().unwrap_or_else(|| fail("input missing"));
            let output = a.next().unwrap_or_else(|| fail("output missing"));
            let r = candidate(&read(Path::new(&input)));
            publish(&r, Path::new(&output))
        }
        Some("import-log") => {
            let log = a.next().unwrap_or_else(|| fail("log missing"));
            let output = a.next().unwrap_or_else(|| fail("output missing"));
            let ids = a.next().unwrap_or_else(|| fail("identity missing"));
            let r = import_log(Path::new(&log));
            publish(&r, Path::new(&output));
            identity_candidate(&r, Path::new(&ids))
        }
        Some("normalize") => {
            let input = a.next().unwrap_or_else(|| fail("runtime missing"));
            let output = a.next().unwrap_or_else(|| fail("projection missing"));
            normalize(Path::new(&input), Path::new(&output))
        }
        Some("identity") => {
            let input = a.next().unwrap_or_else(|| fail("project missing"));
            let output = a.next().unwrap_or_else(|| fail("identity missing"));
            identity_project(Path::new(&input), Path::new(&output))
        }
        Some("check-diff") => {
            let input = a.next().unwrap_or_else(|| fail("diff missing"));
            check_diff(Path::new(&input));
        }
        Some("reorder") => {
            let input = a.next().unwrap_or_else(|| fail("candidate missing"));
            let output = a.next().unwrap_or_else(|| fail("candidate output missing"));
            reorder(Path::new(&input), Path::new(&output));
        }
        None => fail("usage: candidate|import-log|normalize|identity"),
        Some(x) => fail(format!("unknown command: {x}")),
    }
}
