#[path = "fixtures/recording/create.rs"]
mod fixture;
use ianvs_core::recording::file_service::request_json;
use ianvs_core::recording::{ContainerReader, StoredRecord};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

fn operation(op: &str, payload: Value) -> Value {
    let call = |operation: &str, job_id: Value, payload: Value| -> Value {
        serde_json::from_str(&request_json(
            &json!({"schema_version":2,"operation":operation,"job_id":job_id,"payload":payload})
                .to_string(),
        ))
        .unwrap()
    };
    let reserved = call("reserve", Value::Null, json!({}));
    assert_eq!(reserved["ok"], true, "{reserved}");
    let id = reserved["job_id"].clone();
    let result = call(op, id.clone(), payload);
    assert_eq!(call("release", id, json!({}))["ok"], true);
    result
}

fn run(payload: Value) -> Value {
    operation("copy_bundle", payload)
}

fn copy(source: &Path, destination: &Path, budget: u64) -> Value {
    run(json!({"source_path":source,"destination_path":destination,"maximum_bytes":budget}))
}

fn snapshot(root: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut files = BTreeMap::new();
    fn collect(root: &Path, path: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
        for entry in fs::read_dir(path).unwrap() {
            let entry = entry.unwrap();
            if entry.file_type().unwrap().is_dir() {
                collect(root, &entry.path(), files);
            } else {
                files.insert(
                    entry.path().strip_prefix(root).unwrap().to_owned(),
                    fs::read(entry.path()).unwrap(),
                );
            }
        }
    }
    collect(root, root, &mut files);
    files
}

#[test]
fn copies_exact_primary_and_only_referenced_assets_without_touching_external_caches() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    let destination = root.path().join("copy.trailrec");
    fixture::create(&source, 11);
    fs::write(
        source.join("search.index"),
        b"foreign cache stays unchanged",
    )
    .unwrap();
    fs::write(source.join("old.ndjson"), b"legacy fixture is not imported").unwrap();
    fs::write(
        source.join("assets/unused.rgba"),
        b"unreferenced file is ignored",
    )
    .unwrap();
    let before = snapshot(&source);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&source, fs::Permissions::from_mode(0o555)).unwrap();
        fs::set_permissions(source.join("assets"), fs::Permissions::from_mode(0o555)).unwrap();
    }
    let result = copy(&source, &destination, 1024 * 1024);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&source, fs::Permissions::from_mode(0o700)).unwrap();
        fs::set_permissions(source.join("assets"), fs::Permissions::from_mode(0o700)).unwrap();
    }
    assert_eq!(result["ok"], true, "{result}");
    let inspection = &result["result"]["inspection"];
    assert_eq!(inspection["completion"], "finished");
    assert_eq!(inspection["summary"]["visual_count"], 11);
    assert_eq!(inspection["metadata"]["recording_id"], "a".repeat(32));
    let copied = snapshot(&destination);
    assert_eq!(
        copied.len(),
        2,
        "only primary data and its one referenced asset belong to the import"
    );
    for (name, bytes) in &copied {
        assert_eq!(Some(bytes), before.get(name));
    }
    assert_eq!(
        result["result"]["copied_bytes"],
        copied.values().map(|bytes| bytes.len() as u64).sum::<u64>()
    );
    assert_eq!(snapshot(&source), before);
    let reader = ContainerReader::open(&destination).unwrap();
    let report = reader.scan(|| false, |_| Ok(())).unwrap();
    assert_eq!(report.summary.semantic_count, 22);
}

#[test]
fn import_budget_counts_deduplicated_assets_and_cleans_up_on_exhaustion() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    let destination = root.path().join("copy.trailrec");
    fixture::create(&source, 11);
    let primary_bytes = fs::metadata(source.join("records.bin")).unwrap().len();
    let before = snapshot(&source);
    for budget in [
        0,
        primary_bytes - 1,
        primary_bytes,
        primary_bytes + 23,
        9_007_199_254_740_992,
    ] {
        assert_eq!(copy(&source, &destination, budget)["ok"], false);
        assert!(!destination.exists());
        assert_eq!(snapshot(&source), before);
    }
    let result = copy(&source, &destination, primary_bytes + 24);
    assert_eq!(result["ok"], true, "{result}");
    assert_eq!(result["result"]["copied_bytes"], primary_bytes + 24);
}

#[test]
fn interrupted_and_damaged_primary_bytes_remain_exact_and_describe_the_verified_prefix() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    fixture::create(&source, 2);
    let mut reader = ContainerReader::open(&source).unwrap();
    let footer = loop {
        let record = reader.next_record().unwrap().unwrap();
        if matches!(record.record, StoredRecord::Finished(_)) {
            break record.file_offset;
        }
    };
    drop(reader);
    let primary = source.join("records.bin");
    fs::OpenOptions::new()
        .write(true)
        .open(&primary)
        .unwrap()
        .set_len(footer)
        .unwrap();
    let interrupted = root.path().join("interrupted.trailrec");
    let result = copy(&source, &interrupted, 1024 * 1024);
    assert_eq!(result["ok"], true, "{result}");
    assert_eq!(result["result"]["inspection"]["completion"], "interrupted");
    assert_eq!(
        fs::read(interrupted.join("records.bin")).unwrap(),
        fs::read(&primary).unwrap()
    );
    use std::io::Write;
    fs::OpenOptions::new()
        .append(true)
        .open(&primary)
        .unwrap()
        .write_all(b"TRC2short")
        .unwrap();
    let damaged = root.path().join("damaged.trailrec");
    let result = copy(&source, &damaged, 1024 * 1024);
    assert_eq!(result["ok"], true, "{result}");
    assert_eq!(result["result"]["inspection"]["completion"], "damaged_tail");
    assert_eq!(result["result"]["inspection"]["summary"]["visual_count"], 2);
    assert_eq!(
        fs::read(damaged.join("records.bin")).unwrap(),
        fs::read(&primary).unwrap()
    );
}

