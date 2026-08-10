//! File transfer support for terminal-based file transfer protocols
//!
//! Provides types and a manager for tracking file downloads and uploads
//! initiated through terminal escape sequences (e.g., OSC 1337 for iTerm2
//! inline images, OSC 52 clipboard, or custom file transfer protocols).
//!
//! The `FileTransferManager` maintains active transfers in progress and a
//! bounded ring buffer of completed transfers for later retrieval.

use std::collections::HashMap;

use crate::terminal::unix_millis;

/// Unique file transfer identifier
pub type TransferId = u64;

/// Direction of a file transfer
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferDirection {
    /// Terminal is receiving data (e.g., file download, inline image)
    Download,
    /// Terminal is sending data (e.g., file upload)
    Upload,
}

/// Current status of a file transfer
#[derive(Clone, PartialEq, Eq)]
pub enum TransferStatus {
    /// Transfer has been created but no data received yet
    Pending,
    /// Transfer is actively receiving/sending data
    InProgress {
        /// Number of bytes transferred so far
        bytes_transferred: usize,
        /// Total expected size, if known
        total_bytes: Option<usize>,
    },
    /// Transfer completed successfully
    Completed,
    /// Transfer failed with an error message
    Failed(String),
    /// Transfer was cancelled by the user or system
    Cancelled,
}

impl std::fmt::Debug for TransferStatus {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Pending => formatter.write_str("Pending"),
            Self::InProgress {
                bytes_transferred,
                total_bytes,
            } => formatter
                .debug_struct("InProgress")
                .field("bytes_transferred", bytes_transferred)
                .field("total_bytes", total_bytes)
                .finish(),
            Self::Completed => formatter.write_str("Completed"),
            Self::Failed(_) => formatter.write_str("Failed"),
            Self::Cancelled => formatter.write_str("Cancelled"),
        }
    }
}

/// A single file transfer operation
#[derive(Clone)]
pub struct FileTransfer {
    /// Unique transfer identifier
    pub id: TransferId,
    /// Whether this is a download or upload
    pub direction: TransferDirection,
    /// Name of the file being transferred
    pub filename: String,
    /// Current transfer status
    pub status: TransferStatus,
    /// Accumulated file data
    pub data: Vec<u8>,
    /// Protocol-specific parameters (e.g., content-type, encoding)
    pub params: HashMap<String, String>,
    /// Timestamp when the transfer was started (unix millis)
    pub started_at: u64,
    /// Timestamp when the transfer completed/failed/cancelled (unix millis)
    pub completed_at: Option<u64>,
}

impl std::fmt::Debug for FileTransfer {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FileTransfer")
            .field("id", &self.id)
            .field("direction", &self.direction)
            .field("status", &self.status)
            .field("data_bytes", &self.data.len())
            .field("param_count", &self.params.len())
            .finish()
    }
}

/// Manages active and completed file transfers
///
/// Active transfers are tracked by ID in a `HashMap`. Completed transfers
/// are stored in a bounded ring buffer (oldest evicted when full) so that
/// frontends can poll for finished results without unbounded memory growth.
pub struct FileTransferManager {
    /// Currently in-progress transfers
    active_transfers: HashMap<TransferId, FileTransfer>,
    /// Ring buffer of completed/failed/cancelled transfers
    completed_transfers: Vec<FileTransfer>,
    /// Maximum number of completed transfers to retain
    max_completed: usize,
    /// Maximum number of simultaneous transfers to retain
    max_active: usize,
    /// Next transfer ID to assign
    next_id: TransferId,
    /// Maximum allowed transfer size in bytes (default 50 MB)
    ///
    /// This is also the aggregate byte budget across active and completed
    /// transfers. A PTY must not multiply the per-transfer limit by opening
    /// many transfers or by filling the completed-transfer ring.
    max_transfer_size: usize,
}

impl std::fmt::Debug for FileTransferManager {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FileTransferManager")
            .field("active_count", &self.active_transfers.len())
            .field("completed_count", &self.completed_transfers.len())
            .field("retained_data_bytes", &self.retained_data_bytes())
            .field("max_completed", &self.max_completed)
            .field("max_active", &self.max_active)
            .field("max_transfer_size", &self.max_transfer_size)
            .finish()
    }
}

