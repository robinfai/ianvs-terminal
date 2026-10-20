//! Run with tools/ssh_boundary_lab/composer.py against an isolated loopback sshd.
#![cfg(unix)]
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
    let raw = session_request::request_session_v1_json(
        id,
        &json!({
            "schema_version":1,"contract":"ianvs-session-request-v1","request_id":"remote-test",
            "session_id":id.to_string(),"operation":operation,"payload":payload
        })
        .to_string(),
    )
    .unwrap();
    let response: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(response["ok"], true, "{response}");
    response["payload"].clone()
}
fn ready(id: u64, previous: Option<&str>) -> Value {
    let deadline = Instant::now() + Duration::from_secs(12);
    loop {
        let state = request(id, "composer.state", json!({}));
        if state["state"] == "ready" && state["lease"].as_str() != previous {
            return state;
        }
        assert!(Instant::now() < deadline, "SSH prompt not ready: {state}");
        std::thread::sleep(Duration::from_millis(20));
    }
}
fn submit(id: u64, state: &Value, name: &str, command: &str) -> Value {
    let payload = json!({"lease":state["lease"],"submissionId":name,"text":command});
    assert_eq!(
        request(id, "composer.submit", payload.clone())["outcome"],
        "pending"
    );
    let next = ready(id, state["lease"].as_str());
    assert_eq!(next["outcome"], "accepted", "{next}");
    assert_eq!(
        request(id, "composer.submit", payload)["outcome"],
        "accepted"
    );
    next
}