#[test]
fn missing_or_corrupt_referenced_images_fail_the_copy_without_a_partial_publication() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    let destination = root.path().join("copy.trailrec");
    fixture::create(&source, 2);
    let asset = fs::read_dir(source.join("assets"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let original = fs::read(&asset).unwrap();
    fs::remove_file(&asset).unwrap();
    assert_eq!(copy(&source, &destination, 1024 * 1024)["ok"], false);
    assert!(!destination.exists());
    let mut corrupt = original.clone();
    corrupt[16] ^= 1;
    fs::write(&asset, &corrupt).unwrap();
    assert_eq!(copy(&source, &destination, 1024 * 1024)["ok"], false);
    assert!(!destination.exists());
    assert_eq!(fs::read(&asset).unwrap(), corrupt);
    fs::write(&asset, &original).unwrap();
    assert_eq!(copy(&source, &destination, 1024 * 1024)["ok"], true);
}

#[test]
fn existing_destinations_foreign_paths_and_unknown_payload_shapes_are_rejected_intact() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    let destination = root.path().join("copy.trailrec");
    fixture::create(&source, 2);
    fs::create_dir(&destination).unwrap();
    fs::write(destination.join("preserve"), b"untouched").unwrap();
    assert_eq!(copy(&source, &destination, 1024 * 1024)["ok"], false);
    assert_eq!(
        fs::read(destination.join("preserve")).unwrap(),
        b"untouched"
    );
    let nested = source.join("nested.trailrec");
    assert_eq!(copy(&source, &nested, 1024 * 1024)["ok"], false);
    assert!(!nested.exists());
    let fresh = root.path().join("fresh.trailrec");
    for payload in [
        json!({"source_path":source,"destination_path":fresh,"maximum_bytes":1048576,"extra":true}),
        json!({"source_path":source,"destination_path":fresh}),
        json!({"source_path":"relative.trailrec","destination_path":fresh,"maximum_bytes":1048576}),
        json!({"source_path":source,"destination_path":"relative.trailrec","maximum_bytes":1048576}),
        json!({"source_path":source,"destination_path":fresh,"maximum_bytes":-1}),
    ] {
        assert_eq!(run(payload)["ok"], false);
    }
    assert!(!fresh.exists());
    let legacy = root.path().join("legacy.ndjson");
    fs::write(&legacy, b"old recording").unwrap();
    assert_eq!(copy(&legacy, &fresh, 1024 * 1024)["ok"], false);
    assert_eq!(fs::read(legacy).unwrap(), b"old recording");
}

#[cfg(unix)]
#[test]
fn symlinked_sources_or_assets_are_never_imported() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    let destination = root.path().join("copy.trailrec");
    fixture::create(&source, 2);
    let alias = root.path().join("alias.trailrec");
    std::os::unix::fs::symlink(&source, &alias).unwrap();
    assert_eq!(copy(&alias, &destination, 1024 * 1024)["ok"], false);
    let moved = root.path().join("moved-assets");
    fs::rename(source.join("assets"), &moved).unwrap();
    std::os::unix::fs::symlink(&moved, source.join("assets")).unwrap();
    let before = snapshot(&moved);
    assert_eq!(copy(&source, &destination, 1024 * 1024)["ok"], false);
    assert!(!destination.exists());
    assert_eq!(snapshot(&moved), before);
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
#[test]
fn publication_never_replaces_an_existing_bundle_and_validates_staging_identity() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.trailrec");
    let staging = root.path().join("staging.trailrec");
    let destination = root.path().join(format!("{}.trailrec", "a".repeat(32)));
    fixture::create(&source, 2);
    let original = snapshot(&source);
    assert_eq!(copy(&source, &staging, 1024 * 1024)["ok"], true);
    let staged = snapshot(&staging);
    let publish = |id: &str| {
        operation(
            "publish_bundle",
            json!({"staging_path":staging,"destination_path":destination,"recording_id":id}),
        )
    };
    assert_eq!(publish(&"b".repeat(32))["ok"], false);
    assert_eq!(snapshot(&staging), staged);
    assert!(!destination.exists());
    fs::create_dir(&destination).unwrap();
    // Even an empty destination must not be replaced.
    assert_eq!(publish(&"a".repeat(32))["ok"], false);
    assert_eq!(snapshot(&staging), staged);
    assert!(snapshot(&destination).is_empty());
    fs::write(destination.join("preserve"), b"foreign destination").unwrap();
    assert_eq!(publish(&"a".repeat(32))["ok"], false);
    assert_eq!(
        fs::read(destination.join("preserve")).unwrap(),
        b"foreign destination"
    );
    fs::remove_file(destination.join("preserve")).unwrap();
    fs::remove_dir(&destination).unwrap();
    let result = publish(&"a".repeat(32));
    assert_eq!(result["ok"], true, "{result}");
    assert_eq!(result["result"], json!({}));
    assert!(!staging.exists());
    assert_eq!(snapshot(&destination), staged);
    assert_eq!(snapshot(&source), original);
}
