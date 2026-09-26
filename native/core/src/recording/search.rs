//! Local, disposable text index for retained screens and hook commands.
//! No raw input, PTY, parser replay, image OCR or unsampled output is searched.
use super::cache::FileStamp;
use super::index::metadata_fingerprint;
use super::storage::open_regular_file;
use super::{
    ContainerReader, RecordingMetadata, ScreenReplay, SemanticKind, StorageError, StorageResult,
    StoredRecord,
};
use crate::proto::frame_diff::TerminalFrameDiff;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

const MAGIC: &[u8; 8] = b"TRLTXT02";
const MAX_TEXT_BYTES: usize = 16 * 1024 * 1024;
const MAX_META_BYTES: usize = 512 * 1024;
const PAGE_SCAN_BYTES: u64 = 4 * 1024 * 1024;
const PAGE_SCAN_DOCUMENTS: usize = 2048;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(super) enum SearchKind {
    #[default]
    All,
    Command,
    Screen,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct SearchRequest {
    pub bundle_path: String,
    pub recording_id: String,
    pub query: String,
    pub hostname: Option<String>,
    pub kind: SearchKind,
    pub cursor: u64,
    pub limit: usize,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    offset_micros: u64,
    kind: SearchKind,
    hostname: Option<String>,
    row: Option<u32>,
}

#[derive(Serialize)]
pub(super) struct Hit {
    #[serde(flatten)]
    document: Document,
    preview: String,
}

#[derive(Serialize)]
pub(super) struct SearchPage {
    hits: Vec<Hit>,
    next_cursor: Option<u64>,
    scanned_bytes: u64,
    total_bytes: u64,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    schema_version: u32,
    metadata: [u8; 32],
    source: FileStamp,
    index: FileStamp,
}

fn current(path: &Path, metadata: &RecordingMetadata) -> StorageResult<bool> {
    let mut file = open_regular_file(&path.join("search.info"))?;
    let length = file.metadata()?.len();
    if !(32..=64 * 1024).contains(&length) {
        return Ok(false);
    }
    let mut checksum = [0; 32];
    file.read_exact(&mut checksum)?;
    let mut payload = vec![0; length as usize - 32];
    file.read_exact(&mut payload)?;
    if Sha256::digest(&payload).as_slice() != checksum {
        return Ok(false);
    }
    let manifest: Manifest = serde_json::from_slice(&payload)?;
    Ok(manifest.schema_version == 2
        && manifest.metadata == metadata_fingerprint(metadata)?
        && manifest.source == FileStamp::read(&path.join("records.bin"))?
        && manifest.index == FileStamp::read(&path.join("search.index"))?)
}

fn write_document(output: &mut impl Write, document: &Document, text: &str) -> StorageResult<()> {
    if text.is_empty() {
        return Ok(());
    }
    let metadata = serde_json::to_vec(document)?;
    if text.len() > MAX_TEXT_BYTES || metadata.len() > MAX_META_BYTES {
        return Err(StorageError::Invalid("search document exceeds byte limit"));
    }
    output.write_all(&(metadata.len() as u32).to_le_bytes())?;
    output.write_all(&(text.len() as u32).to_le_bytes())?;
    let mut checksum = Sha256::new();
    checksum.update(&metadata);
    checksum.update(text.as_bytes());
    output.write_all(&checksum.finalize())?;
    output.write_all(&metadata)?;
    output.write_all(text.as_bytes())?;
    Ok(())
}

#[derive(PartialEq, Eq)]
struct Line {
    row: u32,
    text: String,
}

fn lines(frame: &TerminalFrameDiff) -> Vec<Line> {
    let mut result = Vec::new();
    let mut text = String::new();
    let mut start_row = 0;
    for row in &frame.rows {
        if text.is_empty() {
            start_row = row.index;
        }
        text.push_str(&row.text);
        if !row.wrapped {
            result.push(Line {
                row: start_row,
                text: std::mem::take(&mut text),
            });
        }
    }
    if !text.is_empty() {
        result.push(Line {
            row: start_row,
            text,
        });
    }
    for placement in &frame.sized_text {
        result.push(Line {
            row: placement.row,
            text: placement.text.clone(),
        });
    }
    result
}

fn index_screen(
    output: &mut impl Write,
    frame: &TerminalFrameDiff,
    offset_micros: u64,
    hostname: &Option<String>,
    previous: &mut Vec<Line>,
) -> StorageResult<()> {
    let next = lines(frame);
    for (index, line) in next.iter().enumerate() {
        if previous.get(index) == Some(line) {
            continue;
        }
        write_document(
            output,
            &Document {
                offset_micros,
                kind: SearchKind::Screen,
                hostname: hostname.clone(),
                row: Some(line.row),
            },
            &line.text,
        )?;
    }
    *previous = next;
    Ok(())
}

fn build(
    path: &Path,
    metadata: &RecordingMetadata,
    cancelled: &mut impl FnMut() -> bool,
) -> StorageResult<()> {
    let source = FileStamp::read(&path.join("records.bin"))?;
    let reader = ContainerReader::open(path)?;
    if reader.metadata != *metadata {
        return Err(StorageError::Invalid(
            "recording identity changed during search indexing",
        ));
    }
    let mut output = tempfile::NamedTempFile::new_in(path)?;
    output.write_all(MAGIC)?;
    let mut replay = ScreenReplay::default();
    let mut previous = Vec::new();
    let mut hostname = metadata.hostname.clone();
    // HookTimeline supports 64 simultaneously known contexts. Retaining only
    // recent starts bounds memory; an evicted start may yield a duplicate finish
    // hit, never a lost command. FIFO keeps rebuilt byte cursors deterministic.
    let mut starts: VecDeque<(String, String)> = VecDeque::new();
    reader.scan(&mut *cancelled, |located| {
        match &located.record {
            StoredRecord::Visual { sample, .. } => {
                replay.apply((**sample).clone())?;
                index_screen(
                    &mut output,
                    replay
                        .screen()
                        .ok_or(StorageError::Invalid("missing indexed screen"))?,
                    sample.offset_micros,
                    &hostname,
                    &mut previous,
                )?;
            }
            StoredRecord::Semantic(event) => {
                if (event.kind == SemanticKind::ContextChanged || event.hostname.is_some())
                    && hostname != event.hostname
                {
                    hostname = event.hostname.clone();
                    previous.clear();
                    if let Some(screen) = replay.screen() {
                        // The last retained screen is also the screen seek will
                        // return at this context event. No new text is invented.
                        index_screen(
                            &mut output,
                            screen,
                            event.offset_micros,
                            &hostname,
                            &mut previous,
                        )?;
                    }
                }
                let started = event.kind == SemanticKind::CommandStarted;
                let orphan_finish = event.kind == SemanticKind::CommandFinished
                    && !starts.iter().any(|(context, id)| {
                        context == &event.context_id && Some(id) == event.command_id.as_ref()
                    });
                if (started || orphan_finish)
                    && let Some(text) = &event.command
                {
                    write_document(
                        &mut output,
                        &Document {
                            offset_micros: event.offset_micros,
                            kind: SearchKind::Command,
                            hostname: event.hostname.clone(),
                            row: None,
                        },
                        text,
                    )?;
                }
                if started && let Some(id) = &event.command_id {
                    starts.retain(|(context, _)| context != &event.context_id);
                    if starts.len() == 64 {
                        starts.pop_front();
                    }
                    starts.push_back((event.context_id.clone(), id.clone()));
                }
            }
            StoredRecord::Finished(_) => {}
        }
        Ok(())
    })?;
    if cancelled() {
        return Err(StorageError::Cancelled);
    }
    if source != FileStamp::read(&path.join("records.bin"))? {
        return Err(StorageError::Invalid(
            "recording changed during search indexing",
        ));
    }
    output.as_file().sync_all()?;
    output
        .persist(path.join("search.index"))
        .map_err(|error| error.error)?;
    let manifest = Manifest {
        schema_version: 2,
        metadata: metadata_fingerprint(metadata)?,
        source,
        index: FileStamp::read(&path.join("search.index"))?,
    };
    let bytes = serde_json::to_vec(&manifest)?;
    let mut info = tempfile::NamedTempFile::new_in(path)?;
    info.write_all(&Sha256::digest(&bytes))?;
    info.write_all(&bytes)?;
    info.as_file().sync_all()?;
    if cancelled() {
        return Err(StorageError::Cancelled);
    }
    info.persist(path.join("search.info"))
        .map_err(|error| error.error)?;
    super::assets::sync_directory(path)?;
    Ok(())
}

fn read_document(file: &mut File, remaining: u64) -> StorageResult<(Document, String, u64)> {
    let mut header = [0; 40];
    file.read_exact(&mut header)?;
    let meta_bytes = u32::from_le_bytes(header[..4].try_into().unwrap()) as usize;
    let text_bytes = u32::from_le_bytes(header[4..8].try_into().unwrap()) as usize;
    let total = 40 + meta_bytes as u64 + text_bytes as u64;
    if meta_bytes > MAX_META_BYTES || text_bytes > MAX_TEXT_BYTES || total > remaining {
        return Err(StorageError::Invalid("invalid search document length"));
    }
    let mut metadata = vec![0; meta_bytes];
    let mut text = vec![0; text_bytes];
    file.read_exact(&mut metadata)?;
    file.read_exact(&mut text)?;
    let mut checksum = Sha256::new();
    checksum.update(&metadata);
    checksum.update(&text);
    if checksum.finalize().as_slice() != &header[8..] {
        return Err(StorageError::Invalid("search document checksum mismatch"));
    }
    let document: Document = serde_json::from_slice(&metadata)?;
    if document.kind == SearchKind::All
        || document.row.is_some_and(|row| row >= 4096)
        || document
            .hostname
            .as_ref()
            .is_some_and(|host| host.len() > 64 * 1024 || host.contains('\0'))
    {
        return Err(StorageError::Invalid("invalid search document"));
    }
    let text = String::from_utf8(text).map_err(|_| StorageError::Invalid("invalid search text"))?;
    Ok((document, text, total))
}

/// Preserve the original spelling even when Unicode lowercasing changes byte
/// lengths (for example İ). The snippet is bounded independently of line size.
fn preview(text: &str, folded_match: usize) -> String {
    let mut folded_bytes = 0;
    let mut original_char: usize = 0;
    for ch in text.chars() {
        if folded_bytes >= folded_match {
            break;
        }
        folded_bytes += ch.to_lowercase().map(char::len_utf8).sum::<usize>();
        original_char += 1;
    }
    let start = original_char.saturating_sub(60);
    let body: String = text.chars().skip(start).take(240).collect();
    let prefix = if start > 0 { "…" } else { "" };
    let suffix = if text.chars().nth(start + 240).is_some() {
        "…"
    } else {
        ""
    };
    format!("{prefix}{body}{suffix}")
}

pub(super) fn page(
    request: &SearchRequest,
    metadata: &RecordingMetadata,
    mut cancelled: impl FnMut() -> bool,
) -> StorageResult<SearchPage> {
    if request.query.len() > 1024
        || request.query.contains('\0')
        || request
            .hostname
            .as_ref()
            .is_some_and(|host| host.len() > 64 * 1024 || host.contains('\0'))
        || !(1..=100).contains(&request.limit)
    {
        return Err(StorageError::Invalid("invalid search query or page limit"));
    }
    let path = Path::new(&request.bundle_path);
    if !current(path, metadata).unwrap_or(false) {
        build(path, metadata, &mut cancelled)?;
    }
    if cancelled() {
        return Err(StorageError::Cancelled);
    }
    let mut file = open_regular_file(&path.join("search.index"))?;
    let length = file.metadata()?.len();
    let mut magic = [0; 8];
    file.read_exact(&mut magic)?;
    if &magic != MAGIC {
        return Err(StorageError::Invalid("invalid search index header"));
    }
    let mut cursor = if request.cursor == 0 {
        8
    } else {
        request.cursor
    };
    if cursor < 8 || cursor > length {
        return Err(StorageError::Invalid("invalid search cursor"));
    }
    file.seek(SeekFrom::Start(cursor))?;
    let needle = request.query.trim().to_lowercase();
    let host = request
        .hostname
        .as_ref()
        .map(|value| value.trim().to_lowercase());
    let mut hits = Vec::new();
    let mut scanned_bytes = 0;
    let mut response_bytes = 0;
    let mut documents = 0;
    while cursor < length
        && hits.len() < request.limit
        && scanned_bytes < PAGE_SCAN_BYTES
        && documents < PAGE_SCAN_DOCUMENTS
        && response_bytes < 1024 * 1024
    {
        if cancelled() {
            return Err(StorageError::Cancelled);
        }
        let (document, text, bytes) = read_document(&mut file, length - cursor)?;
        cursor += bytes;
        scanned_bytes += bytes;
        documents += 1;
        if request.kind != SearchKind::All && request.kind != document.kind {
            continue;
        }
        if host.as_ref().is_some_and(|host| {
            !host.is_empty()
                && !document
                    .hostname
                    .as_ref()
                    .is_some_and(|name| name.to_lowercase().contains(host))
        }) {
            continue;
        }
        if let Some(position) = text.to_lowercase().find(&needle) {
            let preview = preview(&text, position);
            response_bytes += preview.len() + document.hostname.as_ref().map_or(0, String::len);
            hits.push(Hit { document, preview });
        }
    }
    if cancelled() {
        return Err(StorageError::Cancelled);
    }
    Ok(SearchPage {
        hits,
        next_cursor: (cursor < length).then_some(cursor),
        scanned_bytes,
        total_bytes: length,
    })
}
