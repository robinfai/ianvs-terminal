//! Optional, bounded local IO. The pure matcher never opens files or processes.
use ianvs_completion_core::{CompletionBatch, CompletionEdit, CompletionQuery, LocalContext};
use serde::Deserialize;
use serde_json::{Value, json};
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};
use std::time::{Duration, Instant};

static WORKERS: AtomicUsize = AtomicUsize::new(0);
const MAX_ENTRIES: usize = 512;
const MAX_ITEMS: usize = 60;
const MAX_PACKAGE: u64 = 262_144;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct LocalPolicy {
    pub files: bool,
    pub scripts: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Start {
    pub query: CompletionQuery,
    pub lease: String,
    pub policy: LocalPolicy,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct JobRequest {
    pub job_id: String,
}

struct Job {
    id: String,
    lease: String,
    cancelled: Arc<AtomicBool>,
    result: Arc<Mutex<Option<Value>>>,
    finished: Arc<AtomicBool>,
}

#[derive(Default)]
pub(crate) struct LocalCompletions {
    serial: u64,
    job: Option<Job>,
}

impl Drop for LocalCompletions {
    fn drop(&mut self) {
        if let Some(job) = &self.job {
            job.cancelled.store(true, Ordering::Relaxed);
        }
    }
}

struct Permit;
impl Drop for Permit {
    fn drop(&mut self) {
        WORKERS.fetch_sub(1, Ordering::Relaxed);
    }
}

impl LocalCompletions {
    pub fn start(&mut self, request: Start, cwd: PathBuf) -> Value {
        if !request.policy.files && !request.policy.scripts {
            return json!({"status":"denied"});
        }
        let Some(plan) = ianvs_completion_core::local_context(&request.query) else {
            return json!({"status":"unsupported"});
        };
        if !cwd.is_absolute() {
            return json!({"status":"denied"});
        }
        if let Some(job) = &self.job {
            job.cancelled.store(true, Ordering::Relaxed);
            if !job.finished.load(Ordering::Acquire) {
                return json!({"status":"busy"});
            }
        }
        if WORKERS
            .fetch_update(Ordering::AcqRel, Ordering::Relaxed, |n| {
                (n < 2).then_some(n + 1)
            })
            .is_err()
        {
            return json!({"status":"busy"});
        }
        let permit = Permit;
        self.serial += 1;
        let id = self.serial.to_string();
        let cancelled = Arc::new(AtomicBool::new(false));
        let result = Arc::new(Mutex::new(None));
        let finished = Arc::new(AtomicBool::new(false));
        let job = Job {
            id: id.clone(),
            lease: request.lease,
            cancelled: cancelled.clone(),
            result: result.clone(),
            finished: finished.clone(),
        };
        let spawned = std::thread::Builder::new()
            .name("composer-local".into())
            .spawn(move || {
                let _permit = permit;
                let items = collect(&cwd, &plan, &request.policy, &cancelled);
                if !cancelled.load(Ordering::Relaxed) {
                    *result.lock().unwrap() = Some(
                        serde_json::to_value(CompletionBatch {
                            schema_version: 1,
                            query: request.query,
                            status: "ok",
                            items,
                        })
                        .expect("completion batch"),
                    );
                }
                finished.store(true, Ordering::Release);
            });
        if spawned.is_err() {
            return json!({"status":"unavailable"});
        }
        self.job = Some(job);
        json!({"status":"pending","jobId":id})
    }

    pub fn poll(&mut self, id: &str, current_lease: Option<&str>) -> Value {
        let Some(job) = self.job.as_ref().filter(|j| j.id == id) else {
            return json!({"status":"cancelled"});
        };
        if current_lease != Some(job.lease.as_str()) || job.cancelled.load(Ordering::Relaxed) {
            job.cancelled.store(true, Ordering::Relaxed);
            return json!({"status":"cancelled"});
        }
        if let Some(batch) = job.result.lock().unwrap().take() {
            return json!({"status":"complete","batch":batch});
        }
        if job.finished.load(Ordering::Acquire) {
            json!({"status":"complete"})
        } else {
            json!({"status":"pending"})
        }
    }

    pub fn cancel(&self, id: &str) -> Value {
        if let Some(job) = self.job.as_ref().filter(|j| j.id == id) {
            job.cancelled.store(true, Ordering::Relaxed);
        }
        json!({"status":"cancelled"})
    }
}

fn clean(value: &str) -> bool {
    value.len() <= 2048
        && !value.chars().any(|c| {
            c.is_control() || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
}

fn collect(
    cwd: &Path,
    plan: &LocalContext,
    policy: &LocalPolicy,
    cancelled: &AtomicBool,
) -> Vec<CompletionEdit> {
    let deadline = Instant::now() + Duration::from_millis(150);
    let stopped = || cancelled.load(Ordering::Relaxed) || Instant::now() >= deadline;
    let mut items = vec![];
    if stopped() || !clean(&plan.prefix) {
        return items;
    }
    let Ok(root) = cwd.canonicalize() else {
        return items;
    };
    if policy.files
        && plan
            .templates
            .iter()
            .any(|t| matches!(t.as_str(), "files" | "folders" | "filepaths"))
    {
        let (parent, prefix) = plan
            .prefix
            .rsplit_once('/')
            .map_or(("", plan.prefix.as_str()), |(a, b)| (a, b));
        // No process cwd fallback, tilde expansion, ancestor search, or traversal
        // through a symlink outside this session's current directory.
        let relative = Path::new(parent);
        if !plan.prefix.starts_with(['/', '~'])
            && relative
                .components()
                .all(|c| matches!(c, Component::Normal(_) | Component::CurDir))
        {
            let folder = root.join(relative).canonicalize();
            if let Ok(folder) = folder
                && folder.starts_with(&root)
                && !stopped()
                && let Ok(entries) = std::fs::read_dir(folder)
            {
                for entry in entries.take(MAX_ENTRIES) {
                    if stopped() || items.len() >= MAX_ITEMS {
                        break;
                    }
                    let Ok(entry) = entry else {
                        continue;
                    };
                    let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                        continue;
                    };
                    if !clean(&name)
                        || !name.starts_with(prefix)
                        || (name.starts_with('.') && !prefix.starts_with('.'))
                    {
                        continue;
                    }
                    let Ok(kind) = entry.file_type() else {
                        continue;
                    };
                    if kind.is_symlink() || (!kind.is_dir() && !kind.is_file()) {
                        continue;
                    }
                    let directories_only = plan.templates.iter().all(|t| t == "folders");
                    if directories_only && !kind.is_dir() {
                        continue;
                    }
                    // Directories remain navigable in a file argument.
                    let mut value = if parent.is_empty() {
                        name.clone()
                    } else {
                        format!("{parent}/{name}")
                    };
                    if value.starts_with('-') {
                        value.insert_str(0, "./");
                    }
                    if kind.is_dir() {
                        value.push('/');
                    }
                    items.push(edit(
                        plan,
                        &value,
                        if kind.is_dir() { "directory" } else { "file" },
                        "local:files",
                    ));
                }
            }
        }
    }
    if policy.scripts && plan.templates.iter().any(|t| t == "packageScripts") && !stopped() {
        // Read only the regular package.json in this exact cwd; never run npm,
        // evaluate scripts, follow config symlinks, or climb through ancestors.
        let path = root.join("package.json");
        if let Ok(meta) = path.symlink_metadata()
            && meta.is_file()
            && meta.len() <= MAX_PACKAGE
        {
            let mut options = std::fs::OpenOptions::new();
            options.read(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
            }
            if !stopped()
                && let Ok(file) = options.open(path)
                && file
                    .metadata()
                    .is_ok_and(|m| m.is_file() && m.len() <= MAX_PACKAGE)
            {
                let mut bytes = Vec::new();
                if file.take(MAX_PACKAGE + 1).read_to_end(&mut bytes).is_ok()
                    && bytes.len() as u64 <= MAX_PACKAGE
                    && !stopped()
                    && let Ok(value) = serde_json::from_slice::<Value>(&bytes)
                    && let Some(scripts) = value.get("scripts").and_then(Value::as_object)
                {
                    for (name, value) in scripts.iter().take(MAX_ENTRIES) {
                        if stopped() || items.len() >= MAX_ITEMS {
                            break;
                        }
                        if value.is_string()
                            && clean(name)
                            && !name.starts_with('-')
                            && name.starts_with(&plan.prefix)
                        {
                            items.push(edit(plan, name, "script", "local:packageScripts"));
                        }
                    }
                }
            }
        }
    }
    items.sort_by(|a, b| a.label.cmp(&b.label));
    let mut bytes = 0;
    items.retain(|item| {
        bytes += serde_json::to_vec(item).map_or(usize::MAX / 100, |v| v.len());
        bytes <= 96 * 1024
    });
    items
}

fn edit(plan: &LocalContext, value: &str, kind: &str, source: &str) -> CompletionEdit {
    let new_text = ianvs_completion_core::quote_literal(value, plan.quoted);
    CompletionEdit {
        item_id: format!("{source}:{}:{}:{new_text}", plan.start, plan.end),
        label: value.into(),
        detail: if kind == "script" {
            "package.json".into()
        } else {
            String::new()
        },
        kind: kind.into(),
        source: source.into(),
        replace_start_utf16: plan.start,
        replace_end_utf16: plan.end,
        final_cursor_utf16: plan.start + new_text.encode_utf16().count(),
        new_text,
        risk_hint: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn plan(template: &str, prefix: &str) -> LocalContext {
        LocalContext {
            templates: vec![template.into()],
            prefix: prefix.into(),
            start: 4,
            end: 4 + prefix.len(),
            quoted: false,
        }
    }
    #[test]
    fn files_are_bounded_quoted_and_scoped() {
        let dir = tempfile::tempdir().unwrap();
        for name in ["normal", "a b;echo nope", "line\nbreak", "\u{1b}escape"] {
            std::fs::write(dir.path().join(name), "").unwrap();
        }
        #[cfg(unix)]
        std::os::unix::fs::symlink("/", dir.path().join("escape")).unwrap();
        let policy = LocalPolicy {
            files: true,
            scripts: false,
        };
        let cancel = AtomicBool::new(false);
        let items = collect(dir.path(), &plan("files", ""), &policy, &cancel);
        assert_eq!(items.len(), 2);
        assert!(items.iter().any(|i| i.new_text == "'a b;echo nope'"));
        assert!(collect(dir.path(), &plan("files", "../"), &policy, &cancel).is_empty());
        assert!(collect(dir.path(), &plan("files", "escape/"), &policy, &cancel).is_empty());
        cancel.store(true, Ordering::Relaxed);
        assert!(collect(dir.path(), &plan("files", ""), &policy, &cancel).is_empty());
    }
    #[test]
    fn script_contents_never_execute_and_policy_is_required() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("package.json"), r#"{"scripts":{"test":"touch MUST_NOT_EXIST","test;echo nope":"anything","-unsafe":"x"}}"#).unwrap();
        let plan = plan("packageScripts", "test");
        let cancel = AtomicBool::new(false);
        assert!(
            collect(
                dir.path(),
                &plan,
                &LocalPolicy {
                    files: false,
                    scripts: false
                },
                &cancel
            )
            .is_empty()
        );
        let items = collect(
            dir.path(),
            &plan,
            &LocalPolicy {
                files: false,
                scripts: true,
            },
            &cancel,
        );
        assert_eq!(items.len(), 2);
        assert!(items.iter().any(|i| i.new_text == "'test;echo nope'"));
        assert!(!dir.path().join("MUST_NOT_EXIST").exists());
    }
}
