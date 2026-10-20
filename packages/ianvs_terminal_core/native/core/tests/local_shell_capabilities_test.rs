#![cfg(target_os = "macos")]
use ianvs_core::{model::TerminalEvent, session, session_request};
use par_term_emu_core_rust::terminal::Terminal;
use serde_json::{Value, json};
use std::time::{Duration, Instant};

struct Session(u64);
impl Drop for Session {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}
fn collect(id: u64, predicate: impl Fn(&[Value]) -> bool) -> Vec<Value> {
    let deadline = Instant::now() + Duration::from_secs(12);
    let mut events = Vec::new();
    loop {
        events.extend(
            session::take_events(id)
                .unwrap()
                .into_iter()
                .map(|e: TerminalEvent| json!({"kind":e.kind,"payload":e.payload})),
        );
        if predicate(&events) {
            return events;
        }
        assert!(
            Instant::now() < deadline,
            "missing runtime evidence: {events:?}"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
}
fn blocks(id: u64) -> Value {
    let result = session_request::request_session_v1_json(
        id,
        &json!({
            "schema_version":1,"contract":"ianvs-session-request-v1","request_id":"caps",
            "session_id":id.to_string(),"operation":"terminal.command_blocks","payload":{}
        })
        .to_string(),
    )
    .unwrap();
    serde_json::from_str::<Value>(&result).unwrap()["payload"]["blocks"].clone()
}
fn finished(events: &[Value], code: i64) -> bool {
    events.iter().any(|e| {
        e["kind"] == "shell_hook"
            && e["payload"]["hook"] == "command_finished"
            && e["payload"]["exit_code"] == code
    }) && events.iter().any(|e| {
        e["kind"] == "shell_command"
            && e["payload"]["eventType"] == "zone_opened"
            && e["payload"]["zoneType"] == "prompt"
    })
}
fn verify(shell: &str) {
    assert!(
        std::path::Path::new(shell).exists(),
        "install test shell: {shell}"
    );
    let home = tempfile::tempdir().unwrap();
    std::fs::write(home.path().join(".zshrc"), "PROMPT='caps> '\nRPROMPT=''\n").unwrap();
    std::fs::write(home.path().join(".bashrc"), "PS1='caps> '\n").unwrap();
    std::fs::create_dir(home.path().join("fish")).unwrap();
    std::fs::write(
        home.path().join("fish/config.fish"),
        "function fish_prompt; printf 'caps> '; end\n",
    )
    .unwrap();
    let corpus: Value = serde_json::from_str(include_str!(
        "fixtures/session_config/session_config_v1_shape_corpus.json"
    ))
    .unwrap();
    let mut config = corpus["valid_local"].clone();
    config["config"]["launch"] = json!({"program":shell,"args":[],"cwd":home.path(),"env":{
        "HOME":home.path(),"ZDOTDIR":home.path(),"XDG_CONFIG_HOME":home.path(),"XDG_DATA_HOME":home.path(),
        "LANG":"en_US.UTF-8","PATH":"/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }});
    let s = Session(session::create_session_v1(&config.to_string()).unwrap());
    let initial = collect(s.0, |events| {
        ["bootstrap.ready", "precmd.pwd"]
            .iter()
            .all(|hook| events.iter().any(|e| e["payload"]["hook"] == *hook))
            && events.iter().any(|e| {
                e["payload"]["eventType"] == "zone_opened" && e["payload"]["zoneType"] == "prompt"
            })
    });
    let ready = &initial
        .iter()
        .find(|e| e["payload"]["hook"] == "bootstrap.ready")
        .unwrap()["payload"];
    assert_eq!(ready["registered"], true, "{shell}: {ready}");
    for name in [
        "hostname",
        "username",
        "integration_version",
        "prompt_navigation",
        "command_output_ranges",
        "user_variables",
    ] {
        assert_eq!(ready["checks"][name], "provided", "{shell}: {name}");
    }
    let metadata = &initial
        .iter()
        .find(|e| e["payload"]["hook"] == "precmd.pwd")
        .unwrap()["payload"];
    for (name, command, args) in [
        ("hostname", "/bin/hostname", vec![]),
        ("username", "/usr/bin/id", vec!["-un"]),
    ] {
        let output = std::process::Command::new(command)
            .args(args)
            .output()
            .unwrap();
        assert_eq!(
            metadata[name].as_str().unwrap(),
            String::from_utf8(output.stdout).unwrap().trim()
        );
    }
    assert_eq!(metadata["integration_version"], "2");
    assert!(!initial.iter().any(|e| e["kind"] == "shell_user_var"
        || e["payload"]["hook"] == "preexec"
        || e["payload"]["hook"] == "command_finished"));
    assert_eq!(
        blocks(s.0).as_array().unwrap().len(),
        0,
        "startup must not invent command history"
    );

    session::write_session(s.0, b"printf 'CAP_START\\nCAP_END\\n'; false\n").unwrap();
    let output = collect(s.0, |events| finished(events, 1));
    let range = &output
        .iter()
        .find(|e| {
            e["payload"]["eventType"] == "zone_closed" && e["payload"]["zoneType"] == "output"
        })
        .unwrap()["payload"];
    assert!(range["zoneId"].as_u64().is_some());
    assert!(range["absRowEnd"].as_u64().unwrap() >= range["absRowStart"].as_u64().unwrap());
    let all = blocks(s.0);
    let rows: Vec<_> = all
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|b| b["lines"].as_array().unwrap())
        .filter_map(|l| l["text"].as_str())
        .collect();
    assert!(
        rows.contains(&"CAP_START") && rows.contains(&"CAP_END"),
        "{all}"
    );
    assert!(
        !rows.iter().any(|row| row.contains("caps>")),
        "prompt leaked into output: {all}"
    );

    session::write_session(
        s.0,
        "ianvs_set_user_var IANVS_PROJECT 'project 中文'\n".as_bytes(),
    )
    .unwrap();
    let variables = collect(s.0, |events| {
        finished(events, 0) && events.iter().any(|e| e["kind"] == "shell_user_var")
    });
    assert!(variables.iter().any(|e| e["kind"] == "shell_user_var"
        && e["payload"]["name"] == "IANVS_PROJECT"
        && e["payload"]["value"] == "project 中文"));
    session::write_session(s.0, b"ianvs_set_user_var PRIVATE_TOKEN 'do-not-publish'\n").unwrap();
    let rejected = collect(s.0, |events| finished(events, 2));
    assert!(!rejected.iter().any(|e| e["kind"] == "shell_user_var"));
    println!(
        "{shell}: actual identity/version, prompt and output coordinates, exit codes, explicit Unicode variable, invalid-name rejection verified"
    );
}
#[test]
fn local_zsh_capabilities() {
    verify("/bin/zsh");
}
#[test]
fn local_system_bash_capabilities() {
    verify("/bin/bash");
}
#[test]
fn local_fish_capabilities() {
    let shell =
        std::env::var("IANVS_TEST_FISH").unwrap_or_else(|_| "/opt/homebrew/bin/fish".into());
    if !std::path::Path::new(&shell).exists() {
        eprintln!("SKIP fish PTY: set IANVS_TEST_FISH to an installed fish");
        return;
    }
    verify(&shell);
}
#[test]
fn local_modern_bash_capabilities() {
    let shell =
        std::env::var("IANVS_TEST_BASH").unwrap_or_else(|_| "/opt/homebrew/bin/bash".into());
    if !std::path::Path::new(&shell).exists() {
        eprintln!("SKIP modern Bash PTY: set IANVS_TEST_BASH to an installed Bash");
        return;
    }
    verify(&shell);
}
fn hook(terminal: &mut Terminal, value: Value) {
    let hex: String = value
        .to_string()
        .bytes()
        .map(|b| format!("{b:02x}"))
        .collect();
    terminal.process(format!("\x1bPhook;{hex}\x1b\\").as_bytes());
}
#[test]
fn user_variable_honors_context_screen_and_bounds() {
    let mut terminal = Terminal::new(80, 24);
    hook(
        &mut terminal,
        json!({"hook":"user_variable","name":"IANVS_PROJECT","value":"root"}),
    );
    assert_eq!(terminal.get_user_var("IANVS_PROJECT"), Some("root"));
    hook(
        &mut terminal,
        json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
    );
    for payload in [
        json!({"hook":"user_variable","context_id":"root","name":"IANVS_PROJECT","value":"stale"}),
        json!({"hook":"user_variable","context_id":"child","name":"PRIVATE_TOKEN","value":"secret"}),
        json!({"hook":"user_variable","context_id":"child","name":"IANVS_PROJECT","value":"x".repeat(513)}),
    ] {
        hook(&mut terminal, payload);
    }
    assert_eq!(terminal.get_user_var("IANVS_PROJECT"), Some("root"));
    assert!(terminal.get_user_var("PRIVATE_TOKEN").is_none());
    terminal.process(b"\x1b[?1049h");
    hook(
        &mut terminal,
        json!({"hook":"user_variable","context_id":"child","name":"IANVS_PROJECT","value":"alternate"}),
    );
    terminal.process(b"\x1b[?1049l");
    assert_eq!(terminal.get_user_var("IANVS_PROJECT"), Some("root"));
    hook(
        &mut terminal,
        json!({"hook":"user_variable","context_id":"child","name":"IANVS_PROJECT","value":"child"}),
    );
    assert_eq!(terminal.get_user_var("IANVS_PROJECT"), Some("child"));
}
