//! Recording file operations have no Session/PTY dependency. The caller runs
//! blocking work off its UI thread; cancellation is an independent atomic request.
use super::assets::AssetBinding;
use super::cache::{self, FileStamp, TIMELINE_HEADER_BYTES, TIMELINE_MAGIC};
use super::index::metadata_fingerprint;
use super::storage::open_regular_file;
use super::{
    ContainerReader, RecordingCompletion, RecordingIndex, SemanticEvent, StorageError,
    StorageResult, StoredRecord,
};
use base64::{Engine, engine::general_purpose::STANDARD};
use parking_lot::Mutex;
use prost::Message;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock};

const MAX_JOBS: usize = 8;
const MAX_RESPONSE_BYTES: usize = 48 * 1024 * 1024;
static NEXT_JOB: AtomicU64 = AtomicU64::new(1);
static JOBS: LazyLock<Mutex<HashMap<u64, Arc<Job>>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

struct Job {
    cancelled: AtomicBool,
    // 0 reserved, 1 running, 2 settled. Release never removes running work.
    phase: AtomicU8,
}
struct Completion(Arc<Job>);
impl Drop for Completion {
    fn drop(&mut self) {
        self.0.phase.store(2, Ordering::Release);
    }
}
impl Job {
    fn check(&self) -> StorageResult<()> {
        if self.cancelled.load(Ordering::Acquire) {
            Err(StorageError::Cancelled)
        } else {
            Ok(())
        }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    schema_version: u32,
    job_id: Option<String>,
    operation: String,
    payload: Value,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Inspect {
    bundle_path: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DirectorySyncRequest {
    directory_path: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MetadataRequest {
    bundle_path: String,
    recording_id: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SeekRequest {
    bundle_path: String,
    recording_id: String,
    offset_micros: u64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct TimelineRequest {
    bundle_path: String,
    recording_id: String,
    cursor: u64,
    limit: usize,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AssetRequest {
    bundle_path: String,
    recording_id: String,
    binding: AssetWire,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AssetWire {
    asset_id: u64,
    asset_version: u64,
    width: u32,
    height: u32,
    digest: Vec<u8>,
}

pub fn request_json(raw: &str) -> String {
    let request = if raw.len() <= 64 * 1024 {
        serde_json::from_str::<Request>(raw).ok()
    } else {
        None
    };
    let Some(request) = request.filter(|r| r.schema_version == 2 && r.payload.is_object()) else {
        return json!({"schema_version":2,"operation":"invalid","job_id":null,"ok":false,"error":"invalid recording file request"}).to_string();
    };
    let mut job_id = request.job_id.clone();
    let result = dispatch(&request, &mut job_id);
    let response = match result {
        Ok(result) => {
            json!({"schema_version":2,"operation":request.operation,"job_id":job_id,"ok":true,"result":result})
        }
        Err(error) => {
            json!({"schema_version":2,"operation":request.operation,"job_id":job_id,"ok":false,"error":error.to_string()})
        }
    };
    let encoded = response.to_string();
    if encoded.len() <= MAX_RESPONSE_BYTES {
        encoded
    } else {
        json!({"schema_version":2,"operation":request.operation,"job_id":job_id,"ok":false,"error":"recording response exceeds byte limit"}).to_string()
    }
}

fn dispatch(request: &Request, response_id: &mut Option<String>) -> StorageResult<Value> {
    if matches!(request.operation.as_str(), "reserve" | "cancel" | "release")
        && request.payload != json!({})
    {
        return Err(StorageError::Invalid("control payload must be empty"));
    }
    if request.operation == "reserve" {
        if request.job_id.is_some() {
            return Err(StorageError::Invalid("reserve does not accept a job id"));
        }
        let mut jobs = JOBS.lock();
        if jobs.len() >= MAX_JOBS {
            return Err(StorageError::QueueExhausted);
        }
        let id = NEXT_JOB
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |id| id.checked_add(1))
            .map_err(|_| StorageError::QueueExhausted)?;
        jobs.insert(
            id,
            Arc::new(Job {
                cancelled: AtomicBool::new(false),
                phase: AtomicU8::new(0),
            }),
        );
        *response_id = Some(id.to_string());
        return Ok(json!({}));
    }
    let id = request
        .job_id
        .as_ref()
        .and_then(|id| id.parse::<u64>().ok())
        .filter(|id| *id > 0)
        .ok_or(StorageError::Invalid("invalid file job id"))?;
    if request.job_id.as_deref() != Some(id.to_string().as_str()) {
        return Err(StorageError::Invalid("noncanonical file job id"));
    }
    let mut jobs = JOBS.lock();
    let job = jobs
        .get(&id)
        .cloned()
        .ok_or(StorageError::Invalid("unknown file job"))?;
    match request.operation.as_str() {
        "cancel" => {
            job.cancelled.store(true, Ordering::Release);
            return Ok(json!({}));
        }
        "release" => {
            if job.phase.load(Ordering::Acquire) == 1 {
                return Err(StorageError::Invalid("file job still running"));
            }
            jobs.remove(&id);
            return Ok(json!({}));
        }
        "inspect" | "metadata" | "seek" | "timeline" | "asset" | "search" | "sync_directory" => {}
        _ => {
            return Err(StorageError::Invalid(
                "unsupported recording file operation",
            ));
        }
    }
    job.phase
        .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
        .map_err(|_| StorageError::Invalid("file job already used"))?;
    drop(jobs);
    let _completion = Completion(job.clone());
    job.check()?;
    let result = match request.operation.as_str() {
        "sync_directory" => sync_directory(serde_json::from_value(request.payload.clone())?),
        "inspect" => inspect(serde_json::from_value(request.payload.clone())?, &job),
        "metadata" => {
            let input: MetadataRequest = serde_json::from_value(request.payload.clone())?;
            let source = reader(&input.bundle_path, Some(&input.recording_id))?;
            Ok(json!({"metadata":source.metadata}))
        }
        "seek" => seek(serde_json::from_value(request.payload.clone())?, &job),
        "timeline" => timeline(serde_json::from_value(request.payload.clone())?, &job),
        "asset" => asset(serde_json::from_value(request.payload.clone())?, &job),
        "search" => {
            let input: super::search::SearchRequest =
                serde_json::from_value(request.payload.clone())?;
            let source = reader(&input.bundle_path, Some(&input.recording_id))?;
            Ok(serde_json::to_value(super::search::page(
                &input,
                &source.metadata,
                || job.cancelled.load(Ordering::Acquire),
            )?)?)
        }
        _ => unreachable!(),
    }?;
    job.check()?;
    Ok(result)
}

// Library metadata uses the same bounded worker pool as recording reads. A
// success acknowledges the directory publication, never only an enqueued job.
fn sync_directory(request: DirectorySyncRequest) -> StorageResult<Value> {
    let path = Path::new(&request.directory_path);
    if request.directory_path.len() > 4096
        || request.directory_path.contains('\0')
        || !path.is_absolute()
    {
        return Err(StorageError::Invalid(
            "expected an absolute library directory",
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        fs::OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(path)?
            .sync_all()?;
        Ok(json!({}))
    }
    #[cfg(not(unix))]
    Err(StorageError::Invalid(
        "directory durability is unavailable on this platform",
    ))
}

fn reader(path: &str, expected_id: Option<&str>) -> StorageResult<ContainerReader> {
    let root = Path::new(path);
    if path.len() > 4096
        || path.contains('\0')
        || !root.is_absolute()
        || root.extension().and_then(|x| x.to_str()) != Some("trailrec")
        || !fs::symlink_metadata(root)?.is_dir()
    {
        return Err(StorageError::Invalid(
            "expected an absolute sampled recording bundle",
        ));
    }
    let reader = ContainerReader::open(root)?;
    if expected_id.is_some_and(|id| id != reader.metadata.recording_id) {
        return Err(StorageError::Invalid("recording identity changed"));
    }
    Ok(reader)
}

fn inspect(request: Inspect, job: &Job) -> StorageResult<Value> {
    let root = Path::new(&request.bundle_path);
    let reader = reader(&request.bundle_path, None)?;
    let metadata = reader.metadata;
    let source_bytes = fs::metadata(root.join("records.bin"))?.len();
    if let Ok(report) = cache::load_report(root, &metadata) {
        job.check()?;
        return inspection_result(metadata, source_bytes, report);
    }
    let source_stamp = FileStamp::read(&root.join("records.bin"))?;
    let mut commands = tempfile::NamedTempFile::new_in(root)?;
    commands.write_all(&[0; TIMELINE_HEADER_BYTES])?;
    let report = RecordingIndex::rebuild_with_visitor(
        root,
        || job.cancelled.load(Ordering::Acquire),
        |record| {
            if let StoredRecord::Semantic(event) = &record.record {
                cache::write_event(&mut commands, event)?;
            }
            Ok(())
        },
    )?;
    job.check()?;
    if FileStamp::read(&root.join("records.bin"))? != source_stamp {
        return Err(StorageError::Invalid("recording changed during inspection"));
    }
    commands.seek(SeekFrom::Start(0))?;
    cache::write_timeline_header(
        &mut commands,
        source_bytes,
        &metadata_fingerprint(&metadata)?,
    )?;
    commands.as_file().sync_all()?;
    job.check()?;
    commands
        .persist(root.join("commands.index"))
        .map_err(|e| e.error)?;
    super::assets::sync_directory(root)?;
    // A failed optional summary cache does not invalidate recovered primary data.
    let _ = cache::publish_report(root, &metadata, source_stamp, &report);
    inspection_result(metadata, source_bytes, report)
}

fn inspection_result(
    metadata: super::RecordingMetadata,
    source_bytes: u64,
    report: super::ScanReport,
) -> StorageResult<Value> {
    let (completion, error) = match report.completion {
        RecordingCompletion::Finished => ("finished", None),
        RecordingCompletion::Interrupted => ("interrupted", None),
        RecordingCompletion::DamagedTail(error) => ("damaged_tail", Some(error)),
    };
    Ok(
        json!({"metadata":metadata,"summary":report.summary,"completion":completion,"error":error,"source_bytes":source_bytes,"verified_bytes":report.verified_bytes}),
    )
}

fn seek(request: SeekRequest, job: &Job) -> StorageResult<Value> {
    reader(&request.bundle_path, Some(&request.recording_id))?;
    let mut index = RecordingIndex::open(Path::new(&request.bundle_path))?;
    let screen = index.seek(request.offset_micros, || {
        job.cancelled.load(Ordering::Acquire)
    })?;
    let Some(screen) = screen else {
        return Ok(json!({"screen":null}));
    };
    let assets = screen.assets.iter().map(|a| json!({"asset_id":a.asset_id,"asset_version":a.asset_version,"width":a.width,"height":a.height,"digest":a.digest})).collect::<Vec<_>>();
    Ok(
        json!({"screen":{"offset_micros":screen.offset_micros,"sequence":screen.sequence,"frame_base64":STANDARD.encode(screen.frame.encode_to_vec()),"assets":assets}}),
    )
}

fn asset(request: AssetRequest, job: &Job) -> StorageResult<Value> {
    let reader = reader(&request.bundle_path, Some(&request.recording_id))?;
    job.check()?;
    let b = request.binding;
    let asset = reader.load_asset(&AssetBinding {
        asset_id: b.asset_id,
        asset_version: b.asset_version,
        width: b.width,
        height: b.height,
        digest: b.digest,
    })?;
    job.check()?;
    Ok(
        json!({"asset_id":asset.asset_id,"asset_version":asset.asset_version,"width":asset.width,"height":asset.height,"rgba_base64":STANDARD.encode(asset.rgba)}),
    )
}

fn timeline(request: TimelineRequest, job: &Job) -> StorageResult<Value> {
    if request.limit == 0 || request.limit > 128 {
        return Err(StorageError::Invalid("timeline page limit must be 1..128"));
    }
    let source = reader(&request.bundle_path, Some(&request.recording_id))?;
    let root = Path::new(&request.bundle_path);
    let source_bytes = fs::metadata(root.join("records.bin"))?.len();
    let mut file = open_regular_file(&root.join("commands.index"))?;
    let mut header = [0u8; TIMELINE_HEADER_BYTES];
    file.read_exact(&mut header)?;
    if &header[..8] != TIMELINE_MAGIC
        || header[8..16] != source_bytes.to_le_bytes()
        || header[16..48] != metadata_fingerprint(&source.metadata)?
        || Sha256::digest(&header[..48]).as_slice() != &header[48..]
    {
        return Err(StorageError::Invalid("stale or invalid timeline index"));
    }
    let length = file.metadata()?.len();
    let mut cursor = if request.cursor == 0 {
        TIMELINE_HEADER_BYTES as u64
    } else {
        request.cursor
    };
    if cursor < TIMELINE_HEADER_BYTES as u64 || cursor > length {
        return Err(StorageError::Invalid("invalid timeline cursor"));
    }
    file.seek(SeekFrom::Start(cursor))?;
    let mut events = Vec::new();
    let mut payload_bytes = 0usize;
    while cursor < length && events.len() < request.limit && payload_bytes < 4 * 1024 * 1024 {
        job.check()?;
        let mut entry = [0u8; 36];
        file.read_exact(&mut entry)?;
        let bytes = u32::from_le_bytes(entry[..4].try_into().unwrap()) as usize;
        if bytes > 1024 * 1024 || bytes as u64 > length.saturating_sub(cursor + 36) {
            return Err(StorageError::Invalid("invalid timeline entry length"));
        }
        let mut payload = vec![0; bytes];
        file.read_exact(&mut payload)?;
        if Sha256::digest(&payload).as_slice() != &entry[4..] {
            return Err(StorageError::Invalid("timeline entry checksum mismatch"));
        }
        let event: SemanticEvent = serde_json::from_slice(&payload)?;
        event.validate()?;
        events.push(event);
        cursor += 36 + bytes as u64;
        payload_bytes += bytes;
    }
    Ok(json!({"events":events,"next_cursor":if cursor < length {Some(cursor)} else {None}}))
}