/// Default maximum transfer size: 50 MB
const DEFAULT_MAX_TRANSFER_SIZE: usize = 50 * 1024 * 1024;

/// Default maximum number of completed transfers to retain
const DEFAULT_MAX_COMPLETED: usize = 32;

/// Default maximum number of simultaneous transfers to retain.
const DEFAULT_MAX_ACTIVE: usize = 32;

impl Default for FileTransferManager {
    fn default() -> Self {
        Self {
            active_transfers: HashMap::new(),
            completed_transfers: Vec::new(),
            max_completed: DEFAULT_MAX_COMPLETED,
            max_active: DEFAULT_MAX_ACTIVE,
            next_id: 1,
            max_transfer_size: DEFAULT_MAX_TRANSFER_SIZE,
        }
    }
}

impl FileTransferManager {
    /// Create a new `FileTransferManager` with default settings
    pub fn new() -> Self {
        Self::default()
    }

    /// Start a new download transfer
    ///
    /// Returns the assigned `TransferId` for tracking the transfer.
    pub fn start_download(
        &mut self,
        filename: String,
        total_bytes: Option<usize>,
        params: HashMap<String, String>,
    ) -> TransferId {
        self.make_active_slot();
        let id = self.next_id;
        self.next_id += 1;

        let status = if total_bytes.is_some() {
            TransferStatus::InProgress {
                bytes_transferred: 0,
                total_bytes,
            }
        } else {
            TransferStatus::Pending
        };

        let transfer = FileTransfer {
            id,
            direction: TransferDirection::Download,
            filename,
            status,
            data: Vec::new(),
            params,
            started_at: unix_millis(),
            completed_at: None,
        };

        self.active_transfers.insert(id, transfer);
        id
    }

    /// Append data to an active transfer
    ///
    /// Returns `Ok(())` on success, or `Err(String)` if the transfer is not found,
    /// not in a valid state for appending, or would exceed the maximum transfer size.
    pub fn append_data(&mut self, id: TransferId, data: &[u8]) -> Result<(), String> {
        let current_size = self
            .active_transfers
            .get(&id)
            .ok_or_else(|| format!("transfer {id} not found"))?
            .data
            .len();

        let new_size = current_size.saturating_add(data.len());
        if new_size > self.max_transfer_size {
            self.fail_and_discard_transfer_data(
                id,
                format!(
                    "transfer exceeds maximum size of {} bytes",
                    self.max_transfer_size
                ),
            );
            return Err(format!(
                "transfer {id} exceeds maximum size of {} bytes",
                self.max_transfer_size
            ));
        }

        self.evict_completed_until_fits(data.len());
        if self.retained_data_bytes().saturating_add(data.len()) > self.max_transfer_size {
            self.fail_and_discard_transfer_data(
                id,
                format!(
                    "aggregate transfer data exceeds maximum size of {} bytes",
                    self.max_transfer_size
                ),
            );
            return Err(format!(
                "transfer {id} exceeds aggregate retained-data budget of {} bytes",
                self.max_transfer_size
            ));
        }

        let transfer = self
            .active_transfers
            .get_mut(&id)
            .expect("active transfer was validated above");

        transfer.data.extend_from_slice(data);

        // Update status to InProgress with current byte count
        let bytes_transferred = transfer.data.len();
        let total_bytes = match &transfer.status {
            TransferStatus::InProgress { total_bytes, .. } => *total_bytes,
            TransferStatus::Pending => None,
            _ => {
                return Err(format!(
                    "transfer {id} is not in a valid state for appending data"
                ));
            }
        };

        transfer.status = TransferStatus::InProgress {
            bytes_transferred,
            total_bytes,
        };

        Ok(())
    }

    /// Mark a transfer as completed
    ///
    /// Moves the transfer from active to the completed ring buffer.
    /// Returns `Err(String)` if the transfer is not found.
    pub fn complete_transfer(&mut self, id: TransferId) -> Result<(), String> {
        let mut transfer = self
            .active_transfers
            .remove(&id)
            .ok_or_else(|| format!("transfer {id} not found"))?;

        transfer.status = TransferStatus::Completed;
        transfer.completed_at = Some(unix_millis());
        self.push_completed(transfer);
        Ok(())
    }