fn completed_block(id: u64, previous: Option<&str>, command: &str, output: &str) -> String {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let snapshot = request(id, "terminal.command_blocks", json!({}));
        if let Some(block) = snapshot["blocks"]
            .as_array()
            .unwrap()
            .iter()
            .rev()
            .find(|b| {
                b["command"] == command && b["id"].as_str() != previous && b["running"] == false
            })
        {
            assert_eq!(block["exitCode"], 0, "{block}");
            let submission = block["submissionId"]
                .as_str()
                .expect("shell command provenance");
            let receipt = request(id, "composer.receipt", json!({"submissionId":submission}));
            assert_eq!(receipt["outcome"], "accepted");
            assert_eq!(receipt["blockId"], block["id"]);
            let text = block["lines"]
                .as_array()
                .unwrap()
                .iter()
                .filter_map(|line| line["text"].as_str())
                .collect::<Vec<_>>()
                .join("\n");
            assert!(text.contains(output), "missing output: {block}");
            assert!(
                !text.contains("fixture>"),
                "prompt leaked into output: {block}"
            );
            return block["id"].as_str().unwrap().into();
        }
        assert!(
            Instant::now() < deadline,
            "missing completed block: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
}
fn config(fixture: &Value) -> Value {
    let corpus: Value = serde_json::from_str(include_str!(
        "fixtures/session_config/session_config_v1_shape_corpus.json"
    ))
    .unwrap();
    let mut config = corpus["valid_local"].clone();
    let mut connection = corpus["valid_ssh"]["config"]["connection"].clone();
    for (key, value) in fixture["connection"].as_object().unwrap() {
        connection[key] = value.clone();
    }
    connection["proxyJump"] = Value::Null;
    connection["proxyJumpProfiles"] = json!([]);
    connection["portForwards"] = json!([]);
    config["config"]["connection"] = connection;
    if fixture["local"] == true {
        config["config"]["connection"] = json!({"type":"local"});
        config["config"]["launch"] = json!({"program":"/bin/zsh","args":[],"cwd":fixture["home"],"env":{"HOME":fixture["home"],"ZDOTDIR":fixture["home"],"LANG":"en_US.UTF-8"}});
    }
    config["config"]["shellIntegration"] =
        json!({"enabled":true,"sshAutoInject":true,"sshWrapper":true});
    config
}

#[test]
#[ignore = "requires the isolated loopback SSH fixture"]
fn remote_composer_ssh_negotiation_and_multihop() {
    let fixture: Value = serde_json::from_slice(
        &std::fs::read(std::env::var("IANVS_COMPOSER_SSH_FIXTURE").unwrap()).unwrap(),
    )
    .unwrap();
    let config = config(&fixture);
    let session = Session(session::create_session_v1(&config.to_string()).unwrap());
    let mut initial = ready(session.0, None);
    assert_eq!(
        initial["transport"],
        if fixture["local"] == true {
            "local"
        } else {
            "shell"
        }
    );
    assert_eq!(
        initial["dialect"],
        if fixture["local"] == true {
            json!("zsh")
        } else {
            fixture["shell"].clone()
        }
    );
    // Command acceptance and bytes in the raw screen are insufficient: each
    // execution needs its own completed output zone, including duplicate input.
    let mut previous_block = None;
    initial = submit(
        session.0,
        &initial,
        "intent-alias",
        "alias intentcheck='printf alias-ok'; intentfunction() { printf fn-ok; }",
    );
    assert!(initial["aliases"]["intentcheck"].is_string(), "{initial}");
    for name in ["ls", "cd", "intentcheck", "intentfunction"] {
        assert!(
            initial["commandNames"]
                .as_array()
                .unwrap()
                .contains(&json!(name)),
            "missing {name}"
        );
    }
    initial = submit(
        session.0,
        &initial,
        "remove-intent",
        "unalias intentcheck; unset -f intentfunction",
    );
    for name in ["intentcheck", "intentfunction"] {
        assert!(
            !initial["commandNames"]
                .as_array()
                .unwrap()
                .contains(&json!(name)),
            "stale {name}"
        );
    }
    for index in 0..2 {
        initial = submit(session.0, &initial, &format!("list-{index}"), "ls");
        previous_block = Some(completed_block(
            session.0,
            previous_block.as_deref(),
            "ls",
            "block-fixture.txt",
        ));
    }
    let parent_command =
        "export COMPOSER_SSH_VALUE=parent; cd /tmp\nprintf '%s\\n' 'SSH_UNICODE_中文_😀'";
    let parent = submit(session.0, &initial, "parent", parent_command);
    completed_block(session.0, None, parent_command, "SSH_UNICODE_中文_😀");
    assert!(
        !serde_json::from_str::<Value>(
            &session::search_session(session.0, "SSH_UNICODE_中文_😀").unwrap()
        )
        .unwrap()
        .as_array()
        .unwrap()
        .is_empty()
    );
    // Remote paths must never be sent to the local filesystem provider.
    let query = json!({"schemaVersion":1,"sessionEpoch":1,"targetId":session.0.to_string(),"contextRevision":1,"editorRevision":1,"selectionRevision":1,"catalogRevision":"ianvs-20260929-v1","policyRevision":0,"text":"cat /","cursorUtf16":5,"dialect":fixture["shell"]});
    if fixture["local"] != true {
        assert_eq!(
            request(
                session.0,
                "completion.local_start",
                json!({"query":query,"lease":parent["lease"],"policy":{"files":true,"scripts":false}})
            )["status"],
            "denied"
        );
    }
    let child = submit(session.0, &parent, "hop-one", "ssh composer-hop");
    assert_ne!(child["contextId"], parent["contextId"]);
    assert_eq!(
        request(
            session.0,
            "composer.submit",
            json!({"lease":parent["lease"],"submissionId":"stale-parent","text":"touch WRONG_ENDPOINT"})
        )["outcome"],
        "rejected"
    );
    let child_command = "printf 'SSH_CHILD:%s\\n' \"${COMPOSER_SSH_VALUE:-empty}\"; export COMPOSER_SSH_VALUE=child";
    let child = submit(session.0, &child, "child-value", child_command);
    completed_block(session.0, None, child_command, "SSH_CHILD:empty");
    assert!(
        !serde_json::from_str::<Value>(
            &session::search_session(session.0, "SSH_CHILD:empty").unwrap()
        )
        .unwrap()
        .as_array()
        .unwrap()
        .is_empty()
    );
    let grandchild = submit(session.0, &child, "hop-two", "ssh composer-hop");
    assert_ne!(grandchild["contextId"], child["contextId"]);
    let returned_child = submit(session.0, &grandchild, "leave-two", "exit");
    assert_eq!(returned_child["contextId"], child["contextId"]);
    assert_ne!(returned_child["lease"], child["lease"]);
    assert_eq!(
        request(
            session.0,
            "composer.submit",
            json!({"lease":grandchild["lease"],"submissionId":"retired","text":"touch WRONG_ENDPOINT"})
        )["outcome"],
        "rejected"
    );
    let returned_parent = submit(session.0, &returned_child, "leave-one", "exit");
    if returned_parent["contextId"] != parent["contextId"] {
        eprintln!(
            "{}",
            session::export_scrollback_session(session.0, Some(40)).unwrap()
        );
    }
    assert_eq!(returned_parent["contextId"], parent["contextId"]);
    let parent = submit(
        session.0,
        &returned_parent,
        "parent-value",
        "printf 'SSH_PARENT:%s\\n' \"$COMPOSER_SSH_VALUE\"",
    );
    assert!(
        !serde_json::from_str::<Value>(
            &session::search_session(session.0, "SSH_PARENT:parent").unwrap()
        )
        .unwrap()
        .as_array()
        .unwrap()
        .is_empty()
    );
    session::write_session(session.0, b"printf RAW_DRAFT").unwrap();
    let raw_deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if session::take_frame_diff(session.0)
            .unwrap()
            .is_some_and(|frame| frame.contains("RAW_DRAFT"))
        {
            break;
        }
        assert!(
            Instant::now() < raw_deadline,
            "raw draft did not reach the editing buffer"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
    assert_eq!(
        request(
            session.0,
            "composer.submit",
            json!({"lease":parent["lease"],"submissionId":"raw-race","text":"touch WRONG_ENDPOINT"})
        )["outcome"],
        "rejected"
    );
    session::write_session(session.0, b"\x03").unwrap();
    let recovered = ready(session.0, parent["lease"].as_str());
    // The wire carries no literal Enter; incomplete shell syntax stays in PS2.
    let receipt = request(
        session.0,
        "composer.submit",
        json!({"lease":recovered["lease"],"submissionId":"continuation","text":"echo 'unfinished"}),
    );
    assert_eq!(receipt["outcome"], "pending");
    let deadline = Instant::now() + Duration::from_secs(6);
    loop {
        let state = request(session.0, "composer.state", json!({}));
        if state["outcome"] == "accepted" {
            assert!(state["lease"].is_null());
            break;
        }
        assert!(Instant::now() < deadline, "{state}");
        std::thread::sleep(Duration::from_millis(20));
    }
    session::write_session(session.0, b"\x03").unwrap();
    let cancelled = ready(session.0, recovered["lease"].as_str());
    // Cancelling an accepted but incomplete line must not attach the following
    // raw command to that submission or replace its title with the stale input.
    session::write_session(session.0, b"printf 'AFTER_CANCEL\\n'\r").unwrap();
    let mut state = ready(session.0, cancelled["lease"].as_str());
    let blocks = request(session.0, "terminal.command_blocks", json!({}));
    let raw_block = blocks["blocks"].as_array().unwrap().last().unwrap();
    assert_eq!(raw_block["command"], "printf 'AFTER_CANCEL\\n'");
    assert!(raw_block["submissionId"].is_null(), "{raw_block}");
    assert!(
        request(
            session.0,
            "composer.receipt",
            json!({"submissionId":"continuation"})
        )["blockId"]
            .is_null()
    );
    // Repeated pipelines/conditionals keep the exact reviewed input and distinct
    // canonical blocks, even though DEBUG initially sees only the first printf.
    let command = "  printf '%s\\n' 'QUOTE_\"中文😀' | cat && printf '\\tCOMPOUND_END\\n'\n";
    let mut previous = None;
    for index in 0..2 {
        state = submit(session.0, &state, &format!("compound-{index}"), command);
        previous = Some(completed_block(
            session.0,
            previous.as_deref(),
            command,
            "COMPOUND_END",
        ));
    }
    // Exercise both fragmented host hooks and the former 16 KiB title limit
    // through real Readline/ZLE, not only an in-memory terminal parser.
    let long_command = format!(": '{}'; printf 'LONG_COMMAND_END\\n'", "x".repeat(17_000));
    submit(session.0, &state, "long-command", &long_command);
    completed_block(session.0, None, &long_command, "LONG_COMMAND_END");
    if fixture["local"] != true {
        // Real OpenSSH can send EOF before exit-status. Preserve a nonzero
        // remote result instead of manufacturing success or transport failure.
        session::write_session(session.0, b"exit 7\r").unwrap();
        let deadline = Instant::now() + Duration::from_secs(8);
        loop {
            let events: Value =
                serde_json::from_str(&session::poll_events(session.0).unwrap()).unwrap();
            if let Some(exit) = events
                .as_array()
                .unwrap()
                .iter()
                .find(|e| e["kind"] == "exit")
            {
                assert_eq!(exit["payload"]["code"], 7, "{exit}");
                break;
            }
            assert!(Instant::now() < deadline, "SSH shell exit was not reported");
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}
