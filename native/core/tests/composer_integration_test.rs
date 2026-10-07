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
fn local_paths(id: u64, state: &Value, text: &str) -> Vec<Value> {
    let query = json!({"schemaVersion":1,"sessionEpoch":1,"targetId":id.to_string(),"contextRevision":1,"editorRevision":1,"selectionRevision":1,"catalogRevision":"ianvs-20260929-v1","policyRevision":0,"text":text,"cursorUtf16":text.encode_utf16().count(),"dialect":"zsh"});
    let deadline = Instant::now() + Duration::from_secs(2);
    let job = loop {
        let start = request(
            id,
            "completion.local_start",
            json!({"query":query,"lease":state["lease"],"policy":{"files":true,"scripts":false}}),
        );
        if let Some(job) = start["payload"]["jobId"].as_str() {
            break job.to_owned();
        }
        assert_eq!(start["payload"]["status"], "busy", "{start}");
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(5));
    };
    loop {
        let response = request(id, "completion.local_poll", json!({"jobId":job}));
        if response["payload"]["status"] == "complete" {
            assert_eq!(response["payload"]["batch"]["query"], query);
            return response["payload"]["batch"]["items"]
                .as_array()
                .unwrap()
                .clone();
        }
        assert!(Instant::now() < deadline, "{response}");
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn composer_paths_use_shell_cwd_and_home_and_keep_expansion_when_accepted() {
    let fixture = tempfile::tempdir().unwrap();
    let home = fixture.path().join("shell-home");
    let cwd = home.join("pkg/application/handlers");
    let destination = home.join("My files/中文目录");
    std::fs::create_dir_all(&cwd).unwrap();
    std::fs::create_dir_all(&destination).unwrap();
    std::fs::write(home.join(".zshrc"), "PROMPT='paths> '\nRPROMPT=''\n").unwrap();
    let mut config = config();
    config["config"]["launch"] = json!({"program":"/bin/zsh","args":[],"cwd":cwd,"env":{"HOME":home,"ZDOTDIR":home,"LANG":"en_US.UTF-8"}});
    let session = Session(session::create_session_v1(&config.to_string()).unwrap());
    let ready = wait_ready(session.0, None);
    assert_eq!(ready["home"], home.to_str().unwrap());
    let relative = local_paths(session.0, &ready, "cd ../../../");
    assert!(
        relative
            .iter()
            .any(|i| i["newText"] == "'../../../My files/'")
    );
    let absolute = format!("cd '{}/My'", home.display());
    assert!(
        local_paths(session.0, &ready, &absolute)
            .iter()
            .any(|i| i["newText"] == format!("'{}/My files/'", home.display()))
    );
    let query = "cd ~/My";
    let completed = local_paths(session.0, &ready, query);
    assert_eq!(completed.len(), 1);
    assert_eq!(completed[0]["newText"], "~/'My files/'");
    let nested = local_paths(session.0, &ready, "cd ~/'My files/'");
    assert_eq!(nested.len(), 1);
    assert_eq!(nested[0]["newText"], "~/'My files/中文目录/'");
    let result = request(
        session.0,
        "composer.submit",
        json!({"lease":ready["lease"],"submissionId":"path-accept","text":format!("cd {}", nested[0]["newText"].as_str().unwrap())}),
    );
    assert_eq!(result["payload"]["outcome"], "pending");
    let after = wait_ready(session.0, ready["lease"].as_str());
    assert_eq!(
        std::path::Path::new(after["cwd"].as_str().unwrap())
            .canonicalize()
            .unwrap(),
        destination.canonicalize().unwrap()
    );
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
fn composer_long_literal_payload_commits_once_within_existing_deadline() {
    let home = tempfile::tempdir().unwrap();
    std::fs::write(home.path().join(".zshrc"), "PROMPT='long> '\nRPROMPT=''\n").unwrap();
    let mut config = config();
    config["config"]["launch"] = json!({"program":"/bin/zsh", "args":[],
        "cwd":home.path(), "env":{"HOME":home.path(), "ZDOTDIR":home.path(), "LANG":"en_US.UTF-8"}});
    let session = Session(session::create_session_v1(&config.to_string()).unwrap());
    let mut state = wait_ready(session.0, None);
    for length in [17_000, 65_536] {
        // UTF-8 straddles the decoder's chunk boundary; backslashes stay literal.
        // A quoted substitution must remain text, never adapter-side eval.
        let prefix = format!(": '{}中文😀\\n$(touch WRONG_ENDPOINT)", "x".repeat(507));
        let suffix = "'; printf x >> proof";
        let command = format!(
            "{prefix}{}{suffix}",
            "y".repeat(length - prefix.len() - suffix.len())
        );
        assert_eq!(command.len(), length);
        let id = format!("long-{length}");
        let payload = json!({"lease":state["lease"],"submissionId":id,"text":command});
        assert_eq!(
            request(session.0, "composer.submit", payload.clone())["payload"]["outcome"],
            "pending"
        );
        state = wait_ready(session.0, state["lease"].as_str());
        assert_eq!(state["outcome"], "accepted", "{state}");
        assert_eq!(
            request(session.0, "composer.submit", payload)["payload"]["outcome"],
            "accepted"
        );
        let receipt = request(session.0, "composer.receipt", json!({"submissionId":id}));
        assert_eq!(receipt["payload"]["outcome"], "accepted");
        assert_eq!(receipt["payload"]["exitCode"], 0);
        let block = request(
            session.0,
            "terminal.command_blocks",
            json!({"id":receipt["payload"]["blockId"]}),
        );
        assert_eq!(block["payload"]["block"]["command"], command);
    }
    assert_eq!(
        std::fs::read_to_string(home.path().join("proof")).unwrap(),
        "xx"
    );
    assert!(!home.path().join("WRONG_ENDPOINT").exists());
}

#[test]
#[cfg(target_os = "macos")]
fn composer_command_names_follow_live_shell_without_running_candidates() {
    use std::os::unix::fs::PermissionsExt;
    let home = tempfile::tempdir().unwrap();
    let bin = home.path().join("bin");
    std::fs::create_dir(&bin).unwrap();
    let tool = bin.join("fixture-tool");
    std::fs::write(&tool, "#!/bin/sh\ntouch MUST_NOT_RUN\n").unwrap();
    std::fs::set_permissions(&tool, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::write(home.path().join(".zshrc"),
        "PROMPT='test> '\nRPROMPT=''\nPATH=\"$HOME/bin:$PATH\"\nalias 帮助='echo ok'\ncustom_fn() { touch MUST_NOT_RUN; }\n").unwrap();
    let mut config = config();
    config["config"]["launch"] = json!({"program":"/bin/zsh", "args":[],
        "cwd": home.path(), "env": {"HOME":home.path(), "ZDOTDIR":home.path(), "LANG":"en_US.UTF-8"}});
    let session = Session(session::create_session_v1(&config.to_string()).unwrap());
    let mut state = wait_ready(session.0, None);
    for name in ["fixture-tool", "帮助", "custom_fn", "ls", "cd"] {
        assert!(
            state["commandNames"]
                .as_array()
                .unwrap()
                .contains(&json!(name)),
            "missing {name}"
        );
    }
    assert!(!home.path().join("MUST_NOT_RUN").exists());
    std::fs::rename(&tool, bin.join("new-tool")).unwrap();
    let response = request(
        session.0,
        "composer.submit",
        json!({"lease": state["lease"],
        "submissionId":"inventory-change", "text":"unalias 帮助; unset -f custom_fn"}),
    );
    assert_eq!(response["payload"]["outcome"], "pending");
    state = wait_ready(session.0, state["lease"].as_str());
    for name in ["fixture-tool", "帮助", "custom_fn"] {
        assert!(
            !state["commandNames"]
                .as_array()
                .unwrap()
                .contains(&json!(name)),
            "stale {name}"
        );
    }
    assert!(
        state["commandNames"]
            .as_array()
            .unwrap()
            .contains(&json!("new-tool"))
    );
    assert!(!home.path().join("MUST_NOT_RUN").exists());
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
    for (submission, command) in [
        ("integration-1", "export COMPOSER_TEST=retained; cd /tmp"),
        ("integration-2", "print COMPOSER_VALUE:$COMPOSER_TEST"),
    ] {
        let receipt = request(
            session.0,
            "composer.receipt",
            json!({"submissionId":submission}),
        );
        let payload = &receipt["payload"];
        assert_eq!(payload["outcome"], "accepted", "{receipt}");
        let block_id = payload["blockId"]
            .as_str()
            .expect("canonical block reference");
        let output = request(session.0, "terminal.command_blocks", json!({"id":block_id}));
        assert_eq!(output["payload"]["block"]["submissionId"], submission);
        assert_eq!(output["payload"]["block"]["command"], command);
        assert_eq!(payload["exitCode"], 0);
        assert_eq!(
            request(
                session.0,
                "composer.receipt",
                json!({"submissionId":submission})
            )["payload"],
            *payload
        );
    }
    assert_eq!(
        request(
            session.0,
            "composer.receipt",
            json!({"submissionId":"never-submitted"})
        )["payload"]["outcome"],
        "unknown"
    );
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
    let blocks = request(session.0, "terminal.command_blocks", json!({}));
    assert!(
        blocks["payload"]["blocks"]
            .as_array()
            .unwrap()
            .last()
            .unwrap()["submissionId"]
            .is_null()
    );
}