    /// Mark a transfer as failed with an error message
    ///
    /// Moves the transfer from active to the completed ring buffer.
    /// Returns `Err(String)` if the transfer is not found.
    pub fn fail_transfer(&mut self, id: TransferId, reason: String) -> Result<(), String> {
        let mut transfer = self
            .active_transfers
            .remove(&id)
            .ok_or_else(|| format!("transfer {id} not found"))?;

        transfer.status = TransferStatus::Failed(reason);
        transfer.completed_at = Some(unix_millis());
        self.push_completed(transfer);
        Ok(())
    }

    /// Cancel a transfer
    ///
    /// Moves the transfer from active to the completed ring buffer.
    /// Returns `Err(String)` if the transfer is not found.
    pub fn cancel_transfer(&mut self, id: TransferId) -> Result<(), String> {
        let mut transfer = self
            .active_transfers
            .remove(&id)
            .ok_or_else(|| format!("transfer {id} not found"))?;

        transfer.status = TransferStatus::Cancelled;
        transfer.completed_at = Some(unix_millis());
        self.push_completed(transfer);
        Ok(())
    }

    /// Get a reference to an active transfer by ID
    pub fn get_transfer(&self, id: TransferId) -> Option<&FileTransfer> {
        self.active_transfers.get(&id)
    }

    /// Get a list of all active transfers
    pub fn active_transfers(&self) -> Vec<&FileTransfer> {
        self.active_transfers.values().collect()
    }

    /// Get a reference to the completed transfers ring buffer
    pub fn completed_transfers(&self) -> &[FileTransfer] {
        &self.completed_transfers
    }

    /// Take a completed transfer by ID, removing it from the completed buffer
    ///
    /// Returns `None` if no completed transfer with the given ID exists.
    pub fn take_completed_transfer(&mut self, id: TransferId) -> Option<FileTransfer> {
        if let Some(pos) = self.completed_transfers.iter().position(|t| t.id == id) {
            Some(self.completed_transfers.remove(pos))
        } else {
            None
        }
    }

    /// Get the current maximum transfer size in bytes
    pub fn max_transfer_size(&self) -> usize {
        self.max_transfer_size
    }

    /// Set the maximum transfer size in bytes
    pub fn set_max_transfer_size(&mut self, size: usize) {
        self.max_transfer_size = size;
        self.enforce_retained_budget();
    }

    /// Push a transfer onto the completed ring buffer, evicting the oldest if
    /// either the item count or aggregate retained-data budget is full.
    fn push_completed(&mut self, mut transfer: FileTransfer) {
        if self.completed_transfers.len() >= self.max_completed {
            self.completed_transfers.remove(0);
        }
        self.evict_completed_until_fits(transfer.data.len());
        if self
            .retained_data_bytes()
            .saturating_add(transfer.data.len())
            > self.max_transfer_size
        {
            // Keep failure/completion metadata available to the host, but never
            // retain bytes beyond the configured aggregate budget.
            transfer.data.clear();
        }
        self.completed_transfers.push(transfer);
    }

    fn retained_data_bytes(&self) -> usize {
        self.active_transfers
            .values()
            .chain(self.completed_transfers.iter())
            .fold(0usize, |total, transfer| {
                total.saturating_add(transfer.data.len())
            })
    }

    fn evict_completed_until_fits(&mut self, additional_bytes: usize) {
        while !self.completed_transfers.is_empty()
            && self.retained_data_bytes().saturating_add(additional_bytes) > self.max_transfer_size
        {
            self.completed_transfers.remove(0);
        }
    }

    fn make_active_slot(&mut self) {
        if self.active_transfers.len() < self.max_active {
            return;
        }
        let Some(oldest_id) = self.active_transfers.keys().copied().min() else {
            return;
        };
        self.fail_and_discard_transfer_data(
            oldest_id,
            format!(
                "active transfer capacity of {} was exceeded",
                self.max_active
            ),
        );
    }

    fn fail_and_discard_transfer_data(&mut self, id: TransferId, reason: String) {
        let Some(mut transfer) = self.active_transfers.remove(&id) else {
            return;
        };
        transfer.data.clear();
        transfer.status = TransferStatus::Failed(reason);
        transfer.completed_at = Some(unix_millis());
        self.push_completed(transfer);
    }

