#![cfg(target_os = "macos")]
use ianvs_core::{session, session_request};
use serde_json::{Value, json};
use std::time::{Duration, Instant};

struct Session(u64);
impl Drop for Session {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}
fn request(id: u64, operation: &str, payload: Value) -> Value {
    let raw = session_request::request_session_v1_json(id, &json!({
        "schema_version": 1, "contract": "ianvs-session-request-v1", "request_id": "composer-test",
        "session_id": id.to_string(), "operation": operation, "payload": payload
    }).to_string()).unwrap();
    serde_json::from_str(&raw).unwrap()
}
fn config() -> Value {
    let corpus: Value = serde_json::from_str(include_str!(
        "fixtures/session_config/session_config_v1_shape_corpus.json"
    ))
    .unwrap();
    corpus["valid_local"].clone()
}
fn wait_ready(id: u64, previous: Option<&str>) -> Value {
    let deadline = Instant::now() + Duration::from_secs(6);
    loop {
        let response = request(id, "composer.state", json!({}));
        assert_eq!(response["ok"], true, "{response}");
        let state = response["payload"].clone();
        if state["state"] == "ready" && state["lease"].as_str() != previous {
            return state;
        }
        assert!(Instant::now() < deadline, "no ready shell: {state}");
        std::thread::sleep(Duration::from_millis(20));
    }
}
#[test]
fn composer_current_request_contract_static_and_replay_denial() {
    let session = Session(session::create_replay_session_v1(&config().to_string()).unwrap());
    let query = json!({"schemaVersion": 1, "sessionEpoch": 1, "targetId": session.0.to_string(),
        "contextRevision": 0, "editorRevision": 1, "selectionRevision": 1, "catalogRevision": "ianvs-20260929-v1",
        "policyRevision": 0, "text": "git che --help", "cursorUtf16": 7, "dialect": "zsh"});
    let response = request(session.0, "completion.query", query.clone());
    assert_eq!(response["ok"], true, "{response}");
    assert!(
        response["payload"]["items"]
            .as_array()
            .unwrap()
            .iter()
            .any(|i| i["label"] == "checkout")
    );
    let mut unknown = query;
    unknown["future"] = true.into();
    assert_eq!(request(session.0, "completion.query", unknown)["ok"], false);
    assert_eq!(
        request(
            session.0,
            "composer.submit",
            json!({"lease":"fake","submissionId":"1","text":"echo bad"})
        )["payload"]["outcome"],
        "rejected"
    );
}
#[test]
#[cfg(target_os = "macos")]
fn composer_real_session_commits_once_in_current_zsh() {
    assert!(
        std::path::Path::new("/bin/zsh").exists(),
        "zsh required for Composer gate"
    );
    let home = tempfile::tempdir().unwrap();
    std::fs::write(home.path().join("hello world.txt"), "fixture").unwrap();
    std::fs::write(
        home.path().join(".zshrc"),
        "PROMPT='test> '\nRPROMPT=''\nHISTSIZE=100\nalias gc='git checkout'\n",
    )
    .unwrap();
    let mut config = config();
    config["config"]["launch"] = json!({"program":"/bin/zsh", "args":[],
        "cwd": home.path(), "env": {"HOME":home.path(), "ZDOTDIR":home.path(), "LANG":"en_US.UTF-8"}});
    let session = Session(session::create_session_v1(&config.to_string()).unwrap());
    let initial = wait_ready(session.0, None);
    let lease = initial["lease"].as_str().unwrap();
    let alias_query = json!({"schemaVersion":1,"sessionEpoch":1,"targetId":session.0.to_string(),"contextRevision":1,"editorRevision":1,"selectionRevision":1,"catalogRevision":"ianvs-20260929-v1","policyRevision":0,"text":"g","cursorUtf16":1,"dialect":"zsh"});
    let aliases = request(session.0, "completion.query", alias_query);
    let alias = aliases["payload"]["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["label"] == "gc")
        .expect("live shell alias");
    assert_eq!(alias["kind"], "alias");
    assert_eq!(alias["detail"], "git checkout");
    assert_eq!(alias["newText"], "gc");
    let local_query = json!({"schemaVersion":1,"sessionEpoch":1,"targetId":session.0.to_string(),"contextRevision":1,"editorRevision":1,"selectionRevision":1,"catalogRevision":"ianvs-20260929-v1","policyRevision":1,"text":"cat he","cursorUtf16":6,"dialect":"zsh"});
    let start = request(
        session.0,
        "completion.local_start",
        json!({"query":local_query,"lease":lease,"policy":{"files":true,"scripts":false}}),
    );
    let job = start["payload"]["jobId"].as_str().expect("local job");
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        let response = request(session.0, "completion.local_poll", json!({"jobId":job}));
        if response["payload"]["status"] == "complete" {
            assert_eq!(
                response["payload"]["batch"]["items"][0]["newText"],
                "'hello world.txt'"
            );
            assert_eq!(response["payload"]["batch"]["query"], local_query);
            break;
        }
        assert!(Instant::now() < deadline, "{response}");
        std::thread::sleep(Duration::from_millis(10));
    }
    let submit = json!({"lease":lease,"submissionId":"integration-1", "text":"export COMPOSER_TEST=retained; cd /tmp"});
    assert_eq!(
        request(session.0, "composer.submit", submit.clone())["payload"]["outcome"],
        "pending"
    );
    let after = wait_ready(session.0, Some(lease));
    assert_eq!(after["outcome"], "accepted");
    assert_eq!(
        after["history"][0],
        "export COMPOSER_TEST=retained; cd /tmp"
    );
    assert!(after["historyRevision"].as_u64().unwrap() > 0);
    assert!(matches!(
        after["cwd"].as_str(),
        Some("/tmp" | "/private/tmp")
    ));
    assert_eq!(
        request(session.0, "composer.submit", submit)["payload"]["outcome"],
        "accepted"
    );
    let lease = after["lease"].as_str().unwrap();
    let submit = json!({"lease":lease,"submissionId":"integration-2", "text":"print COMPOSER_VALUE:$COMPOSER_TEST"});
    assert_eq!(
        request(session.0, "composer.submit", submit)["payload"]["outcome"],
        "pending"
    );
    let second = wait_ready(session.0, Some(lease));
    assert_eq!(second["history"][0], "print COMPOSER_VALUE:$COMPOSER_TEST");
    let history: Value = serde_json::from_str(
        &session::search_session(session.0, "COMPOSER_VALUE:retained").unwrap(),
    )
    .unwrap();
    assert!(!history.as_array().unwrap().is_empty(), "{history}");
    session::write_session(session.0, b"echo raw").unwrap();
    assert_ne!(
        request(session.0, "composer.state", json!({}))["payload"]["state"],
        "ready"
    );
    session::write_session(session.0, " 中文 😀\r".as_bytes()).unwrap();
    let raw = wait_ready(session.0, second["lease"].as_str());
    assert_eq!(raw["history"][0], "echo raw 中文 😀");
}
