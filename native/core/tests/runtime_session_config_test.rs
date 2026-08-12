use ianvs_core::session;
use ianvs_core::session_config::SessionConfigV1;
use serde_json::{Map, Value};
use std::ffi::CString;

const SHAPE_CORPUS: &str =
    include_str!("fixtures/session_config/session_config_v1_shape_corpus.json");

fn corpus() -> Value {
    serde_json::from_str(SHAPE_CORPUS).expect("SessionConfig shape corpus")
}

fn object_at_mut<'a>(root: &'a mut Value, pointer: &str) -> &'a mut Map<String, Value> {
    let mut value = root;
    for segment in pointer
        .split('/')
        .skip(1)
        .filter(|segment| !segment.is_empty())
    {
        value = match value {
            Value::Object(object) => object.get_mut(segment).expect("object path segment"),
            Value::Array(values) => &mut values[segment.parse::<usize>().expect("array index")],
            _ => panic!("invalid corpus pointer {pointer}"),
        };
    }
    value.as_object_mut().expect("closed object path")
}

fn value_at<'a>(root: &'a Value, pointer: &str) -> &'a Value {
    pointer
        .split('/')
        .skip(1)
        .filter(|segment| !segment.is_empty())
        .fold(root, |value, segment| match value {
            Value::Object(object) => object.get(segment).expect("object path segment"),
            Value::Array(values) => &values[segment.parse::<usize>().expect("array index")],
            _ => panic!("invalid corpus pointer {pointer}"),
        })
}

fn replace_at(root: &mut Value, pointer: &str, replacement: Value) {
    let mut segments = pointer
        .split('/')
        .skip(1)
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();
    let last = segments.pop().expect("non-root mutation path");
    let mut parent = root;
    for segment in segments {
        parent = match parent {
            Value::Object(object) => object.get_mut(segment).expect("object path segment"),
            Value::Array(values) => &mut values[segment.parse::<usize>().expect("array index")],
            _ => panic!("invalid corpus pointer {pointer}"),
        };
    }
    match parent {
        Value::Object(object) => {
            object.insert(last.to_string(), replacement);
        }
        Value::Array(values) => {
            values[last.parse::<usize>().expect("array index")] = replacement;
        }
        _ => panic!("invalid corpus pointer {pointer}"),
    }
}

fn materialize_mutation(specification: &Value, current: Option<&Value>) -> Value {
    let Some(object) = specification.as_object() else {
        return match specification {
            Value::Array(values) => Value::Array(
                values
                    .iter()
                    .map(|value| materialize_mutation(value, None))
                    .collect(),
            ),
            _ => specification.clone(),
        };
    };
    let Some(operation) = object.get("op").and_then(Value::as_str) else {
        return Value::Object(
            object
                .iter()
                .map(|(key, value)| (key.clone(), materialize_mutation(value, None)))
                .collect(),
        );
    };
    let count = object["count"].as_u64().expect("mutation count") as usize;
    match operation {
        "repeat_string" => Value::String(
            object["value"]
                .as_str()
                .expect("repeat string value")
                .repeat(count),
        ),
        "repeat_array" => Value::Array(
            (0..count)
                .map(|_| materialize_mutation(&object["value"], None))
                .collect(),
        ),
        "repeat_current_array_item" => {
            let first = current
                .and_then(Value::as_array)
                .and_then(|values| values.first())
                .expect("current array item");
            Value::Array((0..count).map(|_| first.clone()).collect())
        }
        "oversized_string_map" => Value::Object(
            (0..count)
                .map(|index| (format!("KEY_{index}"), Value::String("value".into())))
                .collect(),
        ),
        _ => panic!("unknown corpus mutation operation {operation}"),
    }
}

fn case_alias(key: &str) -> String {
    let mut chars = key.chars();
    let first = chars.next().expect("non-empty JSON key");
    let alias = if first.is_ascii_uppercase() {
        first.to_ascii_lowercase()
    } else {
        first.to_ascii_uppercase()
    };
    format!("{alias}{}", chars.as_str())
}