    fn enforce_retained_budget(&mut self) {
        self.evict_completed_until_fits(0);
        while self.retained_data_bytes() > self.max_transfer_size {
            let Some(oldest_id) = self.active_transfers.keys().copied().min() else {
                break;
            };
            self.fail_and_discard_transfer_data(
                oldest_id,
                format!(
                    "aggregate transfer data exceeds maximum size of {} bytes",
                    self.max_transfer_size
                ),
            );
        }
    }
}

use crate::terminal::{Terminal, MAX_RESPONSE_BUFFER_BYTES};

impl Terminal {
    // === File Transfer Methods ===

    /// Get a list of all active file transfers
    pub fn get_active_transfers(&self) -> Vec<FileTransfer> {
        self.file_transfer_manager
            .active_transfers()
            .into_iter()
            .cloned()
            .collect()
    }

    /// Get a list of all completed file transfers
    pub fn get_completed_transfers(&self) -> Vec<FileTransfer> {
        self.file_transfer_manager.completed_transfers().to_vec()
    }

    /// Get a specific transfer by ID (active or completed)
    pub fn get_transfer(&self, id: TransferId) -> Option<FileTransfer> {
        self.file_transfer_manager
            .get_transfer(id)
            .cloned()
            .or_else(|| {
                self.file_transfer_manager
                    .completed_transfers()
                    .iter()
                    .find(|t| t.id == id)
                    .cloned()
            })
    }

    /// Take a completed transfer by ID, removing it from the manager
    pub fn take_completed_transfer(&mut self, id: TransferId) -> Option<FileTransfer> {
        self.file_transfer_manager.take_completed_transfer(id)
    }

    /// Cancel an active file transfer
    pub fn cancel_file_transfer(&mut self, id: TransferId) -> bool {
        self.file_transfer_manager.cancel_transfer(id).is_ok()
    }

    /// Send data for an active upload
    ///
    /// Writes the iTerm2-compatible upload response to the response buffer:
    /// `ok\n` + base64(data) + `\n\n`. Data that exceeds either the
    /// configured file-transfer limit or the terminal response budget is
    /// rejected with the protocol's Ctrl-C cancellation response.
    pub fn send_upload_data(&mut self, data: &[u8]) {
        use base64::Engine;

        const RESPONSE_OVERHEAD_BYTES: usize = b"ok\n\n\n".len();
        if data.len() > self.file_transfer_manager.max_transfer_size() {
            self.cancel_upload();
            return;
        }
        let Some(response_len) = base64::encoded_len(data.len(), true)
            .and_then(|encoded_len| encoded_len.checked_add(RESPONSE_OVERHEAD_BYTES))
        else {
            self.cancel_upload();
            return;
        };
        if response_len > MAX_RESPONSE_BUFFER_BYTES {
            self.cancel_upload();
            return;
        }

        let mut response = String::with_capacity(response_len);
        response.push_str("ok\n");
        base64::engine::general_purpose::STANDARD.encode_string(data, &mut response);
        response.push_str("\n\n");
        debug_assert_eq!(response.len(), response_len);
        self.push_response(response.as_bytes());
    }

    /// Cancel the current upload
    ///
    /// Writes Ctrl-C (0x03) to the response buffer to signal upload cancellation
    pub fn cancel_upload(&mut self) {
        self.push_response(&[0x03]);
    }

    /// Set the maximum allowed transfer size in bytes
    pub fn set_max_transfer_size(&mut self, size: usize) {
        self.file_transfer_manager.set_max_transfer_size(size);
    }

