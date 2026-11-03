use ianvs_core::recording::{HookTimeline, RecordingError, SemanticKind, TimelineContext};
use serde_json::json;

fn timeline() -> HookTimeline {
    HookTimeline::new(TimelineContext {
        id: "root".into(),
        cwd: Some("/local".into()),
        hostname: Some("laptop".into()),
    })
    .unwrap()
}

#[test]
fn full_command_arguments_unicode_and_multiline_are_preserved_and_paired() {
    let mut timeline = timeline();
    let command = format!(
        "printf '雪 ❄\\n'\n{} --argument='with spaces'",
        "x".repeat(2048)
    );
    let started = timeline
        .observe_hook(1, &json!({"hook":"preexec", "command":command}))
        .unwrap();
    let start = started
        .iter()
        .find(|e| e.kind == SemanticKind::CommandStarted)
        .unwrap();
    assert_eq!(start.command.as_deref(), Some(command.as_str()));
    timeline
        .observe_context(2, &json!({"cwd":"/changed"}))
        .unwrap();
    let finished = timeline
        .observe_hook(
            3,
            &json!({"hook":"command_finished", "command":command, "exit_code":7}),
        )
        .unwrap();
    let finish = finished
        .iter()
        .find(|e| e.kind == SemanticKind::CommandFinished)
        .unwrap();
    assert_eq!(finish.command_id, start.command_id);
    assert_eq!(finish.exit_code, Some(7));
    assert_eq!(finish.cwd.as_deref(), Some("/local"));
    assert_eq!(finish.offset_micros, 3);
}

#[test]
fn nested_ssh_contexts_do_not_overwrite_parent_commands() {
    let mut timeline = timeline();
    let started = timeline
        .observe_hook(10, &json!({"hook":"preexec","command":"ssh server"}))
        .unwrap();
    let parent_id = started
        .iter()
        .find(|e| e.kind == SemanticKind::CommandStarted)
        .unwrap()
        .command_id
        .clone();
    timeline.observe_hook(20, &json!({"hook":"bootstrap.ready","context_id":"remote", "host":"server", "registered":true})).unwrap();
    let remote = timeline
        .observe_hook(
            30,
            &json!({"hook":"preexec","context_id":"remote","command":"tail -f /var/log/app"}),
        )
        .unwrap();
    assert_eq!(remote.last().unwrap().hostname.as_deref(), Some("server"));
    let resume = timeline
        .observe_hook(
            40,
            &json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["remote"]}),
        )
        .unwrap();
    assert!(resume.iter().any(|e| e.context_id == "remote"
        && e.kind == SemanticKind::HookUnavailable
        && e.command_id.is_some()));
    let finished = timeline
        .observe_hook(
            50,
            &json!({"hook":"command_finished","command":"ssh server","exit_code":255}),
        )
        .unwrap();
    let finish = finished
        .iter()
        .find(|e| e.kind == SemanticKind::CommandFinished)
        .unwrap();
    assert_eq!(finish.command_id, parent_id);
    assert_eq!(finish.hostname.as_deref(), Some("laptop"));
}

#[test]
fn missing_start_and_replaced_command_are_explicit_coverage_gaps() {
    let mut timeline = timeline();
    assert!(
        timeline
            .initial_events()
            .iter()
            .any(|e| e.kind == SemanticKind::HookUnavailable)
    );
    let orphan = timeline
        .observe_hook(
            10,
            &json!({"hook":"command_finished","command":"started before capture","exit_code":0}),
        )
        .unwrap();
    assert!(
        orphan
            .iter()
            .any(|e| e.kind == SemanticKind::HookUnavailable)
    );
    assert!(
        !orphan
            .iter()
            .any(|e| e.kind == SemanticKind::CommandStarted)
    );
    let first = timeline
        .observe_hook(20, &json!({"hook":"preexec","command":"lost finish"}))
        .unwrap();
    let id = first.last().unwrap().command_id.clone();
    let second = timeline
        .observe_hook(30, &json!({"hook":"preexec","command":"next command"}))
        .unwrap();
    assert!(
        second
            .iter()
            .any(|e| e.kind == SemanticKind::HookUnavailable && e.command_id == id)
    );
    assert_eq!(
        second.last().unwrap().command.as_deref(),
        Some("next command")
    );
}

#[test]
fn malformed_or_oversized_hook_does_not_consume_ids_or_clock() {
    let mut timeline = timeline();
    assert_eq!(
        timeline.observe_hook(100, &json!({"hook":"preexec","command":"x".repeat(65_537)})),
        Err(RecordingError::InvalidSemanticEvent)
    );
    assert!(
        timeline
            .observe_hook(
                100,
                &json!({"hook":"preexec","context_id":42,"command":"echo"})
            )
            .is_err()
    );
    let valid = timeline
        .observe_hook(10, &json!({"hook":"preexec","command":"first"}))
        .unwrap();
    assert_eq!(valid.last().unwrap().command_id.as_deref(), Some("0"));
    assert!(
        timeline
            .observe_hook(
                20,
                &json!({"hook":"command_finished","exit_code":9_999_999_999_i64})
            )
            .is_err()
    );
    let finish = timeline
        .observe_hook(11, &json!({"hook":"command_finished","exit_code":0}))
        .unwrap();
    assert_eq!(finish.last().unwrap().command_id.as_deref(), Some("0"));
}

#[test]
fn retired_contexts_release_memory_for_many_sequential_remote_sessions() {
    let mut timeline = timeline();
    for index in 0..200 {
        let context = format!("remote-{index}");
        timeline
            .observe_hook(
                index * 10 + 1,
                &json!({"hook":"bootstrap.ready","context_id":context,"registered":true}),
            )
            .unwrap();
        timeline
            .observe_hook(
                index * 10 + 2,
                &json!({"hook":"preexec","context_id":context,"command":"true"}),
            )
            .unwrap();
        timeline.observe_hook(index * 10 + 3, &json!({"hook":"command_finished","context_id":context,"command":"true","exit_code":0})).unwrap();
        timeline.observe_hook(index * 10 + 4, &json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":[context]})).unwrap();
    }
}

#[test]
fn unavailable_bootstrap_is_recorded_and_unrelated_hooks_are_not_commands() {
    let mut timeline = timeline();
    let unavailable = timeline
        .observe_hook(
            1,
            &json!({"hook":"bootstrap.ready","context_id":"remote","registered":false}),
        )
        .unwrap();
    assert_eq!(
        unavailable.last().unwrap().kind,
        SemanticKind::HookUnavailable
    );
    assert!(
        timeline
            .observe_hook(
                2,
                &json!({"hook":"some_future_hook", "command":"do not execute"})
            )
            .unwrap()
            .is_empty()
    );
    let prompt = timeline
        .observe_hook(
            3,
            &json!({"hook":"precmd.pwd", "context_id":"remote", "pwd":"/srv"}),
        )
        .unwrap();
    assert!(prompt.iter().any(|e| e.kind == SemanticKind::HookAvailable));
    assert!(
        !prompt
            .iter()
            .any(|e| e.kind == SemanticKind::CommandStarted)
    );
}