fn assert_ffi_rejects(value: &Value, reason: &str) {
    let raw = CString::new(value.to_string()).expect("CString config");
    assert_eq!(
        unsafe { ianvs_core::ffi::ianvs_session_create_v1(raw.as_ptr()) },
        0,
        "live FFI accepted {reason}"
    );
    assert_eq!(
        unsafe { ianvs_core::ffi::ianvs_replay_session_create_v1(raw.as_ptr()) },
        0,
        "replay FFI accepted {reason}"
    );
}

#[test]
fn session_config_v1_crosses_live_and_replay_ffi() {
    let corpus = corpus();
    let config = corpus["valid_local"].clone();
    let decoded = SessionConfigV1::decode_json(&config.to_string()).unwrap();
    assert_eq!(decoded.session_id, "shape-local");
    assert_eq!(decoded.config.launch.program, "/bin/sh");

    let raw = CString::new(config.to_string()).unwrap();
    let live_id = unsafe { ianvs_core::ffi::ianvs_session_create_v1(raw.as_ptr()) };
    assert_ne!(live_id, 0);
    session::close_session(live_id).unwrap();

    let replay_id = unsafe { ianvs_core::ffi::ianvs_replay_session_create_v1(raw.as_ptr()) };
    assert_ne!(replay_id, 0);
    session::close_session(replay_id).unwrap();
}

#[test]
fn live_and_replay_ffi_enforce_the_shared_exact_shape_corpus() {
    let corpus = corpus();
    let valid_ssh = corpus["valid_ssh"].clone();
    let paths = corpus["closed_object_paths"]
        .as_array()
        .expect("closed paths");

    for path in paths {
        let path = path.as_str().expect("string path");
        let keys = {
            let mut source = valid_ssh.clone();
            object_at_mut(&mut source, path)
                .keys()
                .cloned()
                .collect::<Vec<_>>()
        };
        for key in keys {
            let mut missing = valid_ssh.clone();
            object_at_mut(&mut missing, path).remove(&key);
            assert_ffi_rejects(&missing, &format!("missing {path}/{key}"));

            let mut case_variant = valid_ssh.clone();
            let object = object_at_mut(&mut case_variant, path);
            let value = object.remove(&key).expect("existing key");
            object.insert(case_alias(&key), value);
            assert_ffi_rejects(&case_variant, &format!("case alias {path}/{key}"));
        }

        let mut unknown = valid_ssh.clone();
        object_at_mut(&mut unknown, path).insert("future_field".into(), Value::Bool(true));
        assert_ffi_rejects(&unknown, &format!("unknown field at {path}"));
    }

    for mutation in ["missing", "case", "unknown"] {
        let mut local = corpus["valid_local"].clone();
        let connection = object_at_mut(&mut local, "/config/connection");
        match mutation {
            "missing" => {
                connection.remove("type");
            }
            "case" => {
                let value = connection.remove("type").expect("type");
                connection.insert("Type".into(), value);
            }
            "unknown" => {
                connection.insert("future_field".into(), Value::Bool(true));
            }
            _ => unreachable!(),
        }
        assert_ffi_rejects(&local, &format!("local connection {mutation}"));
    }
}

#[test]
fn live_and_replay_ffi_reject_every_shared_invalid_value() {
    let corpus = corpus();
    let groups = corpus["value_mutation_groups"]
        .as_array()
        .expect("value mutation groups");
    for group in groups {
        let id = group["id"].as_str().expect("group id");
        let base = group["base"].as_str().expect("group base");
        for path in group["paths"].as_array().expect("mutation paths") {
            let path = path.as_str().expect("mutation path");
            for (index, specification) in group["invalid_values"]
                .as_array()
                .expect("invalid values")
                .iter()
                .enumerate()
            {
                let mut invalid = corpus[base].clone();
                let current = value_at(&invalid, path).clone();
                let replacement = materialize_mutation(specification, Some(&current));
                replace_at(&mut invalid, path, replacement);
                assert_ffi_rejects(&invalid, &format!("{id} {path} mutation {index}"));
            }
        }
    }
}