    /// Get the maximum allowed transfer size in bytes
    pub fn get_max_transfer_size(&self) -> usize {
        self.file_transfer_manager.max_transfer_size()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upload_data_respects_transfer_limit_and_recovers_after_cancel() {
        let mut term = Terminal::new(80, 24);
        term.set_max_transfer_size(3);

        term.send_upload_data(b"four");
        assert_eq!(term.drain_responses(), &[0x03]);

        term.send_upload_data(b"abc");
        assert_eq!(term.drain_responses(), b"ok\nYWJj\n\n");
    }

    #[test]
    fn upload_response_larger_than_terminal_budget_is_cancelled_before_encoding() {
        const RESPONSE_OVERHEAD_BYTES: usize = b"ok\n\n\n".len();
        let first_oversized_raw_len =
            ((MAX_RESPONSE_BUFFER_BYTES - RESPONSE_OVERHEAD_BYTES) / 4) * 3 + 1;
        assert!(
            base64::encoded_len(first_oversized_raw_len, true).unwrap() + RESPONSE_OVERHEAD_BYTES
                > MAX_RESPONSE_BUFFER_BYTES
        );
        let data = vec![0u8; first_oversized_raw_len];
        let mut term = Terminal::new(80, 24);
        term.set_max_transfer_size(usize::MAX);

        term.send_upload_data(&data);

        assert_eq!(term.drain_responses(), &[0x03]);
        assert_eq!(term.response_buffer_overflow_count(), 0);
    }

    #[test]
    fn test_start_download() {
        let mut mgr = FileTransferManager::new();
        let id = mgr.start_download("test.txt".into(), Some(1024), HashMap::new());

        assert_eq!(id, 1);
        let transfer = mgr.get_transfer(id).unwrap();
        assert_eq!(transfer.filename, "test.txt");
        assert_eq!(transfer.direction, TransferDirection::Download);
        assert_eq!(
            transfer.status,
            TransferStatus::InProgress {
                bytes_transferred: 0,
                total_bytes: Some(1024),
            }
        );
        assert!(transfer.data.is_empty());
        assert!(transfer.started_at > 0);
        assert!(transfer.completed_at.is_none());

        // Second download gets incremented ID
        let id2 = mgr.start_download("other.bin".into(), None, HashMap::new());
        assert_eq!(id2, 2);
        let transfer2 = mgr.get_transfer(id2).unwrap();
        assert_eq!(transfer2.status, TransferStatus::Pending);
    }

    #[test]
    fn test_append_data_and_complete() {
        let mut mgr = FileTransferManager::new();
        let id = mgr.start_download("data.bin".into(), Some(10), HashMap::new());

        mgr.append_data(id, b"hello").unwrap();
        let transfer = mgr.get_transfer(id).unwrap();
        assert_eq!(transfer.data, b"hello");
        assert_eq!(
            transfer.status,
            TransferStatus::InProgress {
                bytes_transferred: 5,
                total_bytes: Some(10),
            }
        );

        mgr.append_data(id, b"world").unwrap();
        let transfer = mgr.get_transfer(id).unwrap();
        assert_eq!(transfer.data, b"helloworld");
        assert_eq!(
            transfer.status,
            TransferStatus::InProgress {
                bytes_transferred: 10,
                total_bytes: Some(10),
            }
        );

        mgr.complete_transfer(id).unwrap();
        assert!(mgr.get_transfer(id).is_none());
        assert_eq!(mgr.completed_transfers().len(), 1);
        let completed = &mgr.completed_transfers()[0];
        assert_eq!(completed.id, id);
        assert_eq!(completed.status, TransferStatus::Completed);
        assert!(completed.completed_at.is_some());
        assert_eq!(completed.data, b"helloworld");
    }

    #[test]
    fn test_size_limit_enforcement() {
        let mut mgr = FileTransferManager::new();
        mgr.set_max_transfer_size(10);
        assert_eq!(mgr.max_transfer_size(), 10);

        let id = mgr.start_download("big.bin".into(), None, HashMap::new());

        // This fits
        mgr.append_data(id, b"12345").unwrap();

        // This exceeds the limit (5 + 6 = 11 > 10)
        let result = mgr.append_data(id, b"123456");
        assert!(result.is_err());

        // Transfer should have been moved to completed as failed
        assert!(mgr.get_transfer(id).is_none());
        assert_eq!(mgr.completed_transfers().len(), 1);
        match &mgr.completed_transfers()[0].status {
            TransferStatus::Failed(msg) => {
                assert!(msg.contains("maximum size"));
            }
            other => panic!("expected Failed status, got {other:?}"),
        }
    }

    #[test]
    fn test_cancel_transfer() {
        let mut mgr = FileTransferManager::new();
        let id = mgr.start_download("cancel_me.txt".into(), None, HashMap::new());

        mgr.append_data(id, b"partial").unwrap();
        mgr.cancel_transfer(id).unwrap();

        assert!(mgr.get_transfer(id).is_none());
        assert_eq!(mgr.completed_transfers().len(), 1);
        let transfer = &mgr.completed_transfers()[0];
        assert_eq!(transfer.status, TransferStatus::Cancelled);
        assert!(transfer.completed_at.is_some());
        assert_eq!(transfer.data, b"partial");
    }

    #[test]
    fn test_take_completed_transfer() {
        let mut mgr = FileTransferManager::new();
        let id = mgr.start_download("take_me.txt".into(), None, HashMap::new());
        mgr.complete_transfer(id).unwrap();

        assert_eq!(mgr.completed_transfers().len(), 1);

        let taken = mgr.take_completed_transfer(id);
        assert!(taken.is_some());
        let taken = taken.unwrap();
        assert_eq!(taken.id, id);
        assert_eq!(taken.filename, "take_me.txt");

        // Should be gone now
        assert!(mgr.completed_transfers().is_empty());
        assert!(mgr.take_completed_transfer(id).is_none());
    }

    #[test]
    fn test_ring_buffer_eviction() {
        let mut mgr = FileTransferManager::new();
        // Set small max_completed to test eviction
        mgr.max_completed = 3;

        // Create and complete 5 transfers
        let mut ids = Vec::new();
        for i in 0..5 {
            let id = mgr.start_download(format!("file_{i}.txt"), None, HashMap::new());
            mgr.complete_transfer(id).unwrap();
            ids.push(id);
        }

        // Only the last 3 should remain
        let completed = mgr.completed_transfers();
        assert_eq!(completed.len(), 3);
        assert_eq!(completed[0].id, ids[2]); // file_2.txt
        assert_eq!(completed[1].id, ids[3]); // file_3.txt
        assert_eq!(completed[2].id, ids[4]); // file_4.txt

        // First two should be evicted
        assert!(mgr.take_completed_transfer(ids[0]).is_none());
        assert!(mgr.take_completed_transfer(ids[1]).is_none());
    }

    #[test]
    fn completed_transfers_share_one_aggregate_byte_budget() {
        let mut mgr = FileTransferManager::new();
        mgr.set_max_transfer_size(10);

        for index in 0..4 {
            let id = mgr.start_download(format!("file_{index}.bin"), None, HashMap::new());
            mgr.append_data(id, b"123456").unwrap();
            mgr.complete_transfer(id).unwrap();
            assert!(mgr.retained_data_bytes() <= 10);
        }

        assert_eq!(mgr.completed_transfers().len(), 1);
        assert_eq!(mgr.completed_transfers()[0].data, b"123456");
    }

    #[test]
    fn active_transfers_cannot_multiply_the_byte_budget() {
        let mut mgr = FileTransferManager::new();
        mgr.set_max_transfer_size(10);
        let first = mgr.start_download("first.bin".into(), None, HashMap::new());
        let second = mgr.start_download("second.bin".into(), None, HashMap::new());

        mgr.append_data(first, b"123456").unwrap();
        let result = mgr.append_data(second, b"abcdef");

        assert!(result.is_err());
        assert!(mgr.get_transfer(second).is_none());
        assert!(mgr.retained_data_bytes() <= 10);
        assert!(matches!(
            mgr.completed_transfers()
                .last()
                .map(|transfer| &transfer.status),
            Some(TransferStatus::Failed(_))
        ));
    }

    #[test]
    fn simultaneous_transfer_metadata_is_bounded() {
        let mut mgr = FileTransferManager::new();

        for index in 0..(DEFAULT_MAX_ACTIVE + 5) {
            mgr.start_download(format!("file_{index}.bin"), None, HashMap::new());
        }

        assert_eq!(mgr.active_transfers().len(), DEFAULT_MAX_ACTIVE);
        assert!(mgr.completed_transfers().len() <= DEFAULT_MAX_COMPLETED);
        assert!(mgr.completed_transfers().iter().all(|transfer| {
            matches!(transfer.status, TransferStatus::Failed(_)) && transfer.data.is_empty()
        }));
    }

    #[test]
    fn test_fail_transfer() {
        let mut mgr = FileTransferManager::new();
        let id = mgr.start_download("fail_me.txt".into(), Some(100), HashMap::new());

        mgr.append_data(id, b"some data").unwrap();
        mgr.fail_transfer(id, "network error".into()).unwrap();

        assert!(mgr.get_transfer(id).is_none());
        assert_eq!(mgr.completed_transfers().len(), 1);
        let transfer = &mgr.completed_transfers()[0];
        assert_eq!(
            transfer.status,
            TransferStatus::Failed("network error".into())
        );
        assert!(transfer.completed_at.is_some());
        assert_eq!(transfer.data, b"some data");

        // Failing a non-existent transfer should error
        let result = mgr.fail_transfer(999, "not found".into());
        assert!(result.is_err());
    }

    #[test]
    fn test_active_transfers_list() {
        let mut mgr = FileTransferManager::new();

        // No active transfers initially
        assert!(mgr.active_transfers().is_empty());

        let id1 = mgr.start_download("a.txt".into(), None, HashMap::new());
        let id2 = mgr.start_download("b.txt".into(), None, HashMap::new());
        let id3 = mgr.start_download("c.txt".into(), None, HashMap::new());

        let active = mgr.active_transfers();
        assert_eq!(active.len(), 3);

        // Complete one - should reduce active count
        mgr.complete_transfer(id2).unwrap();
        let active = mgr.active_transfers();
        assert_eq!(active.len(), 2);

        let active_ids: Vec<TransferId> = active.iter().map(|t| t.id).collect();
        assert!(active_ids.contains(&id1));
        assert!(!active_ids.contains(&id2));
        assert!(active_ids.contains(&id3));
    }

    #[test]
    fn test_append_to_nonexistent_transfer() {
        let mut mgr = FileTransferManager::new();
        let result = mgr.append_data(999, b"data");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    #[test]
    fn test_complete_nonexistent_transfer() {
        let mut mgr = FileTransferManager::new();
        let result = mgr.complete_transfer(999);
        assert!(result.is_err());
    }

    #[test]
    fn test_cancel_nonexistent_transfer() {
        let mut mgr = FileTransferManager::new();
        let result = mgr.cancel_transfer(999);
        assert!(result.is_err());
    }

    #[test]
    fn test_params_preserved() {
        let mut mgr = FileTransferManager::new();
        let mut params = HashMap::new();
        params.insert("content-type".into(), "image/png".into());
        params.insert("encoding".into(), "base64".into());

        let id = mgr.start_download("image.png".into(), Some(4096), params.clone());
        let transfer = mgr.get_transfer(id).unwrap();
        assert_eq!(transfer.params, params);

        mgr.complete_transfer(id).unwrap();
        let completed = &mgr.completed_transfers()[0];
        assert_eq!(completed.params, params);
    }

    #[test]
    fn debug_output_redacts_file_transfer_content() {
        let filename = "filename-secret-canary";
        let payload = b"payload-secret-canary";
        let failure = "failure-secret-canary";
        let mut params = HashMap::new();
        params.insert(
            "param-name-secret-canary".to_string(),
            "param-value-secret-canary".to_string(),
        );
        let mut manager = FileTransferManager::new();
        let id = manager.start_download(filename.to_string(), None, params);
        manager.append_data(id, payload).unwrap();
        manager.fail_transfer(id, failure.to_string()).unwrap();

        let transfer = manager.completed_transfers().last().unwrap();
        let transfer_debug = format!("{transfer:?}");
        let manager_debug = format!("{manager:?}");
        let status_debug = format!("{:?}", transfer.status);
        let payload_debug = format!("{:?}", payload.as_slice());
        for secret in [
            filename,
            failure,
            "param-name-secret-canary",
            "param-value-secret-canary",
            payload_debug.as_str(),
        ] {
            assert!(!transfer_debug.contains(secret), "Debug leaked {secret}");
            assert!(!manager_debug.contains(secret), "Debug leaked {secret}");
            assert!(!status_debug.contains(secret), "Debug leaked {secret}");
        }
        assert!(transfer_debug.contains(&format!("data_bytes: {}", payload.len())));
        assert!(manager_debug.contains("completed_count: 1"));
        assert_eq!(status_debug, "Failed");
    }
}
