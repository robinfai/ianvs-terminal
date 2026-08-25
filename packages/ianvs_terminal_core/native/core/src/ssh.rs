use crate::model::{
    TerminalProfileConnection, TerminalSshAuthMethod, TerminalSshHostKeyPolicy,
    TerminalSshJumpProfile, TerminalSshPortForward, TerminalSshPortForwardKind,
};
use anyhow::{Context, Result, anyhow, bail};
use futures_util::{StreamExt, future::BoxFuture, stream::FuturesUnordered};
use parking_lot::Mutex;
use portable_pty::{Child, ChildKiller, ExitStatus, MasterPty, PtySize};
use russh::client;
use russh::client::KeyboardInteractiveAuthResponse;
use russh::keys::PrivateKey;
#[cfg(unix)]
use russh::keys::agent::{AgentIdentity, client::AgentClient};
use russh::keys::key::PrivateKeyWithHashAlg;
use russh::{Channel, ChannelMsg, ChannelOpenFailure, Disconnect};
use russh_sftp::client::{
    Config as SftpConfig, RawSftpSession, SftpSession, error::Error as SftpError,
};
use russh_sftp::protocol::{
    FileAttributes as SftpFileAttributes, FileType as SftpFileType, Packet as SftpPacket,
    StatusCode as SftpStatusCode,
};
use std::collections::{HashMap, VecDeque};
use std::fmt;
use std::fs;
use std::future::Future;
use std::io::{Error as IoError, ErrorKind, Read, Result as IoResult, Write};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex as StdMutex, mpsc as std_mpsc};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
#[cfg(unix)]
use tokio::net::UnixStream;
use tokio::net::{TcpListener, TcpStream};
use tokio::process::{Child as TokioChild, ChildStdin, ChildStdout, Command};
use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore, mpsc, oneshot};
use url::Url;

const SOCKS_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
const FORWARD_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const X11_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
const SSH_NETWORK_TEARDOWN_TIMEOUT: Duration = Duration::from_secs(2);
const SFTP_DIRECTORY_REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const SFTP_FILE_OPERATION_REQUEST_TIMEOUT: Duration = Duration::from_secs(30 * 60);
const SFTP_FILE_CANCELLATION_CLEANUP_TIMEOUT: Duration = Duration::from_secs(15);
const MAX_CONCURRENT_SFTP_REQUESTS: usize = 16;
const MAX_SFTP_DIRECTORY_ENTRIES: usize = 10_000;
const MAX_SFTP_ENTRY_NAME_BYTES: usize = 1024;
const MAX_SFTP_INBOUND_PACKET_BYTES: u32 = 256 * 1024;
const SFTP_LIMITED_READ_CHUNK_BYTES: usize = 8 * 1024;
// Keep the directory payload comfortably below the 16 MiB session-response
// limit. This is enforced while entries are collected so JSON escaping cannot
// amplify a remote filename into one large, late allocation.
const MAX_SFTP_DIRECTORY_WIRE_BYTES: usize = 8 * 1024 * 1024;
const MAX_SFTP_FILE_TRANSFER_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const SFTP_FILE_COPY_BUFFER_BYTES: usize = 64 * 1024;
// Match OpenSSH's default LoginGraceTime so keyboard-interactive prompts do
// not expire locally before a server using its default authentication window.
const SSH_AUTH_INTERACTION_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_PENDING_FORWARD_HANDSHAKES: usize = 64;
const MAX_ACTIVE_FORWARD_RELAYS: usize = 64;
const MAX_PENDING_X11_CONNECTIONS: usize = 32;
const MAX_X11_SETUP_BYTES: usize = 4 * 1024;
const X11_AUTH_PROTOCOL: &[u8] = b"MIT-MAGIC-COOKIE-1";
const SSH_SHELL_PROBE_TIMEOUT: Duration = Duration::from_secs(5);
const SSH_SHELL_CLEANUP_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_SSH_SHELL_PROBE_BYTES: usize = 4096;
const REMOTE_SHELL_MARKER: &str = "__IANVS_REMOTE_SHELL__";
const REMOTE_CAPABILITY_MARKER: &str = "__IANVS_REMOTE_CAPABILITIES__1";

pub struct SshRuntime {
    pub master: Box<dyn MasterPty + Send>,
    pub reader: Box<dyn Read + Send>,
    pub writer: Box<dyn Write + Send>,
    pub child: Box<dyn Child + Send + Sync>,
    pub auth: SshAuthClient,
    pub sftp: SshSftpClient,
}

#[derive(Clone, Debug)]
pub struct SshSftpClient {
    sender: mpsc::UnboundedSender<SshCommand>,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct SftpDirectoryListing {
    pub path: String,
    pub entries: Vec<SftpDirectoryEntry>,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct SftpDirectoryEntry {
    pub name: String,
    pub kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub modified_at_epoch_seconds: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub permissions: Option<String>,
}

pub type SftpDirectoryResult = std::result::Result<SftpDirectoryListing, String>;
pub type SftpOperationResult = std::result::Result<(), String>;

#[derive(Clone, Debug)]
pub enum SftpOperation {
    DownloadFile {
        remote_path: String,
        local_path: String,
    },
    UploadFile {
        local_path: String,
        remote_path: String,
    },
    CreateDirectory {
        path: String,
    },
    DeleteEntry {
        path: String,
        is_directory: bool,
    },
}

impl SshSftpClient {
    pub fn start_list_directory(
        &self,
        path: String,
    ) -> std::result::Result<oneshot::Receiver<SftpDirectoryResult>, String> {
        let (response, receiver) = oneshot::channel();
        self.sender
            .send(SshCommand::ListDirectory { path, response })
            .map_err(|_| "SSH session is closed".to_string())?;
        Ok(receiver)
    }

    pub fn start_operation(
        &self,
        operation: SftpOperation,
    ) -> std::result::Result<oneshot::Receiver<SftpOperationResult>, String> {
        let (response, receiver) = oneshot::channel();
        self.sender
            .send(SshCommand::SftpOperation {
                operation,
                response,
            })
            .map_err(|_| "SSH session is closed".to_string())?;
        Ok(receiver)
    }
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct SshAuthPromptField {
    pub prompt: String,
    pub echo: bool,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct SshAuthPrompt {
    pub challenge_id: u64,
    pub host: String,
    pub user: String,
    pub name: String,
    pub instructions: String,
    pub prompts: Vec<SshAuthPromptField>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SshHostKeyPromptReason {
    Unknown,
    Changed,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct SshHostKeyPrompt {
    pub challenge_id: u64,
    pub host: String,
    pub port: u16,
    pub reason: SshHostKeyPromptReason,
    pub algorithm: String,
    pub fingerprint: String,
}

struct PendingAuthResponse {
    prompt_count: usize,
    sender: oneshot::Sender<Option<Vec<String>>>,
}

struct PendingHostKeyResponse {
    sender: oneshot::Sender<bool>,
}

#[derive(Default)]
struct SshAuthBroker {
    next_challenge_id: AtomicU64,
    prompts: StdMutex<VecDeque<SshAuthPrompt>>,
    responses: StdMutex<HashMap<u64, PendingAuthResponse>>,
    next_host_key_challenge_id: AtomicU64,
    host_key_prompts: StdMutex<VecDeque<SshHostKeyPrompt>>,
    host_key_responses: StdMutex<HashMap<u64, PendingHostKeyResponse>>,
    pending_interactions: AtomicUsize,
    interaction_changed: Notify,
}

struct SshInteractionGuard {
    broker: Arc<SshAuthBroker>,
}

impl Drop for SshInteractionGuard {
    fn drop(&mut self) {
        self.broker
            .pending_interactions
            .fetch_sub(1, Ordering::AcqRel);
        self.broker.interaction_changed.notify_waiters();
    }
}

#[derive(Clone, Default)]
pub struct SshAuthClient {
    broker: Arc<SshAuthBroker>,
}

impl fmt::Debug for SshAuthClient {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SshAuthClient")
            .finish_non_exhaustive()
    }
}

impl SshAuthClient {
    fn begin_interaction(&self) -> SshInteractionGuard {
        self.broker
            .pending_interactions
            .fetch_add(1, Ordering::AcqRel);
        self.broker.interaction_changed.notify_waiters();
        SshInteractionGuard {
            broker: Arc::clone(&self.broker),
        }
    }

    fn has_pending_interaction(&self) -> bool {
        self.broker.pending_interactions.load(Ordering::Acquire) != 0
    }

    async fn wait_until_interactions_complete(&self) {
        loop {
            let notified = self.broker.interaction_changed.notified();
            if !self.has_pending_interaction() {
                return;
            }
            notified.await;
        }
    }

    async fn wait_until_interaction_begins(&self) {
        loop {
            let notified = self.broker.interaction_changed.notified();
            if self.has_pending_interaction() {
                return;
            }
            notified.await;
        }
    }

    pub fn take_prompts(&self) -> Vec<SshAuthPrompt> {
        let Ok(mut prompts) = self.broker.prompts.lock() else {
            return Vec::new();
        };
        prompts.drain(..).collect()
    }

    pub fn respond(&self, challenge_id: u64, responses: Vec<String>) -> bool {
        let pending = self
            .broker
            .responses
            .lock()
            .ok()
            .and_then(|mut pending| pending.remove(&challenge_id));
        let Some(pending) = pending else {
            return false;
        };
        if responses.len() != pending.prompt_count {
            let _ = pending.sender.send(None);
            return false;
        }
        pending.sender.send(Some(responses)).is_ok()
    }

    pub fn take_host_key_prompts(&self) -> Vec<SshHostKeyPrompt> {
        let Ok(mut prompts) = self.broker.host_key_prompts.lock() else {
            return Vec::new();
        };
        prompts.drain(..).collect()
    }

    pub fn respond_host_key(&self, challenge_id: u64, accept: bool) -> bool {
        self.broker
            .host_key_responses
            .lock()
            .ok()
            .and_then(|mut pending| pending.remove(&challenge_id))
            .is_some_and(|pending| pending.sender.send(accept).is_ok())
    }

    pub fn cancel(&self, challenge_id: u64) -> bool {
        self.broker
            .responses
            .lock()
            .ok()
            .and_then(|mut pending| pending.remove(&challenge_id))
            .is_some_and(|pending| pending.sender.send(None).is_ok())
    }

    fn cancel_all(&self) {
        if let Ok(mut pending) = self.broker.responses.lock() {
            for (_, pending) in pending.drain() {
                let _ = pending.sender.send(None);
            }
        }
        if let Ok(mut prompts) = self.broker.prompts.lock() {
            prompts.clear();
        }
        if let Ok(mut pending) = self.broker.host_key_responses.lock() {
            for (_, pending) in pending.drain() {
                let _ = pending.sender.send(false);
            }
        }
        if let Ok(mut prompts) = self.broker.host_key_prompts.lock() {
            prompts.clear();
        }
    }

    async fn request(
        &self,
        connection: &TerminalProfileConnection,
        name: String,
        instructions: String,
        prompts: Vec<SshAuthPromptField>,
    ) -> Result<Vec<String>> {
        let _interaction = self.begin_interaction();
        let challenge_id = self
            .broker
            .next_challenge_id
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1);
        let (sender, receiver) = oneshot::channel();
        self.broker
            .responses
            .lock()
            .map_err(|_| anyhow!("SSH authentication response queue is poisoned"))?
            .insert(
                challenge_id,
                PendingAuthResponse {
                    prompt_count: prompts.len(),
                    sender,
                },
            );
        self.broker
            .prompts
            .lock()
            .map_err(|_| anyhow!("SSH authentication prompt queue is poisoned"))?
            .push_back(SshAuthPrompt {
                challenge_id,
                host: connection.host.clone(),
                user: connection.user.clone(),
                name,
                instructions,
                prompts,
            });
        match tokio::time::timeout(SSH_AUTH_INTERACTION_TIMEOUT, receiver).await {
            Ok(Ok(Some(responses))) => Ok(responses),
            Ok(Ok(None)) => bail!("SSH authentication challenge was cancelled"),
            Ok(Err(_)) => bail!("SSH authentication challenge response channel closed"),
            Err(_) => {
                if let Ok(mut pending) = self.broker.responses.lock() {
                    pending.remove(&challenge_id);
                }
                bail!("SSH authentication challenge timed out")
            }
        }
    }

    async fn request_host_key(
        &self,
        host: String,
        port: u16,
        reason: SshHostKeyPromptReason,
        server_public_key: &russh::keys::ssh_key::PublicKey,
    ) -> Result<bool> {
        let _interaction = self.begin_interaction();
        let challenge_id = self
            .broker
            .next_host_key_challenge_id
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1);
        let (sender, receiver) = oneshot::channel();
        self.broker
            .host_key_responses
            .lock()
            .map_err(|_| anyhow!("SSH host-key response queue is poisoned"))?
            .insert(challenge_id, PendingHostKeyResponse { sender });
        self.broker
            .host_key_prompts
            .lock()
            .map_err(|_| anyhow!("SSH host-key prompt queue is poisoned"))?
            .push_back(SshHostKeyPrompt {
                challenge_id,
                host,
                port,
                reason,
                algorithm: server_public_key.algorithm().to_string(),
                fingerprint: server_public_key
                    .fingerprint(Default::default())
                    .to_string(),
            });
        match tokio::time::timeout(Duration::from_secs(300), receiver).await {
            Ok(Ok(accept)) => Ok(accept),
            Ok(Err(_)) => bail!("SSH host-key confirmation response channel closed"),
            Err(_) => {
                if let Ok(mut pending) = self.broker.host_key_responses.lock() {
                    pending.remove(&challenge_id);
                }
                bail!("SSH host-key confirmation timed out")
            }
        }
    }
}

#[derive(Debug)]
enum SshCommand {
    Data(Vec<u8>),
    Resize(PtySize),
    ListDirectory {
        path: String,
        response: oneshot::Sender<SftpDirectoryResult>,
    },
    SftpOperation {
        operation: SftpOperation,
        response: oneshot::Sender<SftpOperationResult>,
    },
    Close,
}

#[derive(Clone, Default)]
struct SshCancellation {
    cancelled: Arc<AtomicBool>,
    notify: Arc<Notify>,
    proxy_processes: Arc<StdMutex<Vec<std::sync::Weak<tokio::sync::Mutex<TokioChild>>>>>,
}

impl SshCancellation {
    fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.notify.notify_waiters();
    }

    async fn cancelled(&self) {
        loop {
            let notified = self.notify.notified();
            if self.cancelled.load(Ordering::Acquire) {
                return;
            }
            notified.await;
        }
    }

    fn register_proxy_process(&self, process: &Arc<tokio::sync::Mutex<TokioChild>>) {
        if let Ok(mut processes) = self.proxy_processes.lock() {
            processes.retain(|process| process.strong_count() != 0);
            processes.push(Arc::downgrade(process));
        }
    }

    async fn terminate_proxy_processes(&self) {
        let processes = self
            .proxy_processes
            .lock()
            .map(|mut processes| {
                let live: Vec<Arc<tokio::sync::Mutex<TokioChild>>> = processes
                    .iter()
                    .filter_map(std::sync::Weak::upgrade)
                    .collect();
                processes.clear();
                live
            })
            .unwrap_or_default();
        for process in processes {
            let mut process = process.lock().await;
            let _ = process.start_kill();
            let _ = process.wait().await;
        }
    }
}

async fn shutdown_ssh_resources(cancellation: &SshCancellation, forward_runtime: &ForwardRuntime) {
    cancellation.cancel();
    cancellation.terminate_proxy_processes().await;
    forward_runtime.shutdown().await;
}

async fn await_bounded_ssh_teardown<F>(teardown: F, timeout: Duration) -> bool
where
    F: Future<Output = ()>,
{
    tokio::time::timeout(timeout, teardown).await.is_ok()
}

struct SshReader {
    receiver: std_mpsc::Receiver<Vec<u8>>,
    pending: Vec<u8>,
    offset: usize,
}

impl Read for SshReader {
    fn read(&mut self, target: &mut [u8]) -> IoResult<usize> {
        if target.is_empty() {
            return Ok(0);
        }
        while self.offset >= self.pending.len() {
            match self.receiver.recv() {
                Ok(bytes) if bytes.is_empty() => continue,
                Ok(bytes) => {
                    self.pending = bytes;
                    self.offset = 0;
                }
                Err(_) => return Ok(0),
            }
        }
        let remaining = &self.pending[self.offset..];
        let count = remaining.len().min(target.len());
        target[..count].copy_from_slice(&remaining[..count]);
        self.offset += count;
        Ok(count)
    }
}

#[derive(Clone)]
struct SshWriter {
    sender: mpsc::UnboundedSender<SshCommand>,
}

impl Write for SshWriter {
    fn write(&mut self, bytes: &[u8]) -> IoResult<usize> {
        self.sender
            .send(SshCommand::Data(bytes.to_vec()))
            .map_err(|_| IoError::new(ErrorKind::BrokenPipe, "SSH session is closed"))?;
        Ok(bytes.len())
    }

    fn flush(&mut self) -> IoResult<()> {
        Ok(())
    }
}

struct SshMaster {
    sender: mpsc::UnboundedSender<SshCommand>,
    reader: Mutex<Option<std_mpsc::Receiver<Vec<u8>>>>,
    writer_taken: AtomicBool,
    size: Mutex<PtySize>,
}

impl MasterPty for SshMaster {
    fn resize(&self, size: PtySize) -> Result<()> {
        self.sender
            .send(SshCommand::Resize(size))
            .map_err(|_| IoError::new(ErrorKind::BrokenPipe, "SSH session is closed"))?;
        *self.size.lock() = size;
        Ok(())
    }

    fn get_size(&self) -> Result<PtySize> {
        Ok(*self.size.lock())
    }

    fn try_clone_reader(&self) -> Result<Box<dyn Read + Send>> {
        let receiver = self
            .reader
            .lock()
            .take()
            .ok_or_else(|| anyhow!("SSH reader has already been taken"))?;
        Ok(Box::new(SshReader {
            receiver,
            pending: Vec::new(),
            offset: 0,
        }))
    }

    fn take_writer(&self) -> Result<Box<dyn Write + Send>> {
        if self.writer_taken.swap(true, Ordering::AcqRel) {
            bail!("SSH writer has already been taken");
        }
        Ok(Box::new(SshWriter {
            sender: self.sender.clone(),
        }))
    }

    #[cfg(unix)]
    fn process_group_leader(&self) -> Option<libc::pid_t> {
        None
    }

    #[cfg(unix)]
    fn as_raw_fd(&self) -> Option<std::os::fd::RawFd> {
        None
    }

    #[cfg(unix)]
    fn tty_name(&self) -> Option<PathBuf> {
        None
    }
}

type SharedExitStatus = Arc<(StdMutex<Option<ExitStatus>>, Condvar)>;

struct SshChild {
    sender: mpsc::UnboundedSender<SshCommand>,
    status: SharedExitStatus,
    auth: SshAuthClient,
    cancellation: SshCancellation,
}

impl fmt::Debug for SshChild {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.debug_struct("SshChild").finish_non_exhaustive()
    }
}

impl ChildKiller for SshChild {
    fn kill(&mut self) -> IoResult<()> {
        self.auth.cancel_all();
        self.cancellation.cancel();
        let _ = self.sender.send(SshCommand::Close);
        Ok(())
    }

    fn clone_killer(&self) -> Box<dyn ChildKiller + Send + Sync> {
        Box::new(Self {
            sender: self.sender.clone(),
            status: Arc::clone(&self.status),
            auth: self.auth.clone(),
            cancellation: self.cancellation.clone(),
        })
    }
}

impl Child for SshChild {
    fn try_wait(&mut self) -> IoResult<Option<ExitStatus>> {
        Ok(self.status.0.lock().map_err(poisoned_lock)?.clone())
    }

    fn wait(&mut self) -> IoResult<ExitStatus> {
        let mut guard = self.status.0.lock().map_err(poisoned_lock)?;
        while guard.is_none() {
            guard = self.status.1.wait(guard).map_err(poisoned_lock)?;
        }
        Ok(guard
            .clone()
            .unwrap_or_else(|| ExitStatus::with_exit_code(255)))
    }

    fn process_id(&self) -> Option<u32> {
        None
    }

    #[cfg(windows)]
    fn as_raw_handle(&self) -> Option<std::os::windows::io::RawHandle> {
        None
    }
}

fn poisoned_lock<T>(_: std::sync::PoisonError<T>) -> IoError {
    IoError::other("SSH session status lock is poisoned")
}

#[derive(Clone)]
struct SshClientHandler {
    host: String,
    port: u16,
    policy: TerminalSshHostKeyPolicy,
    known_hosts_file: Option<PathBuf>,
    interactions: SshAuthClient,
    remote_forwards: Vec<TerminalSshPortForward>,
    agent_socket: Option<PathBuf>,
    x11_proxy: Option<X11ProxyConfig>,
    forward_runtime: ForwardRuntime,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum X11Target {
    Tcp(String, u16),
    #[cfg(unix)]
    Unix(PathBuf),
}

#[derive(Clone)]
struct X11ProxyConfig {
    target: X11Target,
    fake_cookie: [u8; 16],
    real_cookie: [u8; 16],
    connections: Arc<Semaphore>,
}

#[derive(Clone)]
struct ForwardRuntime {
    inner: Arc<ForwardRuntimeInner>,
}

struct ForwardRuntimeInner {
    cancellation: SshCancellation,
    handshakes: Arc<Semaphore>,
    relays: Arc<Semaphore>,
    state: Mutex<ForwardTaskState>,
}

#[derive(Default)]
struct ForwardTaskState {
    closed: bool,
    next_id: u64,
    tasks: HashMap<u64, tokio::task::JoinHandle<()>>,
}

impl ForwardRuntime {
    fn new(cancellation: SshCancellation) -> Self {
        Self::with_limits(
            cancellation,
            MAX_PENDING_FORWARD_HANDSHAKES,
            MAX_ACTIVE_FORWARD_RELAYS,
        )
    }

    fn with_limits(
        cancellation: SshCancellation,
        handshake_limit: usize,
        relay_limit: usize,
    ) -> Self {
        Self {
            inner: Arc::new(ForwardRuntimeInner {
                cancellation,
                handshakes: Arc::new(Semaphore::new(handshake_limit)),
                relays: Arc::new(Semaphore::new(relay_limit)),
                state: Mutex::new(ForwardTaskState::default()),
            }),
        }
    }

    fn try_handshake_permit(&self) -> Option<OwnedSemaphorePermit> {
        Arc::clone(&self.inner.handshakes).try_acquire_owned().ok()
    }

    fn try_relay_permit(&self) -> Option<OwnedSemaphorePermit> {
        Arc::clone(&self.inner.relays).try_acquire_owned().ok()
    }

    fn spawn_tracked<F>(&self, task: F) -> bool
    where
        F: Future<Output = ()> + Send + 'static,
    {
        let mut state = self.inner.state.lock();
        if state.closed {
            return false;
        }
        state.tasks.retain(|_, task| !task.is_finished());
        state.next_id = state.next_id.saturating_add(1);
        let id = state.next_id;
        state.tasks.insert(id, tokio::spawn(task));
        true
    }

    fn spawn_relay<A, B>(&self, left: A, right: B, permit: OwnedSemaphorePermit) -> bool
    where
        A: AsyncRead + AsyncWrite + Unpin + Send + 'static,
        B: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let cancellation = self.inner.cancellation.clone();
        self.spawn_tracked(async move {
            let _permit = permit;
            relay_streams_until_cancelled(left, right, cancellation).await;
        })
    }

    async fn shutdown(&self) {
        let tasks = {
            let mut state = self.inner.state.lock();
            if state.closed {
                Vec::new()
            } else {
                state.closed = true;
                self.inner.handshakes.close();
                self.inner.relays.close();
                state
                    .tasks
                    .drain()
                    .map(|(_, task)| task)
                    .collect::<Vec<_>>()
            }
        };
        for task in &tasks {
            task.abort();
        }
        for task in tasks {
            let _ = task.await;
        }
    }

    #[cfg(test)]
    fn available_handshake_permits(&self) -> usize {
        self.inner.handshakes.available_permits()
    }

    #[cfg(test)]
    fn available_relay_permits(&self) -> usize {
        self.inner.relays.available_permits()
    }

    #[cfg(test)]
    fn tracked_task_count(&self) -> usize {
        self.inner.state.lock().tasks.len()
    }
}

impl Drop for ForwardRuntimeInner {
    fn drop(&mut self) {
        let state = self.state.get_mut();
        state.closed = true;
        self.handshakes.close();
        self.relays.close();
        for (_, task) in state.tasks.drain() {
            task.abort();
        }
    }
}

impl client::Handler for SshClientHandler {
    type Error = anyhow::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &russh::keys::ssh_key::PublicKey,
    ) -> Result<bool, Self::Error> {
        if self.policy == TerminalSshHostKeyPolicy::Insecure {
            return Ok(true);
        }
        let check = if let Some(path) = &self.known_hosts_file {
            russh::keys::known_hosts::check_known_hosts_path(
                &self.host,
                self.port,
                server_public_key,
                path,
            )
        } else {
            russh::keys::check_known_hosts(&self.host, self.port, server_public_key)
        };
        match check {
            Ok(true) => Ok(true),
            Ok(false) if self.policy == TerminalSshHostKeyPolicy::AcceptNew => {
                self.learn_host_key(server_public_key)?;
                Ok(true)
            }
            Ok(false) => {
                let accepted = self
                    .interactions
                    .request_host_key(
                        self.host.clone(),
                        self.port,
                        SshHostKeyPromptReason::Unknown,
                        server_public_key,
                    )
                    .await?;
                if accepted {
                    self.learn_host_key(server_public_key)?;
                }
                Ok(accepted)
            }
            Err(russh::keys::Error::KeyChanged { line }) => {
                let accepted = self
                    .interactions
                    .request_host_key(
                        self.host.clone(),
                        self.port,
                        SshHostKeyPromptReason::Changed,
                        server_public_key,
                    )
                    .await?;
                if accepted {
                    self.replace_changed_host_key(line, server_public_key)?;
                }
                Ok(accepted)
            }
            Err(error) => Err(error.into()),
        }
    }

    fn server_channel_open_forwarded_tcpip(
        &mut self,
        channel: Channel<client::Msg>,
        connected_address: &str,
        connected_port: u32,
        _originator_address: &str,
        _originator_port: u32,
        reply: client::ChannelOpenHandle,
        _session: &mut client::Session,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send {
        let target = self
            .remote_forwards
            .iter()
            .find(|forward| {
                forward.kind == TerminalSshPortForwardKind::Remote
                    && forward.bind_host == connected_address
                    && u32::from(forward.bind_port) == connected_port
            })
            .map(|forward| (forward.target_host.clone(), forward.target_port));
        let forward_runtime = self.forward_runtime.clone();
        async move {
            let Some((host, port)) = target else {
                return Ok(());
            };
            let Some(permit) = forward_runtime.try_relay_permit() else {
                reply.reject(ChannelOpenFailure::ResourceShortage).await;
                return Ok(());
            };
            if let Ok(Ok(stream)) = tokio::time::timeout(
                FORWARD_CONNECT_TIMEOUT,
                TcpStream::connect((host.as_str(), port)),
            )
            .await
            {
                reply.accept().await;
                let _ = forward_runtime.spawn_relay(channel.into_stream(), stream, permit);
            } else {
                reply.reject(ChannelOpenFailure::ConnectFailed).await;
            }
            Ok(())
        }
    }

    fn server_channel_open_agent_forward(
        &mut self,
        channel: Channel<client::Msg>,
        reply: client::ChannelOpenHandle,
        _session: &mut client::Session,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send {
        let agent_socket = self.agent_socket.clone();
        let forward_runtime = self.forward_runtime.clone();
        async move {
            #[cfg(unix)]
            {
                let Some(agent_socket) = agent_socket else {
                    reply
                        .reject(ChannelOpenFailure::AdministrativelyProhibited)
                        .await;
                    return Ok(());
                };
                let Some(permit) = forward_runtime.try_relay_permit() else {
                    reply.reject(ChannelOpenFailure::ResourceShortage).await;
                    return Ok(());
                };
                if let Ok(Ok(stream)) =
                    tokio::time::timeout(FORWARD_CONNECT_TIMEOUT, UnixStream::connect(agent_socket))
                        .await
                {
                    reply.accept().await;
                    let _ = forward_runtime.spawn_relay(channel.into_stream(), stream, permit);
                } else {
                    reply.reject(ChannelOpenFailure::ConnectFailed).await;
                }
            }
            #[cfg(not(unix))]
            {
                let _ = (agent_socket, channel, forward_runtime);
                reply
                    .reject(ChannelOpenFailure::AdministrativelyProhibited)
                    .await;
            }
            Ok(())
        }
    }

    fn server_channel_open_x11(
        &mut self,
        channel: Channel<client::Msg>,
        _originator_address: &str,
        _originator_port: u32,
        reply: client::ChannelOpenHandle,
        _session: &mut client::Session,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send {
        let proxy = self.x11_proxy.clone();
        let forward_runtime = self.forward_runtime.clone();
        async move {
            let Some(proxy) = proxy else {
                reply
                    .reject(ChannelOpenFailure::AdministrativelyProhibited)
                    .await;
                return Ok(());
            };
            let Ok(permit) = Arc::clone(&proxy.connections).try_acquire_owned() else {
                reply.reject(ChannelOpenFailure::ResourceShortage).await;
                return Ok(());
            };
            match proxy.target.clone() {
                X11Target::Tcp(host, port) => {
                    if let Ok(Ok(stream)) = tokio::time::timeout(
                        FORWARD_CONNECT_TIMEOUT,
                        TcpStream::connect((host.as_str(), port)),
                    )
                    .await
                    {
                        reply.accept().await;
                        let _ = forward_runtime.spawn_tracked(proxy_x11_streams(
                            channel.into_stream(),
                            stream,
                            proxy,
                            permit,
                        ));
                    } else {
                        reply.reject(ChannelOpenFailure::ConnectFailed).await;
                    }
                }
                #[cfg(unix)]
                X11Target::Unix(path) => {
                    if let Ok(Ok(stream)) =
                        tokio::time::timeout(FORWARD_CONNECT_TIMEOUT, UnixStream::connect(path))
                            .await
                    {
                        reply.accept().await;
                        let _ = forward_runtime.spawn_tracked(proxy_x11_streams(
                            channel.into_stream(),
                            stream,
                            proxy,
                            permit,
                        ));
                    } else {
                        reply.reject(ChannelOpenFailure::ConnectFailed).await;
                    }
                }
            }
            Ok(())
        }
    }
}

impl SshClientHandler {
    fn known_hosts_path(&self) -> Result<PathBuf> {
        if let Some(path) = &self.known_hosts_file {
            return Ok(path.clone());
        }
        let home = std::env::var_os("HOME")
            .or_else(|| std::env::var_os("USERPROFILE"))
            .map(PathBuf::from)
            .ok_or_else(|| anyhow!("home directory is unavailable for known_hosts"))?;
        Ok(home.join(".ssh").join("known_hosts"))
    }

    fn learn_host_key(&self, server_public_key: &russh::keys::ssh_key::PublicKey) -> Result<()> {
        if let Some(path) = &self.known_hosts_file {
            russh::keys::known_hosts::learn_known_hosts_path(
                &self.host,
                self.port,
                server_public_key,
                path,
            )?;
        } else {
            russh::keys::known_hosts::learn_known_hosts(&self.host, self.port, server_public_key)?;
        }
        Ok(())
    }

    fn replace_changed_host_key(
        &self,
        line: usize,
        server_public_key: &russh::keys::ssh_key::PublicKey,
    ) -> Result<()> {
        let path = self.known_hosts_path()?;
        let original =
            fs::read(&path).with_context(|| format!("could not read {}", path.display()))?;
        let text = std::str::from_utf8(&original)
            .with_context(|| format!("{} is not UTF-8", path.display()))?;
        let mut lines = text.lines().map(str::to_string).collect::<Vec<_>>();
        let index = line
            .checked_sub(1)
            .filter(|index| *index < lines.len())
            .ok_or_else(|| anyhow!("stored SSH host-key line changed before confirmation"))?;
        let host_pattern = if self.port == 22 {
            self.host.clone()
        } else {
            format!("[{}]:{}", self.host, self.port)
        };
        lines[index] = format!("{host_pattern} {}", server_public_key.to_openssh()?);
        let mut replacement = lines.join("\n");
        if text.ends_with('\n') {
            replacement.push('\n');
        }
        if fs::read(&path)? != original {
            bail!("known_hosts changed while SSH host-key confirmation was open");
        }
        let parent = path
            .parent()
            .ok_or_else(|| anyhow!("known_hosts has no parent directory"))?;
        let mut staging = tempfile::NamedTempFile::new_in(parent)?;
        staging.write_all(replacement.as_bytes())?;
        staging.as_file().sync_all()?;
        staging.persist(&path).map_err(|error| error.error)?;
        Ok(())
    }
}

async fn relay_streams_until_cancelled<A, B>(mut left: A, mut right: B, cancel: SshCancellation)
where
    A: AsyncRead + AsyncWrite + Unpin,
    B: AsyncRead + AsyncWrite + Unpin,
{
    tokio::select! {
        biased;
        _ = cancel.cancelled() => {}
        _ = tokio::io::copy_bidirectional(&mut left, &mut right) => {}
    }
    let _ = left.shutdown().await;
    let _ = right.shutdown().await;
}

async fn proxy_x11_streams<A, B>(
    mut remote: A,
    mut local: B,
    proxy: X11ProxyConfig,
    _permit: tokio::sync::OwnedSemaphorePermit,
) where
    A: AsyncRead + AsyncWrite + Unpin,
    B: AsyncRead + AsyncWrite + Unpin,
{
    let handshake = rewrite_x11_setup_with_timeout(
        &mut remote,
        &mut local,
        &proxy.fake_cookie,
        &proxy.real_cookie,
        X11_HANDSHAKE_TIMEOUT,
    );
    if handshake.await.is_ok() {
        let _ = tokio::io::copy_bidirectional(&mut remote, &mut local).await;
    }
    let _ = remote.shutdown().await;
    let _ = local.shutdown().await;
}

async fn rewrite_x11_setup_with_timeout<R, W>(
    remote: &mut R,
    local: &mut W,
    fake_cookie: &[u8; 16],
    real_cookie: &[u8; 16],
    timeout: Duration,
) -> Result<()>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    tokio::time::timeout(
        timeout,
        rewrite_x11_setup(remote, local, fake_cookie, real_cookie),
    )
    .await
    .map_err(|_| anyhow!("X11 setup authentication timed out"))?
}

async fn rewrite_x11_setup<R, W>(
    remote: &mut R,
    local: &mut W,
    fake_cookie: &[u8; 16],
    real_cookie: &[u8; 16],
) -> Result<()>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut header = [0_u8; 12];
    remote.read_exact(&mut header).await?;
    let read_u16 = match header[0] {
        b'l' => u16::from_le_bytes,
        b'B' => u16::from_be_bytes,
        _ => bail!("invalid X11 setup byte order"),
    };
    if read_u16([header[2], header[3]]) != 11 {
        bail!("unsupported X11 protocol version");
    }
    let protocol_length = usize::from(read_u16([header[6], header[7]]));
    let cookie_length = usize::from(read_u16([header[8], header[9]]));
    let protocol_padded = padded_x11_length(protocol_length)?;
    let cookie_padded = padded_x11_length(cookie_length)?;
    if 12_usize
        .checked_add(protocol_padded)
        .and_then(|length| length.checked_add(cookie_padded))
        .is_none_or(|length| length > MAX_X11_SETUP_BYTES)
    {
        bail!("X11 setup authentication data is too large");
    }
    if protocol_length != X11_AUTH_PROTOCOL.len() || cookie_length != fake_cookie.len() {
        bail!("invalid X11 authentication lengths");
    }
    let mut authentication = vec![0_u8; protocol_padded + cookie_padded];
    remote.read_exact(&mut authentication).await?;
    if &authentication[..protocol_length] != X11_AUTH_PROTOCOL {
        bail!("unsupported X11 authentication protocol");
    }
    if &authentication[protocol_padded..protocol_padded + cookie_length] != fake_cookie {
        bail!("X11 authentication cookie mismatch");
    }

    local.write_all(&header).await?;
    local.write_all(X11_AUTH_PROTOCOL).await?;
    write_x11_padding(local, protocol_length).await?;
    local.write_all(real_cookie).await?;
    write_x11_padding(local, real_cookie.len()).await?;
    local.flush().await?;
    Ok(())
}

fn padded_x11_length(length: usize) -> Result<usize> {
    length
        .checked_add(3)
        .map(|length| length & !3)
        .ok_or_else(|| anyhow!("X11 setup authentication length overflow"))
}

async fn write_x11_padding<W>(target: &mut W, length: usize) -> IoResult<()>
where
    W: AsyncWrite + Unpin,
{
    const ZERO_PADDING: [u8; 3] = [0; 3];
    let padding = padded_x11_length(length)
        .map_err(IoError::other)?
        .saturating_sub(length);
    target.write_all(&ZERO_PADDING[..padding]).await
}

struct AcceptedLocalForward {
    stream: TcpStream,
    target_host: String,
    target_port: u16,
    socks5: bool,
}

struct ForwardListenerTasks(Vec<tokio::task::JoinHandle<()>>);

impl ForwardListenerTasks {
    fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    fn abort_all(&self) {
        for task in &self.0 {
            task.abort();
        }
    }
}

impl Drop for ForwardListenerTasks {
    fn drop(&mut self) {
        self.abort_all();
    }
}

pub fn spawn_ssh(
    connection: TerminalProfileConnection,
    rows: u16,
    cols: u16,
) -> Result<SshRuntime> {
    spawn_ssh_with_shell_integration(connection, rows, cols, false)
}

pub(crate) fn spawn_ssh_with_shell_integration(
    connection: TerminalProfileConnection,
    rows: u16,
    cols: u16,
    shell_integration_enabled: bool,
) -> Result<SshRuntime> {
    let auth = SshAuthClient::default();
    let cancellation = SshCancellation::default();
    let (command_sender, command_receiver) = mpsc::unbounded_channel();
    let (output_sender, output_receiver) = std_mpsc::channel();
    let status: SharedExitStatus = Arc::new((StdMutex::new(None), Condvar::new()));
    let initial_size = PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    };
    let master = Box::new(SshMaster {
        sender: command_sender.clone(),
        reader: Mutex::new(Some(output_receiver)),
        writer_taken: AtomicBool::new(false),
        size: Mutex::new(initial_size),
    });
    let reader = master.try_clone_reader()?;
    let writer = master.take_writer()?;
    let child = Box::new(SshChild {
        sender: command_sender.clone(),
        status: Arc::clone(&status),
        auth: auth.clone(),
        cancellation: cancellation.clone(),
    });

    let thread_auth = auth.clone();
    let thread_cancellation = cancellation;

    thread::Builder::new()
        .name(format!("ianvs-ssh-{}", connection.host))
        .spawn(move || {
            let result = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .worker_threads(2)
                .build()
                .context("could not initialize SSH async runtime")
                .and_then(|runtime| {
                    runtime.block_on(run_ssh_session(
                        connection,
                        initial_size,
                        shell_integration_enabled,
                        command_receiver,
                        output_sender.clone(),
                        thread_auth,
                        thread_cancellation,
                    ))
                });
            let exit_code = match result {
                Ok(code) => code,
                Err(error) => {
                    let message = format!("\r\nIanvs SSH: {error:#}\r\n");
                    let _ = output_sender.send(message.into_bytes());
                    255
                }
            };
            drop(output_sender);
            if let Ok(mut slot) = status.0.lock() {
                *slot = Some(ExitStatus::with_exit_code(exit_code));
                status.1.notify_all();
            }
        })
        .context("could not start SSH transport thread")?;

    Ok(SshRuntime {
        master,
        reader,
        writer,
        child,
        auth,
        sftp: SshSftpClient {
            sender: command_sender,
        },
    })
}

struct PreparedSshSession {
    session: client::Handle<SshClientHandler>,
    jump_sessions: Vec<client::Handle<SshClientHandler>>,
    forward_receiver: mpsc::Receiver<AcceptedLocalForward>,
    forward_listeners: ForwardListenerTasks,
    channel: Channel<client::Msg>,
    shell_integration: Option<RemoteShellIntegration>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RemoteShellKind {
    Sh,
    Bash,
    Zsh,
    Fish,
    Other,
}

#[derive(Debug, Eq, PartialEq)]
struct RemoteShellProbe {
    program: String,
    kind: RemoteShellKind,
    capabilities_available: bool,
}

#[derive(Debug)]
struct RemoteShellIntegration {
    directory: String,
    files: Vec<String>,
    launch_command: String,
}

async fn prepare_remote_shell_integration(
    session: &client::Handle<SshClientHandler>,
    cancellation: &SshCancellation,
) -> Result<Option<RemoteShellIntegration>> {
    let Some(probe) = probe_remote_shell(session, cancellation).await? else {
        return Ok(None);
    };
    if probe.kind == RemoteShellKind::Other || !probe.capabilities_available {
        return Ok(None);
    }

    let token = random_sftp_transfer_token()?;
    let directory = format!("/tmp/ianvs-terminal-shell-{token}");
    let files = remote_shell_integration_files(probe.kind);
    let sftp = open_sftp_session(session)
        .await
        .context("could not open SFTP for remote shell integration")?;
    sftp.create_dir(&directory)
        .await
        .context("could not create the remote shell integration directory")?;

    let mut uploaded_paths = Vec::with_capacity(files.len());
    let upload_result: Result<()> = async {
        for (name, contents) in files {
            let path = format!("{directory}/{name}");
            let mut remote = sftp
                .create(&path)
                .await
                .with_context(|| format!("could not create remote shell hook {name}"))?;
            uploaded_paths.push(path);
            remote
                .write_all(contents.as_bytes())
                .await
                .with_context(|| format!("could not write remote shell hook {name}"))?;
            remote
                .flush()
                .await
                .with_context(|| format!("could not flush remote shell hook {name}"))?;
            remote
                .close()
                .await
                .with_context(|| format!("could not close remote shell hook {name}"))?;
        }
        Ok(())
    }
    .await;
    if let Err(error) = upload_result {
        for path in uploaded_paths.iter().rev() {
            let _ = sftp.remove_file(path).await;
        }
        let _ = sftp.remove_dir(&directory).await;
        return Err(error);
    }

    Ok(Some(RemoteShellIntegration {
        launch_command: remote_shell_launch_command(probe.kind, &probe.program, &directory),
        directory,
        files: uploaded_paths,
    }))
}

async fn probe_remote_shell(
    session: &client::Handle<SshClientHandler>,
    cancellation: &SshCancellation,
) -> Result<Option<RemoteShellProbe>> {
    let output = run_remote_probe(
        session,
        r#"printf '__IANVS_REMOTE_SHELL__%s\n' "$SHELL""#,
        cancellation,
    )
    .await?;
    let Some(program) = parse_remote_shell_program(&output) else {
        return Ok(None);
    };
    let kind = remote_shell_kind(&program);
    let Some(capability_command) = remote_shell_capability_command(kind, &program) else {
        return Ok(Some(RemoteShellProbe {
            program,
            kind,
            capabilities_available: false,
        }));
    };
    let capability_output = run_remote_probe(session, &capability_command, cancellation)
        .await
        .unwrap_or_default();
    Ok(Some(RemoteShellProbe {
        program,
        kind,
        capabilities_available: capability_output
            .lines()
            .any(|line| line.trim() == REMOTE_CAPABILITY_MARKER),
    }))
}

async fn run_remote_probe(
    session: &client::Handle<SshClientHandler>,
    command: &str,
    cancellation: &SshCancellation,
) -> Result<String> {
    let probe = async {
        let channel = session
            .channel_open_session()
            .await
            .context("could not open remote shell probe channel")?;
        channel
            .exec(true, command)
            .await
            .context("remote shell probe was rejected")?;
        let mut stream = channel
            .into_stream()
            .take((MAX_SSH_SHELL_PROBE_BYTES + 1) as u64);
        let mut output = Vec::new();
        stream
            .read_to_end(&mut output)
            .await
            .context("could not read remote shell probe output")?;
        if output.len() > MAX_SSH_SHELL_PROBE_BYTES {
            bail!("remote shell probe output exceeded its byte limit");
        }
        String::from_utf8(output).context("remote shell probe output was not UTF-8")
    };
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => bail!("remote shell probe was cancelled"),
        result = tokio::time::timeout(SSH_SHELL_PROBE_TIMEOUT, probe) => {
            result.context("remote shell probe timed out")?
        }
    }
}

fn parse_remote_shell_program(output: &str) -> Option<String> {
    let program = output
        .lines()
        .filter_map(|line| line.trim().strip_prefix(REMOTE_SHELL_MARKER))
        .map(str::trim)
        .find(|value| !value.is_empty())?;
    if program.len() > 1024
        || !program.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'_' | b'.' | b'+' | b'-')
        })
    {
        return None;
    }
    Some(program.to_string())
}

fn remote_shell_kind(program: &str) -> RemoteShellKind {
    let name = program
        .rsplit('/')
        .next()
        .unwrap_or(program)
        .trim_start_matches('-');
    match name {
        "bash" => RemoteShellKind::Bash,
        "zsh" => RemoteShellKind::Zsh,
        "fish" => RemoteShellKind::Fish,
        "sh" | "dash" | "ash" | "ksh" | "mksh" => RemoteShellKind::Sh,
        _ => RemoteShellKind::Other,
    }
}

fn remote_shell_capability_command(kind: RemoteShellKind, program: &str) -> Option<String> {
    let program = shell_quote(program);
    match kind {
        RemoteShellKind::Zsh => Some(format!(
            "command -v od >/dev/null 2>&1 && command -v tr >/dev/null 2>&1 && {program} -fc 'autoload -Uz add-zsh-hook' >/dev/null 2>&1 && printf '{REMOTE_CAPABILITY_MARKER}\\n'"
        )),
        RemoteShellKind::Bash => Some(format!(
            "command -v od >/dev/null 2>&1 && command -v tr >/dev/null 2>&1 && {program} --noprofile --norc -c ':' >/dev/null 2>&1 && printf '{REMOTE_CAPABILITY_MARKER}\\n'"
        )),
        RemoteShellKind::Fish => Some(format!(
            "command -sq od; and command -sq tr; and {program} --init-command ':' -c ':' >/dev/null 2>&1; and printf '{REMOTE_CAPABILITY_MARKER}\\n'"
        )),
        RemoteShellKind::Sh => Some(format!(
            "command -v printf >/dev/null 2>&1 && {program} -c ':' >/dev/null 2>&1 && printf '{REMOTE_CAPABILITY_MARKER}\\n'"
        )),
        RemoteShellKind::Other => None,
    }
}

fn remote_shell_integration_files(kind: RemoteShellKind) -> Vec<(&'static str, String)> {
    match kind {
        RemoteShellKind::Zsh => crate::pty::zsh_shell_integration_files(),
        RemoteShellKind::Bash => vec![(
            ".bashrc",
            crate::pty::remote_bash_shell_integration_source(),
        )],
        RemoteShellKind::Fish => vec![(
            "init.fish",
            crate::pty::fish_shell_integration_source().to_string(),
        )],
        RemoteShellKind::Sh => vec![(
            "init.sh",
            crate::pty::sh_shell_integration_source().to_string(),
        )],
        RemoteShellKind::Other => Vec::new(),
    }
}

fn remote_shell_launch_command(kind: RemoteShellKind, program: &str, directory: &str) -> String {
    let program = shell_quote(program);
    let directory = shell_quote(directory);
    match kind {
        RemoteShellKind::Zsh => format!(
            "if [ \"${{ZDOTDIR+x}}\" = x ]; then export IANVS_ORIGINAL_ZDOTDIR_WAS_SET=1 IANVS_ORIGINAL_ZDOTDIR=\"$ZDOTDIR\"; else export IANVS_ORIGINAL_ZDOTDIR_WAS_SET=0 IANVS_ORIGINAL_ZDOTDIR=; fi; export IANVS_SHELL_INTEGRATION=1 ZDOTDIR={directory}; exec {program} -l"
        ),
        RemoteShellKind::Bash => format!(
            "export IANVS_SHELL_INTEGRATION=1 IANVS_SKIP_ORIGINAL_BASHRC=1; exec {program} --rcfile {directory}/.bashrc -i"
        ),
        RemoteShellKind::Fish => format!(
            "set -gx IANVS_SHELL_INTEGRATION 1; set -gx IANVS_FISH_INIT {directory}/init.fish; exec {program} -l --init-command 'source \"$IANVS_FISH_INIT\"'"
        ),
        RemoteShellKind::Sh => format!(
            "if [ \"${{ENV+x}}\" = x ]; then export IANVS_ORIGINAL_ENV_WAS_SET=1 IANVS_ORIGINAL_ENV=\"$ENV\"; else export IANVS_ORIGINAL_ENV_WAS_SET=0 IANVS_ORIGINAL_ENV=; fi; export IANVS_SHELL_INTEGRATION=1 ENV={directory}/init.sh; exec {program} -l -i"
        ),
        RemoteShellKind::Other => format!("exec {program} -l"),
    }
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

async fn cleanup_remote_shell_integration(
    session: &client::Handle<SshClientHandler>,
    integration: &RemoteShellIntegration,
) {
    let Ok(sftp) = open_sftp_session(session).await else {
        return;
    };
    for path in integration.files.iter().rev() {
        let _ = sftp.remove_file(path).await;
    }
    let _ = sftp.remove_dir(&integration.directory).await;
}

async fn teardown_ssh_network(
    channel: Channel<client::Msg>,
    session: client::Handle<SshClientHandler>,
    jump_sessions: Vec<client::Handle<SshClientHandler>>,
) {
    let teardown = async move {
        let _ = channel.eof().await;
        let _ = channel.close().await;
        let _ = session
            .disconnect(Disconnect::ByApplication, "", "en")
            .await;
        for jump_session in jump_sessions.iter().rev() {
            let _ = jump_session
                .disconnect(Disconnect::ByApplication, "", "en")
                .await;
        }
    };
    let _ = await_bounded_ssh_teardown(teardown, SSH_NETWORK_TEARDOWN_TIMEOUT).await;
}

async fn prepare_ssh_session(
    connection: &TerminalProfileConnection,
    initial_size: PtySize,
    shell_integration_enabled: bool,
    auth: &SshAuthClient,
    cancellation: &SshCancellation,
    forward_runtime: &ForwardRuntime,
) -> Result<PreparedSshSession> {
    let x11_proxy = build_x11_proxy(connection)?;
    let (session, jump_sessions) = connect_authenticated(
        connection,
        auth,
        cancellation,
        x11_proxy.clone(),
        forward_runtime,
    )
    .await?;

    if connection.agent_forwarding
        && connection.agent_socket.is_none()
        && std::env::var_os("SSH_AUTH_SOCK").is_none()
    {
        bail!("agent forwarding requires agentSocket or SSH_AUTH_SOCK");
    }

    let (forward_sender, forward_receiver) = mpsc::channel(MAX_PENDING_FORWARD_HANDSHAKES);
    let forward_listeners =
        start_local_forward_listeners(connection, forward_sender, forward_runtime.clone()).await?;
    request_remote_forwards(&session, connection).await?;

    let shell_integration = if shell_integration_enabled {
        prepare_remote_shell_integration(&session, cancellation)
            .await
            .ok()
            .flatten()
    } else {
        None
    };

    let channel = session.channel_open_session().await?;
    if connection.agent_forwarding {
        channel.agent_forward(true).await?;
    }
    if connection.x11_forwarding {
        let proxy = x11_proxy
            .as_ref()
            .ok_or_else(|| anyhow!("X11 forwarding has no secure cookie proxy"))?;
        channel
            .request_x11(
                true,
                false,
                connection.x11_auth_protocol.clone(),
                encode_x11_cookie(&proxy.fake_cookie),
                connection.x11_screen_number,
            )
            .await?;
    }
    channel
        .request_pty(
            false,
            "xterm-256color",
            u32::from(initial_size.cols),
            u32::from(initial_size.rows),
            u32::from(initial_size.pixel_width),
            u32::from(initial_size.pixel_height),
            &[],
        )
        .await?;
    if let Some(integration) = &shell_integration {
        if channel
            .exec(true, integration.launch_command.clone())
            .await
            .is_err()
        {
            channel.request_shell(true).await?;
        }
    } else {
        channel.request_shell(true).await?;
    }

    Ok(PreparedSshSession {
        session,
        jump_sessions,
        forward_receiver,
        forward_listeners,
        channel,
        shell_integration,
    })
}

async fn await_ssh_setup<F, T>(
    setup: F,
    setup_timeout: Duration,
    auth: &SshAuthClient,
    cancellation: &SshCancellation,
) -> Result<T>
where
    F: Future<Output = Result<T>>,
{
    tokio::pin!(setup);
    loop {
        if auth.has_pending_interaction() {
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => {
                    return Err(anyhow!("SSH initialization was cancelled"));
                },
                result = &mut setup => return result,
                _ = auth.wait_until_interactions_complete() => {},
            }
            continue;
        }

        let deadline = tokio::time::sleep(setup_timeout);
        tokio::pin!(deadline);
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => {
                return Err(anyhow!("SSH initialization was cancelled"));
            },
            result = &mut setup => return result,
            _ = auth.wait_until_interaction_begins() => {},
            _ = &mut deadline => {
                return Err(anyhow!(
                    "SSH initialization timed out after {} seconds",
                    setup_timeout.as_secs()
                ));
            },
        }
    }
}

async fn run_ssh_session(
    connection: TerminalProfileConnection,
    initial_size: PtySize,
    shell_integration_enabled: bool,
    mut commands: mpsc::UnboundedReceiver<SshCommand>,
    output: std_mpsc::Sender<Vec<u8>>,
    auth: SshAuthClient,
    cancellation: SshCancellation,
) -> Result<u32> {
    let forward_runtime = ForwardRuntime::new(cancellation.clone());
    let setup_timeout = Duration::from_secs(connection.connect_timeout_seconds.clamp(1, 120));
    let prepared = await_ssh_setup(
        prepare_ssh_session(
            &connection,
            initial_size,
            shell_integration_enabled,
            &auth,
            &cancellation,
            &forward_runtime,
        ),
        setup_timeout,
        &auth,
        &cancellation,
    )
    .await;
    let prepared = match prepared {
        Ok(prepared) => prepared,
        Err(error) => {
            auth.cancel_all();
            shutdown_ssh_resources(&cancellation, &forward_runtime).await;
            return Err(error);
        }
    };
    let PreparedSshSession {
        session,
        jump_sessions,
        mut forward_receiver,
        forward_listeners,
        mut channel,
        shell_integration,
    } = prepared;
    let _ = output.send(
        format!(
            "\r\nConnected to {}@{}:{}\r\n",
            connection.user, connection.host, connection.port
        )
        .into_bytes(),
    );

    let mut exit_status = 0;
    let session_result: Result<()> = async {
        let mut sftp_requests: FuturesUnordered<BoxFuture<'_, ()>> =
            FuturesUnordered::new();
        let sftp_operation_root = SftpOperationCancellation::new();
        let channel_loop_result: Result<()> = async {
        loop {
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => {
                break;
            },
            _ = sftp_requests.next(), if !sftp_requests.is_empty() => {},
            command = commands.recv() => match command {
                Some(SshCommand::Data(bytes)) => channel.data_bytes(bytes).await?,
                Some(SshCommand::Resize(size)) => {
                    channel.window_change(
                        u32::from(size.cols),
                        u32::from(size.rows),
                        u32::from(size.pixel_width),
                        u32::from(size.pixel_height),
                    ).await?;
                }
                Some(SshCommand::ListDirectory { path, mut response }) => {
                    if response.is_closed() {
                        continue;
                    }
                    if sftp_requests.len() >= MAX_CONCURRENT_SFTP_REQUESTS {
                        let _ = response.send(Err(
                            "too many concurrent SFTP directory requests".to_string(),
                        ));
                        continue;
                    }
                    let request = list_sftp_directory(&session, path);
                    sftp_requests.push(Box::pin(async move {
                        let result = tokio::select! {
                            biased;
                            _ = response.closed() => return,
                            result = tokio::time::timeout(
                                SFTP_DIRECTORY_REQUEST_TIMEOUT,
                                request,
                            ) => match result {
                                Ok(result) => result.map_err(|error| error.to_string()),
                                Err(_) => Err("SFTP directory request timed out".to_string()),
                            },
                        };
                        let _ = response.send(result);
                    }));
                }
                Some(SshCommand::SftpOperation { operation, mut response }) => {
                    if response.is_closed() {
                        continue;
                    }
                    if sftp_requests.len() >= MAX_CONCURRENT_SFTP_REQUESTS {
                        let _ = response.send(Err(
                            "too many concurrent SFTP file requests".to_string(),
                        ));
                        continue;
                    }
                    let cancellation = sftp_operation_root.child();
                    let request = execute_sftp_operation(
                        &session,
                        operation,
                        cancellation.clone(),
                    );
                    sftp_requests.push(Box::pin(async move {
                        tokio::pin!(request);
                        let result = tokio::select! {
                            biased;
                            _ = response.closed() => {
                                cancellation.cancel();
                                let _ = tokio::time::timeout(
                                    SFTP_FILE_CANCELLATION_CLEANUP_TIMEOUT,
                                    &mut request,
                                ).await;
                                return;
                            },
                            result = tokio::time::timeout(
                                SFTP_FILE_OPERATION_REQUEST_TIMEOUT,
                                &mut request,
                            ) => match result {
                                Ok(result) => result.map_err(|error| error.to_string()),
                                Err(_) => {
                                    cancellation.cancel();
                                    let _ = tokio::time::timeout(
                                        SFTP_FILE_CANCELLATION_CLEANUP_TIMEOUT,
                                        &mut request,
                                    ).await;
                                    Err("SFTP file operation timed out".to_string())
                                },
                            },
                        };
                        let _ = response.send(result);
                    }));
                }
                Some(SshCommand::Close) | None => {
                    break;
                }
            },
            message = channel.wait() => match message {
                Some(ChannelMsg::Data { data }) | Some(ChannelMsg::ExtendedData { data, .. }) => {
                    if output.send(data.to_vec()).is_err() {
                        break;
                    }
                }
                Some(ChannelMsg::ExitStatus { exit_status: code }) => {
                    exit_status = code;
                }
                Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => break,
                _ => {}
            },
            accepted = forward_receiver.recv(), if !forward_listeners.is_empty() => {
                if let Some(mut accepted) = accepted {
                    let Some(permit) = forward_runtime.try_relay_permit() else {
                        if accepted.socks5 {
                            let _ = send_socks_reply(&mut accepted.stream, 1).await;
                        }
                        continue;
                    };
                    let open_channel = tokio::select! {
                        biased;
                        _ = cancellation.cancelled() => None,
                        result = tokio::time::timeout(
                            FORWARD_CONNECT_TIMEOUT,
                            session.channel_open_direct_tcpip(
                                accepted.target_host.clone(),
                                u32::from(accepted.target_port),
                                accepted.stream.peer_addr().map(|address| address.ip().to_string()).unwrap_or_else(|_| "127.0.0.1".to_string()),
                                accepted.stream.peer_addr().map(|address| u32::from(address.port())).unwrap_or(0),
                            ),
                        ) => result.ok(),
                    };
                    let Some(open_channel) = open_channel else {
                        if accepted.socks5 {
                            let _ = send_socks_reply(&mut accepted.stream, 1).await;
                        }
                        continue;
                    };
                    match open_channel {
                        Ok(forward_channel) => {
                            if accepted.socks5 && !send_socks_reply(&mut accepted.stream, 0).await {
                                let _ = forward_channel.close().await;
                                continue;
                            }
                            let _ = forward_runtime.spawn_relay(
                                forward_channel.into_stream(),
                                accepted.stream,
                                permit,
                            );
                        }
                        Err(_error) => {
                            if accepted.socks5 {
                                let _ = send_socks_reply(&mut accepted.stream, 1).await;
                            }
                        }
                    }
                }
            },
        }
        }
        Ok(())
        }.await;
        finish_sftp_request_scope(
            channel_loop_result,
            &sftp_operation_root,
            &mut sftp_requests,
        ).await
    }
    .await;
    forward_listeners.abort_all();
    auth.cancel_all();
    if let Some(integration) = &shell_integration {
        let _ = tokio::time::timeout(
            SSH_SHELL_CLEANUP_TIMEOUT,
            cleanup_remote_shell_integration(&session, integration),
        )
        .await;
    }
    shutdown_ssh_resources(&cancellation, &forward_runtime).await;
    teardown_ssh_network(channel, session, jump_sessions).await;
    session_result?;
    Ok(exit_status)
}

async fn finish_sftp_request_scope<T>(
    channel_loop_result: Result<T>,
    cancellation: &SftpOperationCancellation,
    requests: &mut FuturesUnordered<BoxFuture<'_, ()>>,
) -> Result<T> {
    cancellation.cancel();
    let _ = tokio::time::timeout(SFTP_FILE_CANCELLATION_CLEANUP_TIMEOUT, async {
        while requests.next().await.is_some() {}
    })
    .await;
    channel_loop_result
}

async fn list_sftp_directory(
    session: &client::Handle<SshClientHandler>,
    path: String,
) -> Result<SftpDirectoryListing> {
    let channel = session
        .channel_open_session()
        .await
        .context("could not open SFTP channel")?;
    channel
        .request_subsystem(true, "sftp")
        .await
        .context("remote server rejected the SFTP subsystem")?;
    let sftp = RawSftpSession::new_with_config(
        SftpPacketLengthLimitedStream::new(channel.into_stream(), MAX_SFTP_INBOUND_PACKET_BYTES),
        SftpConfig {
            max_packet_len: MAX_SFTP_INBOUND_PACKET_BYTES,
            request_timeout_secs: 10,
            ..SftpConfig::default()
        },
    );
    sftp.init().await.context("could not initialize SFTP")?;
    let handle = sftp
        .opendir(path.clone())
        .await
        .context("could not open remote directory")?
        .handle;
    let entries_result: Result<Vec<SftpDirectoryEntry>> = async {
        let mut entries = Vec::new();
        let mut wire_bytes = serde_json::to_vec(&serde_json::json!({
            "status": "complete",
            "path": path,
            "entries": [],
        }))
        .context("could not measure SFTP directory response")?
        .len();
        loop {
            let files = match sftp.readdir(handle.clone()).await {
                Ok(response) => response.files,
                Err(SftpError::Status(status)) if status.status_code == SftpStatusCode::Eof => {
                    break;
                }
                Err(error) => return Err(error).context("could not read remote directory"),
            };
            for file in files {
                if file.filename == "." || file.filename == ".." {
                    continue;
                }
                if entries.len() >= MAX_SFTP_DIRECTORY_ENTRIES {
                    bail!("remote directory exceeds the entry limit");
                }
                let name = file.filename;
                if !is_valid_sftp_entry_name(&name) {
                    bail!("remote directory contains an invalid entry name");
                }
                let metadata = file.attrs;
                let file_type = metadata.file_type();
                let kind = match file_type {
                    SftpFileType::Dir => "directory",
                    SftpFileType::File => "file",
                    SftpFileType::Symlink => "symbolic_link",
                    SftpFileType::Other => "other",
                };
                let permissions = metadata.permissions.map(|_| {
                    let prefix = match file_type {
                        SftpFileType::Dir => 'd',
                        SftpFileType::File => '-',
                        SftpFileType::Symlink => 'l',
                        SftpFileType::Other => '?',
                    };
                    format!("{prefix}{}", metadata.permissions())
                });
                let entry = SftpDirectoryEntry {
                    name,
                    kind,
                    size_bytes: metadata.size.and_then(|size| i64::try_from(size).ok()),
                    modified_at_epoch_seconds: metadata.mtime,
                    permissions,
                };
                reserve_sftp_entry_wire_bytes(&mut wire_bytes, &entry)?;
                entries.push(entry);
            }
        }
        Ok(entries)
    }
    .await;
    let _ = sftp.close(handle).await;
    let _ = sftp.close_session();
    let entries = entries_result?;
    Ok(SftpDirectoryListing { path, entries })
}

async fn open_sftp_session(session: &client::Handle<SshClientHandler>) -> Result<SftpSession> {
    let channel = session
        .channel_open_session()
        .await
        .context("could not open SFTP channel")?;
    channel
        .request_subsystem(true, "sftp")
        .await
        .context("remote server rejected the SFTP subsystem")?;
    SftpSession::new_with_config(
        SftpPacketLengthLimitedStream::new(channel.into_stream(), MAX_SFTP_INBOUND_PACKET_BYTES),
        SftpConfig {
            max_packet_len: MAX_SFTP_INBOUND_PACKET_BYTES,
            request_timeout_secs: 10,
            ..SftpConfig::default()
        },
    )
    .await
    .context("could not initialize SFTP")
}

async fn execute_sftp_operation(
    session: &client::Handle<SshClientHandler>,
    operation: SftpOperation,
    cancellation: SftpOperationCancellation,
) -> Result<()> {
    let sftp = tokio::select! {
        biased;
        _ = cancellation.cancelled() => bail!("SFTP file operation was cancelled"),
        result = open_sftp_session(session) => result?,
    };
    let result = match operation {
        SftpOperation::DownloadFile {
            remote_path,
            local_path,
        } => download_sftp_file(&sftp, &remote_path, &local_path, &cancellation).await,
        SftpOperation::UploadFile {
            local_path,
            remote_path,
        } => {
            upload_sftp_file(
                Some(session),
                &sftp,
                &local_path,
                &remote_path,
                &cancellation,
            )
            .await
        }
        SftpOperation::CreateDirectory { path } => {
            sftp_operation_step(&cancellation, sftp.create_dir(path))
                .await
                .context("could not create remote directory")
        }
        SftpOperation::DeleteEntry { path, is_directory } => {
            if is_directory {
                sftp_operation_step(&cancellation, sftp.remove_dir(path))
                    .await
                    .context("could not delete remote directory")
            } else {
                sftp_operation_step(&cancellation, sftp.remove_file(path))
                    .await
                    .context("could not delete remote file")
            }
        }
    };
    let _ = sftp.close().await;
    result
}

async fn download_sftp_file(
    sftp: &SftpSession,
    remote_path: &str,
    local_path: &str,
    cancellation: &SftpOperationCancellation,
) -> Result<()> {
    let destination = PathBuf::from(local_path);
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| anyhow!("download destination has no parent directory"))?;
    let file_name = destination
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .ok_or_else(|| anyhow!("download destination has no file name"))?;
    let staging = parent.join(format!(
        ".{file_name}.ianvs-{}.download",
        random_sftp_transfer_token()?
    ));
    let mut staging_cleanup = LocalStagingCleanup::new(staging.clone());

    let result: Result<()> = async {
        let mut remote = sftp_operation_step(cancellation, sftp.open(remote_path))
            .await
            .context("could not open remote file")?;
        let mut local = sftp_operation_step(
            cancellation,
            tokio::fs::OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(&staging),
        )
        .await
        .context("could not create local download")?;
        let mut buffer = vec![0_u8; SFTP_FILE_COPY_BUFFER_BYTES];
        let mut copied = 0_u64;
        loop {
            let read = sftp_operation_step(cancellation, remote.read(&mut buffer))
                .await
                .context("could not read remote file")?;
            if read == 0 {
                break;
            }
            copied = copied
                .checked_add(read as u64)
                .ok_or_else(|| anyhow!("remote file size overflowed"))?;
            if copied > MAX_SFTP_FILE_TRANSFER_BYTES {
                bail!("remote file exceeds the transfer size limit");
            }
            sftp_operation_step(cancellation, local.write_all(&buffer[..read]))
                .await
                .context("could not write local download")?;
        }
        sftp_operation_step(cancellation, local.flush())
            .await
            .context("could not flush local download")?;
        sftp_operation_step(cancellation, local.sync_all())
            .await
            .context("could not persist local download")?;
        sftp_operation_step(cancellation, remote.close())
            .await
            .context("could not close remote file")?;
        drop(local);
        install_local_download(&staging, &destination, cancellation).await?;
        Ok(())
    }
    .await;
    if result.is_ok() {
        staging_cleanup.disarm();
    }
    result
}

#[cfg(not(windows))]
async fn install_local_download(
    staging: &Path,
    destination: &Path,
    cancellation: &SftpOperationCancellation,
) -> Result<()> {
    sftp_operation_step(cancellation, tokio::fs::rename(staging, destination))
        .await
        .context("could not atomically install local download")
}

#[cfg(windows)]
async fn install_local_download(
    staging: &Path,
    destination: &Path,
    _cancellation: &SftpOperationCancellation,
) -> Result<()> {
    use std::iter;
    use std::os::windows::ffi::OsStrExt as _;
    use windows_sys::Win32::Storage::FileSystem::{
        MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
    };

    let staging_wide: Vec<u16> = staging
        .as_os_str()
        .encode_wide()
        .chain(iter::once(0))
        .collect();
    let destination_wide: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(iter::once(0))
        .collect();
    tokio::task::spawn_blocking(move || {
        // SAFETY: both pointers reference owned, NUL-terminated UTF-16 buffers
        // for the duration of this call. MoveFileExW does not retain them.
        let moved = unsafe {
            MoveFileExW(
                staging_wide.as_ptr(),
                destination_wide.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        };
        if moved == 0 {
            Err(IoError::last_os_error())
        } else {
            Ok(())
        }
    })
    .await
    .context("local download replacement worker failed")?
    .context("could not atomically install local download")
}

async fn upload_sftp_file(
    ssh_session: Option<&client::Handle<SshClientHandler>>,
    sftp: &SftpSession,
    local_path: &str,
    remote_path: &str,
    cancellation: &SftpOperationCancellation,
) -> Result<()> {
    let metadata = sftp_operation_step(cancellation, tokio::fs::metadata(local_path))
        .await
        .context("could not inspect local edit")?;
    if !metadata.is_file() {
        bail!("local edit is not a regular file");
    }
    if metadata.len() > MAX_SFTP_FILE_TRANSFER_BYTES {
        bail!("local edit exceeds the transfer size limit");
    }
    let token = random_sftp_transfer_token()?;
    let staging_path = format!("{remote_path}.ianvs-{token}.upload");
    if staging_path.len() > 4096 {
        bail!("remote path is too long for a safe upload");
    }

    let (target_existed, original_permissions) = tokio::select! {
        biased;
        _ = cancellation.cancelled() => bail!("SFTP file operation was cancelled"),
        result = sftp.metadata(remote_path) => match result {
            Ok(metadata) => (true, metadata.permissions),
            Err(SftpError::Status(status))
                if status.status_code == SftpStatusCode::NoSuchFile => (false, None),
            Err(error) => return Err(error).context("could not inspect remote file"),
        },
    };
    let result: Result<()> = async {
        let mut local = sftp_operation_step(cancellation, tokio::fs::File::open(local_path))
            .await
            .context("could not open local edit")?;
        let mut remote = sftp_operation_step(cancellation, sftp.create(&staging_path))
            .await
            .context("could not create remote upload")?;
        let mut buffer = vec![0_u8; SFTP_FILE_COPY_BUFFER_BYTES];
        let mut copied = 0_u64;
        loop {
            let read = sftp_operation_step(cancellation, local.read(&mut buffer))
                .await
                .context("could not read local edit")?;
            if read == 0 {
                break;
            }
            copied = copied
                .checked_add(read as u64)
                .ok_or_else(|| anyhow!("local edit size overflowed"))?;
            if copied > MAX_SFTP_FILE_TRANSFER_BYTES {
                bail!("local edit exceeds the transfer size limit");
            }
            sftp_operation_step(cancellation, remote.write_all(&buffer[..read]))
                .await
                .context("could not write remote upload")?;
        }
        sftp_operation_step(cancellation, remote.flush())
            .await
            .context("could not flush remote upload")?;
        let permissions = SftpFileAttributes {
            permissions: original_permissions,
            ..SftpFileAttributes::empty()
        };
        if permissions.permissions.is_some() {
            sftp_operation_step(cancellation, remote.set_metadata(permissions))
                .await
                .context("could not preserve remote file permissions")?;
        }
        sftp_operation_step(cancellation, remote.sync_all())
            .await
            .context("could not persist remote upload")?;
        sftp_operation_step(cancellation, remote.close())
            .await
            .context("could not close remote upload")?;

        let used_posix_rename = if let Some(ssh_session) = ssh_session {
            posix_rename_sftp_file(ssh_session, &staging_path, remote_path, cancellation).await?
        } else {
            #[cfg(test)]
            {
                sftp_operation_step(cancellation, sftp.rename(&staging_path, remote_path))
                    .await
                    .context("test SFTP server could not install the upload")?;
                true
            }
            #[cfg(not(test))]
            {
                bail!("atomic SFTP rename adapter is unavailable");
            }
        };
        if !used_posix_rename {
            if target_existed {
                bail!("remote server does not support atomic replacement of an existing file");
            }
            sftp_operation_step(cancellation, sftp.rename(&staging_path, remote_path))
                .await
                .context("could not install the new remote file")?;
        }
        Ok(())
    }
    .await;
    if result.is_err() {
        let _ = sftp.remove_file(&staging_path).await;
    }
    result
}

async fn posix_rename_sftp_file(
    session: &client::Handle<SshClientHandler>,
    old_path: &str,
    new_path: &str,
    cancellation: &SftpOperationCancellation,
) -> Result<bool> {
    let channel = sftp_operation_step(cancellation, session.channel_open_session())
        .await
        .context("could not open atomic SFTP rename channel")?;
    sftp_operation_step(cancellation, channel.request_subsystem(true, "sftp"))
        .await
        .context("remote server rejected the atomic SFTP rename channel")?;
    let raw = RawSftpSession::new_with_config(
        SftpPacketLengthLimitedStream::new(channel.into_stream(), MAX_SFTP_INBOUND_PACKET_BYTES),
        SftpConfig {
            max_packet_len: MAX_SFTP_INBOUND_PACKET_BYTES,
            request_timeout_secs: 10,
            ..SftpConfig::default()
        },
    );
    let version = sftp_operation_step(cancellation, raw.init())
        .await
        .context("could not initialize atomic SFTP rename")?;
    if version
        .extensions
        .get("posix-rename@openssh.com")
        .map(String::as_str)
        != Some("1")
    {
        let _ = raw.close_session();
        return Ok(false);
    }
    let mut data = Vec::with_capacity(old_path.len() + new_path.len() + 8);
    append_sftp_string(&mut data, old_path)?;
    append_sftp_string(&mut data, new_path)?;
    let response =
        sftp_operation_step(cancellation, raw.extended("posix-rename@openssh.com", data))
            .await
            .context("atomic SFTP rename request failed")?;
    let _ = raw.close_session();
    match response {
        SftpPacket::Status(status) if status.status_code == SftpStatusCode::Ok => Ok(true),
        SftpPacket::Status(status) => {
            Err(SftpError::Status(status)).context("atomic SFTP rename was rejected")
        }
        _ => bail!("atomic SFTP rename returned an unexpected packet"),
    }
}

fn append_sftp_string(buffer: &mut Vec<u8>, value: &str) -> Result<()> {
    let length = u32::try_from(value.len()).context("SFTP path length overflowed")?;
    buffer.extend_from_slice(&length.to_be_bytes());
    buffer.extend_from_slice(value.as_bytes());
    Ok(())
}

#[derive(Clone)]
struct SftpOperationCancellation {
    state: Arc<SftpOperationCancellationState>,
    parent: Option<Arc<SftpOperationCancellationState>>,
}

struct SftpOperationCancellationState {
    cancelled: AtomicBool,
    notify: Notify,
}

impl SftpOperationCancellation {
    fn new() -> Self {
        Self {
            state: Arc::new(SftpOperationCancellationState {
                cancelled: AtomicBool::new(false),
                notify: Notify::new(),
            }),
            parent: None,
        }
    }

    fn child(&self) -> Self {
        Self {
            state: Arc::new(SftpOperationCancellationState {
                cancelled: AtomicBool::new(false),
                notify: Notify::new(),
            }),
            parent: Some(Arc::clone(&self.state)),
        }
    }

    fn cancel(&self) {
        if !self.state.cancelled.swap(true, Ordering::AcqRel) {
            self.state.notify.notify_waiters();
        }
    }

    async fn cancelled(&self) {
        if let Some(parent) = &self.parent {
            tokio::select! {
                _ = wait_for_sftp_cancellation(&self.state) => {},
                _ = wait_for_sftp_cancellation(parent) => {},
            }
        } else {
            wait_for_sftp_cancellation(&self.state).await;
        }
    }
}

async fn wait_for_sftp_cancellation(state: &SftpOperationCancellationState) {
    loop {
        let notified = state.notify.notified();
        if state.cancelled.load(Ordering::Acquire) {
            return;
        }
        notified.await;
    }
}

async fn sftp_operation_step<T, E, F>(
    cancellation: &SftpOperationCancellation,
    operation: F,
) -> Result<T>
where
    F: Future<Output = std::result::Result<T, E>>,
    E: std::error::Error + Send + Sync + 'static,
{
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => bail!("SFTP file operation was cancelled"),
        result = operation => result.map_err(anyhow::Error::new),
    }
}

struct LocalStagingCleanup {
    path: PathBuf,
    armed: bool,
}

impl LocalStagingCleanup {
    fn new(path: PathBuf) -> Self {
        Self { path, armed: true }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for LocalStagingCleanup {
    fn drop(&mut self) {
        if self.armed {
            let _ = fs::remove_file(&self.path);
        }
    }
}

fn random_sftp_transfer_token() -> Result<String> {
    let mut bytes = [0_u8; 12];
    getrandom::fill(&mut bytes)
        .map_err(|error| anyhow!("could not generate an SFTP transfer token: {error}"))?;
    let mut token = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        write!(&mut token, "{byte:02x}").expect("writing to a string cannot fail");
    }
    Ok(token)
}

/// Enforces the SFTP frame length before the upstream decoder allocates its
/// payload buffer. `russh-sftp` 2.4.0 applies `Config.max_packet_len` to
/// outgoing requests but reads incoming frames with a `u32::MAX` limit.
struct SftpPacketLengthLimitedStream<S> {
    inner: S,
    max_packet_len: u32,
    prefix: [u8; 4],
    prefix_len: usize,
    prefix_sent: usize,
    payload_remaining: Option<u32>,
    rejected: bool,
}

impl<S> SftpPacketLengthLimitedStream<S> {
    fn new(inner: S, max_packet_len: u32) -> Self {
        Self {
            inner,
            max_packet_len,
            prefix: [0; 4],
            prefix_len: 0,
            prefix_sent: 0,
            payload_remaining: None,
            rejected: false,
        }
    }

    fn finish_frame(&mut self) {
        self.prefix_len = 0;
        self.prefix_sent = 0;
        self.payload_remaining = None;
    }
}

impl<S> AsyncRead for SftpPacketLengthLimitedStream<S>
where
    S: AsyncRead + Unpin,
{
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut TaskContext<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<IoResult<()>> {
        let this = self.get_mut();
        let initially_filled = buffer.filled().len();
        loop {
            if buffer.remaining() == 0 {
                return Poll::Ready(Ok(()));
            }
            if this.rejected {
                return Poll::Ready(Err(IoError::new(
                    ErrorKind::UnexpectedEof,
                    "SFTP stream terminated after rejecting an oversized packet",
                )));
            }
            if this.payload_remaining.is_none() {
                while this.prefix_len < this.prefix.len() {
                    let mut prefix_buffer = ReadBuf::new(&mut this.prefix[this.prefix_len..]);
                    match Pin::new(&mut this.inner).poll_read(context, &mut prefix_buffer) {
                        Poll::Pending => {
                            return if buffer.filled().len() > initially_filled {
                                Poll::Ready(Ok(()))
                            } else {
                                Poll::Pending
                            };
                        }
                        Poll::Ready(Err(error)) => return Poll::Ready(Err(error)),
                        Poll::Ready(Ok(())) => {
                            let read = prefix_buffer.filled().len();
                            if read == 0 {
                                return if this.prefix_len == 0 {
                                    Poll::Ready(Ok(()))
                                } else {
                                    Poll::Ready(Err(IoError::new(
                                        ErrorKind::UnexpectedEof,
                                        "SFTP packet ended inside its length prefix",
                                    )))
                                };
                            }
                            this.prefix_len += read;
                        }
                    }
                }
                let packet_len = u32::from_be_bytes(this.prefix);
                if packet_len > this.max_packet_len {
                    this.rejected = true;
                    return Poll::Ready(Err(IoError::new(
                        ErrorKind::InvalidData,
                        "SFTP packet length limit exceeded",
                    )));
                }
                this.payload_remaining = Some(packet_len);
                this.prefix_sent = 0;
            }

            if this.prefix_sent < this.prefix.len() {
                let count = (this.prefix.len() - this.prefix_sent).min(buffer.remaining());
                buffer.put_slice(&this.prefix[this.prefix_sent..this.prefix_sent + count]);
                this.prefix_sent += count;
                if buffer.remaining() == 0 {
                    return Poll::Ready(Ok(()));
                }
            }

            let remaining = this
                .payload_remaining
                .expect("validated SFTP frame must track its payload");
            if remaining == 0 {
                this.finish_frame();
                continue;
            }

            let limit = buffer
                .remaining()
                .min(remaining as usize)
                .min(SFTP_LIMITED_READ_CHUNK_BYTES);
            let mut scratch = [0; SFTP_LIMITED_READ_CHUNK_BYTES];
            let mut payload_buffer = ReadBuf::new(&mut scratch[..limit]);
            match Pin::new(&mut this.inner).poll_read(context, &mut payload_buffer) {
                Poll::Pending => {
                    return if buffer.filled().len() > initially_filled {
                        Poll::Ready(Ok(()))
                    } else {
                        Poll::Pending
                    };
                }
                Poll::Ready(Err(error)) => return Poll::Ready(Err(error)),
                Poll::Ready(Ok(())) => {
                    let read = payload_buffer.filled().len();
                    if read == 0 {
                        return Poll::Ready(Err(IoError::new(
                            ErrorKind::UnexpectedEof,
                            "SFTP packet ended inside its payload",
                        )));
                    }
                    buffer.put_slice(payload_buffer.filled());
                    let next_remaining = remaining - read as u32;
                    this.payload_remaining = Some(next_remaining);
                    if next_remaining == 0 {
                        this.finish_frame();
                    }
                    return Poll::Ready(Ok(()));
                }
            }
        }
    }
}

impl<S> AsyncWrite for SftpPacketLengthLimitedStream<S>
where
    S: AsyncWrite + Unpin,
{
    fn poll_write(
        self: Pin<&mut Self>,
        context: &mut TaskContext<'_>,
        buffer: &[u8],
    ) -> Poll<IoResult<usize>> {
        Pin::new(&mut self.get_mut().inner).poll_write(context, buffer)
    }

    fn poll_flush(self: Pin<&mut Self>, context: &mut TaskContext<'_>) -> Poll<IoResult<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(context)
    }

    fn poll_shutdown(self: Pin<&mut Self>, context: &mut TaskContext<'_>) -> Poll<IoResult<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(context)
    }
}

fn reserve_sftp_entry_wire_bytes(wire_bytes: &mut usize, entry: &SftpDirectoryEntry) -> Result<()> {
    let entry_bytes = serde_json::to_vec(entry)
        .context("could not measure SFTP directory entry")?
        .len()
        .saturating_add(1);
    let next = wire_bytes
        .checked_add(entry_bytes)
        .ok_or_else(|| anyhow!("remote directory response size overflowed"))?;
    if next > MAX_SFTP_DIRECTORY_WIRE_BYTES {
        bail!("remote directory exceeds the response size limit");
    }
    *wire_bytes = next;
    Ok(())
}

fn is_valid_sftp_entry_name(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && name.len() <= MAX_SFTP_ENTRY_NAME_BYTES
        && !name.contains(['/', '\\'])
        && !name.chars().any(char::is_control)
}

fn client_config(connection: &TerminalProfileConnection) -> Arc<client::Config> {
    Arc::new(client::Config {
        inactivity_timeout: None,
        keepalive_interval: (connection.keepalive_seconds > 0)
            .then(|| Duration::from_secs(connection.keepalive_seconds)),
        keepalive_max: connection.keepalive_count_max,
        nodelay: true,
        ..<_>::default()
    })
}

fn client_handler(
    connection: &TerminalProfileConnection,
    interactions: SshAuthClient,
    x11_proxy: Option<X11ProxyConfig>,
    forward_runtime: ForwardRuntime,
) -> SshClientHandler {
    SshClientHandler {
        host: connection.host.clone(),
        port: connection.port,
        policy: connection.host_key_policy,
        known_hosts_file: connection.known_hosts_file.as_deref().map(expand_home_path),
        interactions,
        remote_forwards: connection.port_forwards.clone(),
        agent_socket: connection
            .agent_forwarding
            .then(|| {
                connection
                    .agent_socket
                    .as_deref()
                    .map(expand_home_path)
                    .or_else(|| std::env::var_os("SSH_AUTH_SOCK").map(PathBuf::from))
            })
            .flatten(),
        x11_proxy,
        forward_runtime,
    }
}

fn generate_x11_auth_cookie() -> Result<[u8; 16]> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes)
        .map_err(|error| anyhow!("could not generate the X11 authentication cookie: {error}"))?;
    Ok(bytes)
}

fn build_x11_proxy(connection: &TerminalProfileConnection) -> Result<Option<X11ProxyConfig>> {
    if !connection.x11_forwarding {
        return Ok(None);
    }
    if connection.x11_auth_protocol.as_bytes() != X11_AUTH_PROTOCOL {
        bail!("X11 forwarding only supports MIT-MAGIC-COOKIE-1 authentication");
    }
    let real_cookie = connection
        .x11_auth_cookie
        .as_deref()
        .filter(|cookie| !cookie.is_empty())
        .ok_or_else(|| {
            anyhow!("X11 forwarding requires an explicit local MIT-MAGIC-COOKIE-1 cookie")
        })
        .and_then(decode_x11_cookie)?;
    let target = resolve_x11_target(connection)
        .ok_or_else(|| anyhow!("X11 forwarding could not resolve a local X server target"))?;
    Ok(Some(X11ProxyConfig {
        target,
        fake_cookie: generate_x11_auth_cookie()?,
        real_cookie,
        connections: Arc::new(Semaphore::new(MAX_PENDING_X11_CONNECTIONS)),
    }))
}

fn decode_x11_cookie(cookie: &str) -> Result<[u8; 16]> {
    if cookie.len() != 32 || !cookie.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("X11 MIT-MAGIC-COOKIE-1 cookie must contain exactly 32 hexadecimal characters");
    }
    let mut decoded = [0_u8; 16];
    for (index, pair) in cookie.as_bytes().chunks_exact(2).enumerate() {
        let pair = std::str::from_utf8(pair).expect("ASCII hex cookie");
        decoded[index] = u8::from_str_radix(pair, 16)
            .map_err(|_| anyhow!("X11 cookie contains invalid hexadecimal data"))?;
    }
    Ok(decoded)
}

fn encode_x11_cookie(cookie: &[u8; 16]) -> String {
    cookie.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn resolve_x11_target(connection: &TerminalProfileConnection) -> Option<X11Target> {
    if !connection.x11_forwarding {
        return None;
    }
    if let Some(host) = connection
        .x11_target_host
        .as_deref()
        .filter(|host| !host.is_empty())
        && connection.x11_target_port != 0
    {
        return Some(X11Target::Tcp(host.to_string(), connection.x11_target_port));
    }
    std::env::var("DISPLAY")
        .ok()
        .as_deref()
        .and_then(x11_target_from_display)
        .or_else(|| Some(X11Target::Tcp("127.0.0.1".to_string(), 6000)))
}

fn x11_target_from_display(display: &str) -> Option<X11Target> {
    let display = display.trim();
    if display.is_empty() {
        return None;
    }
    #[cfg(unix)]
    if display.starts_with('/') {
        return Some(X11Target::Unix(PathBuf::from(display)));
    }
    let (host, display_number) = display.rsplit_once(':')?;
    let display_number = display_number
        .split_once('.')
        .map_or(display_number, |(display, _)| display)
        .parse::<u16>()
        .ok()?;
    if host.is_empty() || host.eq_ignore_ascii_case("unix") {
        #[cfg(unix)]
        return Some(X11Target::Unix(PathBuf::from(format!(
            "/tmp/.X11-unix/X{display_number}"
        ))));
        #[cfg(not(unix))]
        return Some(X11Target::Tcp(
            "127.0.0.1".to_string(),
            display_number.checked_add(6000)?,
        ));
    }
    let port = if display_number < 100 {
        display_number.checked_add(6000)?
    } else {
        display_number
    };
    Some(X11Target::Tcp(host.to_string(), port))
}

async fn start_local_forward_listeners(
    connection: &TerminalProfileConnection,
    sender: mpsc::Sender<AcceptedLocalForward>,
    forward_runtime: ForwardRuntime,
) -> Result<ForwardListenerTasks> {
    let mut tasks = Vec::new();
    for forward in connection.port_forwards.iter().filter(|forward| {
        matches!(
            forward.kind,
            TerminalSshPortForwardKind::Local | TerminalSshPortForwardKind::Dynamic
        )
    }) {
        let listener = TcpListener::bind((forward.bind_host.as_str(), forward.bind_port))
            .await
            .with_context(|| {
                format!(
                    "could not bind {:?} SSH forward on {}:{}",
                    forward.kind, forward.bind_host, forward.bind_port
                )
            })?;
        let sender = sender.clone();
        let forward = forward.clone();
        let listener_runtime = forward_runtime.clone();
        tasks.push(tokio::spawn(async move {
            loop {
                let Ok((mut stream, _)) = listener.accept().await else {
                    break;
                };
                let Some(permit) = listener_runtime.try_handshake_permit() else {
                    let _ = stream.shutdown().await;
                    continue;
                };
                let sender = sender.clone();
                let forward = forward.clone();
                let _ = listener_runtime.spawn_tracked(async move {
                    let _permit = permit;
                    let target = match forward.kind {
                        TerminalSshPortForwardKind::Local => {
                            Some((forward.target_host, forward.target_port, false))
                        }
                        TerminalSshPortForwardKind::Dynamic => tokio::time::timeout(
                            SOCKS_HANDSHAKE_TIMEOUT,
                            socks5_target(&mut stream),
                        )
                        .await
                        .ok()
                        .and_then(Result::ok)
                        .map(|(host, port)| (host, port, true)),
                        TerminalSshPortForwardKind::Remote => None,
                    };
                    let Some((target_host, target_port, socks5)) = target else {
                        let _ = send_socks_reply(&mut stream, 1).await;
                        return;
                    };
                    let _ = sender
                        .send(AcceptedLocalForward {
                            stream,
                            target_host,
                            target_port,
                            socks5,
                        })
                        .await;
                });
            }
        }));
    }
    Ok(ForwardListenerTasks(tasks))
}

async fn request_remote_forwards(
    session: &client::Handle<SshClientHandler>,
    connection: &TerminalProfileConnection,
) -> Result<()> {
    for forward in connection
        .port_forwards
        .iter()
        .filter(|forward| forward.kind == TerminalSshPortForwardKind::Remote)
    {
        session
            .tcpip_forward(forward.bind_host.clone(), u32::from(forward.bind_port))
            .await
            .with_context(|| {
                format!(
                    "server rejected remote forward {}:{}",
                    forward.bind_host, forward.bind_port
                )
            })?;
    }
    Ok(())
}

async fn socks5_target(stream: &mut TcpStream) -> Result<(String, u16)> {
    let mut greeting = [0_u8; 2];
    stream.read_exact(&mut greeting).await?;
    if greeting[0] != 5 {
        bail!("unsupported SOCKS version");
    }
    let mut methods = vec![0_u8; usize::from(greeting[1])];
    stream.read_exact(&mut methods).await?;
    if !methods.contains(&0) {
        stream.write_all(&[5, 0xff]).await?;
        bail!("SOCKS client does not support no-authentication mode");
    }
    stream.write_all(&[5, 0]).await?;

    let mut request = [0_u8; 4];
    stream.read_exact(&mut request).await?;
    if request[0] != 5 || request[1] != 1 {
        bail!("only SOCKS5 CONNECT is supported");
    }
    let host = match request[3] {
        1 => {
            let mut address = [0_u8; 4];
            stream.read_exact(&mut address).await?;
            std::net::Ipv4Addr::from(address).to_string()
        }
        3 => {
            let length = stream.read_u8().await?;
            let mut domain = vec![0_u8; usize::from(length)];
            stream.read_exact(&mut domain).await?;
            String::from_utf8(domain).context("SOCKS target domain is not UTF-8")?
        }
        4 => {
            let mut address = [0_u8; 16];
            stream.read_exact(&mut address).await?;
            std::net::Ipv6Addr::from(address).to_string()
        }
        _ => bail!("unsupported SOCKS address type"),
    };
    let port = stream.read_u16().await?;
    if host.is_empty() || port == 0 {
        bail!("invalid SOCKS target");
    }
    Ok((host, port))
}

async fn send_socks_reply<W>(stream: &mut W, status: u8) -> bool
where
    W: AsyncWrite + Unpin,
{
    stream
        .write_all(&[5, status, 0, 1, 0, 0, 0, 0, 0, 0])
        .await
        .is_ok()
}

struct ProxyCommandStream {
    process: Arc<tokio::sync::Mutex<TokioChild>>,
    lifetime: SshCancellation,
    _kill_task: tokio::task::JoinHandle<()>,
    stdin: ChildStdin,
    stdout: ChildStdout,
}

impl ProxyCommandStream {
    fn spawn(
        command: &str,
        connection: &TerminalProfileConnection,
        cancellation: SshCancellation,
    ) -> Result<Self> {
        let arguments = proxy_command_arguments(command, connection)
            .with_context(|| format!("invalid ProxyCommand syntax {command:?}"))?;
        let (program, arguments) = arguments
            .split_first()
            .ok_or_else(|| anyhow!("ProxyCommand is empty"))?;
        let mut command = Command::new(program);
        command
            .args(arguments)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .kill_on_drop(true);
        let mut child = command.spawn().context("could not start ProxyCommand")?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("ProxyCommand stdin is unavailable"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("ProxyCommand stdout is unavailable"))?;
        let process = Arc::new(tokio::sync::Mutex::new(child));
        cancellation.register_proxy_process(&process);
        let lifetime = SshCancellation::default();
        let kill_process = Arc::clone(&process);
        let kill_lifetime = lifetime.clone();
        let kill_task = tokio::spawn(async move {
            kill_lifetime.cancelled().await;
            let mut process = kill_process.lock().await;
            let _ = process.start_kill();
            let _ = process.wait().await;
        });
        Ok(Self {
            process,
            lifetime,
            _kill_task: kill_task,
            stdin,
            stdout,
        })
    }
}

impl Drop for ProxyCommandStream {
    fn drop(&mut self) {
        self.lifetime.cancel();
        // Keep one strong reference until the kill/reap task observes the
        // lifetime signal. This is intentionally not aborted on drop.
        let _ = &self.process;
    }
}

impl AsyncRead for ProxyCommandStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        context: &mut TaskContext<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<IoResult<()>> {
        Pin::new(&mut self.stdout).poll_read(context, buffer)
    }
}

impl AsyncWrite for ProxyCommandStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        context: &mut TaskContext<'_>,
        buffer: &[u8],
    ) -> Poll<IoResult<usize>> {
        Pin::new(&mut self.stdin).poll_write(context, buffer)
    }

    fn poll_flush(mut self: Pin<&mut Self>, context: &mut TaskContext<'_>) -> Poll<IoResult<()>> {
        Pin::new(&mut self.stdin).poll_flush(context)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        context: &mut TaskContext<'_>,
    ) -> Poll<IoResult<()>> {
        Pin::new(&mut self.stdin).poll_shutdown(context)
    }
}

fn expand_proxy_command(command: &str, connection: &TerminalProfileConnection) -> String {
    let mut expanded = String::with_capacity(command.len());
    let mut characters = command.chars();
    while let Some(character) = characters.next() {
        if character != '%' {
            expanded.push(character);
            continue;
        }
        match characters.next() {
            Some('%') => expanded.push('%'),
            Some('h' | 'H') => expanded.push_str(&connection.host),
            Some('p') => expanded.push_str(&connection.port.to_string()),
            Some('r') => expanded.push_str(&connection.user),
            Some(token) => {
                expanded.push('%');
                expanded.push(token);
            }
            None => expanded.push('%'),
        }
    }
    expanded
}

fn proxy_command_arguments(
    command: &str,
    connection: &TerminalProfileConnection,
) -> Result<Vec<String>> {
    shell_words::split(command)
        .map(|arguments| {
            arguments
                .into_iter()
                .map(|argument| expand_proxy_command(&argument, connection))
                .collect()
        })
        .map_err(Into::into)
}

async fn connect_transport(
    connection: &TerminalProfileConnection,
    interactions: &SshAuthClient,
    cancellation: &SshCancellation,
    x11_proxy: Option<X11ProxyConfig>,
    forward_runtime: &ForwardRuntime,
) -> Result<client::Handle<SshClientHandler>> {
    let config = client_config(connection);
    let handler = client_handler(
        connection,
        interactions.clone(),
        x11_proxy,
        forward_runtime.clone(),
    );
    let timeout = Duration::from_secs(connection.connect_timeout_seconds.clamp(1, 120));
    let connect = async {
        if let Some(proxy_command) = connection
            .proxy_command
            .as_deref()
            .filter(|value| !value.trim().is_empty())
        {
            let stream =
                ProxyCommandStream::spawn(proxy_command, connection, cancellation.clone())?;
            client::connect_stream(config, stream, handler).await
        } else {
            client::connect(config, (connection.host.as_str(), connection.port), handler).await
        }
    };
    tokio::time::timeout(timeout, connect)
        .await
        .map_err(|_| anyhow!("connection timed out after {} seconds", timeout.as_secs()))?
}

async fn connect_authenticated(
    connection: &TerminalProfileConnection,
    auth: &SshAuthClient,
    cancellation: &SshCancellation,
    x11_proxy: Option<X11ProxyConfig>,
    forward_runtime: &ForwardRuntime,
) -> Result<(
    client::Handle<SshClientHandler>,
    Vec<client::Handle<SshClientHandler>>,
)> {
    let proxy_jump = connection
        .proxy_jump
        .as_deref()
        .filter(|value| !value.trim().is_empty());
    if proxy_jump.is_some()
        && connection
            .proxy_command
            .as_deref()
            .is_some_and(|value| !value.trim().is_empty())
    {
        bail!("ProxyCommand and ProxyJump cannot be used together");
    }

    if let Some(proxy_jump) = proxy_jump {
        let jump_connections = proxy_jump_connections(connection, proxy_jump)?;
        let first_jump = jump_connections
            .first()
            .ok_or_else(|| anyhow!("ProxyJump chain is empty"))?;
        let mut current_session =
            connect_transport(first_jump, auth, cancellation, None, forward_runtime)
                .await
                .with_context(|| {
                    format!("could not connect to ProxyJump host {}", first_jump.host)
                })?;
        authenticate(&mut current_session, first_jump, auth)
            .await
            .with_context(|| {
                format!(
                    "could not authenticate to ProxyJump host {}",
                    first_jump.host
                )
            })?;
        let mut jump_sessions = Vec::with_capacity(jump_connections.len());

        for next_jump in jump_connections.iter().skip(1) {
            let jump_channel = current_session
                .channel_open_direct_tcpip(
                    next_jump.host.clone(),
                    u32::from(next_jump.port),
                    "127.0.0.1",
                    0,
                )
                .await
                .with_context(|| {
                    format!(
                        "ProxyJump host could not open a channel to {}:{}",
                        next_jump.host, next_jump.port
                    )
                })?;
            let mut next_session = connect_stream_with_timeout(
                next_jump,
                auth,
                jump_channel.into_stream(),
                None,
                forward_runtime,
            )
            .await
            .with_context(|| {
                format!(
                    "could not connect through ProxyJump host {}",
                    next_jump.host
                )
            })?;
            authenticate(&mut next_session, next_jump, auth)
                .await
                .with_context(|| {
                    format!(
                        "could not authenticate to ProxyJump host {}",
                        next_jump.host
                    )
                })?;
            jump_sessions.push(current_session);
            current_session = next_session;
        }

        let jump_channel = current_session
            .channel_open_direct_tcpip(
                connection.host.clone(),
                u32::from(connection.port),
                "127.0.0.1",
                0,
            )
            .await
            .with_context(|| {
                format!(
                    "ProxyJump host could not open a channel to {}:{}",
                    connection.host, connection.port
                )
            })?;
        let mut session = connect_stream_with_timeout(
            connection,
            auth,
            jump_channel.into_stream(),
            x11_proxy,
            forward_runtime,
        )
        .await
        .context("could not connect to destination through ProxyJump chain")?;
        authenticate(&mut session, connection, auth).await?;
        jump_sessions.push(current_session);
        return Ok((session, jump_sessions));
    }

    let mut session =
        connect_transport(connection, auth, cancellation, x11_proxy, forward_runtime).await?;
    authenticate(&mut session, connection, auth).await?;
    Ok((session, Vec::new()))
}

async fn connect_stream_with_timeout<S>(
    connection: &TerminalProfileConnection,
    auth: &SshAuthClient,
    stream: S,
    x11_proxy: Option<X11ProxyConfig>,
    forward_runtime: &ForwardRuntime,
) -> Result<client::Handle<SshClientHandler>>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let timeout = Duration::from_secs(connection.connect_timeout_seconds.clamp(1, 120));
    tokio::time::timeout(
        timeout,
        client::connect_stream(
            client_config(connection),
            stream,
            client_handler(connection, auth.clone(), x11_proxy, forward_runtime.clone()),
        ),
    )
    .await
    .map_err(|_| {
        anyhow!(
            "connection through ProxyJump timed out after {} seconds",
            timeout.as_secs()
        )
    })?
}

fn proxy_jump_connections(
    destination: &TerminalProfileConnection,
    value: &str,
) -> Result<Vec<TerminalProfileConnection>> {
    let value = value.trim();
    if value.is_empty() {
        bail!("ProxyJump host is empty");
    }
    let hops = value.split(',').map(str::trim).collect::<Vec<_>>();
    if !destination.proxy_jump_profiles.is_empty()
        && destination.proxy_jump_profiles.len() != hops.len()
    {
        bail!(
            "ProxyJump declares {} hops but {} independent jump profiles were provided",
            hops.len(),
            destination.proxy_jump_profiles.len()
        );
    }
    hops.into_iter()
        .enumerate()
        .map(|(index, hop)| {
            proxy_jump_connection(destination, hop, destination.proxy_jump_profiles.get(index))
        })
        .collect()
}

fn proxy_jump_connection(
    destination: &TerminalProfileConnection,
    value: &str,
    profile: Option<&TerminalSshJumpProfile>,
) -> Result<TerminalProfileConnection> {
    if value.is_empty() {
        bail!("ProxyJump host is empty");
    }
    let profile = profile.ok_or_else(|| {
        anyhow!(
            "ProxyJump host {value} requires an independent jump profile; destination credentials are never reused"
        )
    })?;
    let url = Url::parse(&format!("ssh://{value}"))
        .with_context(|| format!("invalid ProxyJump host {value:?}"))?;
    if url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !matches!(url.path(), "" | "/")
    {
        bail!("ProxyJump must use [user@]host[:port] syntax without embedded credentials");
    }
    let encoded_host = url
        .host_str()
        .filter(|host| !host.is_empty())
        .ok_or_else(|| anyhow!("ProxyJump host is missing"))?;
    let host = encoded_host
        .strip_prefix('[')
        .and_then(|host| host.strip_suffix(']'))
        .unwrap_or(encoded_host);
    let user = if url.username().is_empty() {
        (!profile.user.is_empty())
            .then(|| profile.user.clone())
            .or_else(|| std::env::var("USER").ok())
            .or_else(|| std::env::var("USERNAME").ok())
            .filter(|user| !user.is_empty())
            .ok_or_else(|| anyhow!("ProxyJump user is missing"))?
    } else {
        url.username().to_string()
    };
    if user.is_empty() {
        bail!("ProxyJump user is missing");
    }

    let mut jump = TerminalProfileConnection {
        connection_type: destination.connection_type,
        host: host.to_string(),
        user,
        port: url.port().unwrap_or(22),
        auth: TerminalSshAuthMethod::Auto,
        password: None,
        private_keys: Vec::new(),
        private_key_passphrase: None,
        host_key_policy: TerminalSshHostKeyPolicy::AcceptNew,
        known_hosts_file: None,
        connect_timeout_seconds: destination.connect_timeout_seconds,
        keepalive_seconds: destination.keepalive_seconds,
        keepalive_count_max: destination.keepalive_count_max,
        ..<_>::default()
    };
    if !profile.host.is_empty() {
        jump.host.clone_from(&profile.host);
    }
    if !profile.user.is_empty() {
        jump.user.clone_from(&profile.user);
    }
    if profile.port != 0 {
        jump.port = profile.port;
    }
    jump.auth = profile.auth;
    jump.password.clone_from(&profile.password);
    jump.private_keys.clone_from(&profile.private_keys);
    jump.private_key_passphrase
        .clone_from(&profile.private_key_passphrase);
    jump.host_key_policy = profile.host_key_policy;
    jump.known_hosts_file.clone_from(&profile.known_hosts_file);
    jump.connect_timeout_seconds = profile.connect_timeout_seconds;
    jump.keepalive_seconds = profile.keepalive_seconds;
    jump.keepalive_count_max = profile.keepalive_count_max;
    match jump.auth {
        TerminalSshAuthMethod::Password if jump.password.as_deref().unwrap_or("").is_empty() => {
            bail!("ProxyJump host {} has no independent password", jump.host)
        }
        TerminalSshAuthMethod::PublicKey if jump.private_keys.is_empty() => {
            bail!(
                "ProxyJump host {} has no independent private key",
                jump.host
            )
        }
        _ => {}
    }
    jump.proxy_command = None;
    jump.proxy_jump = None;
    jump.proxy_jump_profiles.clear();
    jump.port_forwards.clear();
    jump.agent_forwarding = false;
    jump.agent_socket = None;
    jump.x11_forwarding = false;
    jump.x11_target_host = None;
    jump.x11_target_port = 0;
    jump.x11_auth_cookie = None;
    Ok(jump)
}

async fn authenticate(
    session: &mut client::Handle<SshClientHandler>,
    connection: &TerminalProfileConnection,
    auth_client: &SshAuthClient,
) -> Result<()> {
    if session.authenticate_none(&connection.user).await?.success() {
        return Ok(());
    }

    let mut configured_key_loaded = false;
    if !matches!(
        connection.auth,
        TerminalSshAuthMethod::Password | TerminalSshAuthMethod::KeyboardInteractive
    ) {
        for configured_key in &connection.private_keys {
            let inline = looks_like_inline_private_key(configured_key);
            let expanded = (!inline).then(|| expand_identity_path(configured_key, connection));
            let key = match if inline {
                decode_private_key(configured_key, connection.private_key_passphrase.as_deref())
            } else {
                load_private_key(
                    expanded.as_deref().expect("path key must be expanded"),
                    connection.private_key_passphrase.as_deref(),
                )
            } {
                Ok(key) => key,
                Err(_) if connection.auth == TerminalSshAuthMethod::Auto => continue,
                Err(error) => {
                    return Err(error).with_context(|| {
                        expanded.as_ref().map_or_else(
                            || "could not decode saved private key".to_string(),
                            |path| format!("could not load private key {}", path.display()),
                        )
                    });
                }
            };
            configured_key_loaded = true;
            let result = session
                .authenticate_publickey(
                    &connection.user,
                    PrivateKeyWithHashAlg::new(
                        Arc::new(key),
                        session.best_supported_rsa_hash().await?.flatten(),
                    ),
                )
                .await?;
            if result.success() {
                return Ok(());
            }
        }
    }

    if connection.auth == TerminalSshAuthMethod::Auto
        && authenticate_with_agent(session, &connection.user).await?
    {
        return Ok(());
    }

    if matches!(
        connection.auth,
        TerminalSshAuthMethod::Auto | TerminalSshAuthMethod::Password
    ) && let Some(password) = connection.password.as_deref()
        && !password.is_empty()
        && session
            .authenticate_password(&connection.user, password)
            .await?
            .success()
    {
        return Ok(());
    }

    if matches!(
        connection.auth,
        TerminalSshAuthMethod::Auto | TerminalSshAuthMethod::Password
    ) && let Some(password) = connection.password.as_deref()
        && !password.is_empty()
        && authenticate_keyboard_interactive_with_password(session, &connection.user, password)
            .await?
    {
        return Ok(());
    }

    if connection.auth == TerminalSshAuthMethod::KeyboardInteractive
        && authenticate_keyboard_interactive_with_prompts(session, connection, auth_client).await?
    {
        return Ok(());
    }

    match connection.auth {
        TerminalSshAuthMethod::Password
            if connection.password.as_deref().unwrap_or("").is_empty() =>
        {
            bail!("password authentication selected, but no transient password was provided")
        }
        TerminalSshAuthMethod::PublicKey if connection.private_keys.is_empty() => {
            bail!("public-key authentication selected, but no private key was configured")
        }
        TerminalSshAuthMethod::PublicKey if !configured_key_loaded => {
            bail!("no configured private key could be loaded")
        }
        TerminalSshAuthMethod::KeyboardInteractive => {
            bail!("keyboard-interactive SSH authentication failed")
        }
        _ => bail!("SSH authentication failed"),
    }
}

async fn authenticate_keyboard_interactive_with_prompts(
    session: &mut client::Handle<SshClientHandler>,
    connection: &TerminalProfileConnection,
    auth_client: &SshAuthClient,
) -> Result<bool> {
    let mut response = session
        .authenticate_keyboard_interactive_start(&connection.user, None::<String>)
        .await?;
    for _ in 0..16 {
        match response {
            KeyboardInteractiveAuthResponse::Success => return Ok(true),
            KeyboardInteractiveAuthResponse::Failure { .. } => return Ok(false),
            KeyboardInteractiveAuthResponse::InfoRequest {
                name,
                instructions,
                prompts,
            } => {
                if prompts.is_empty() {
                    response = session
                        .authenticate_keyboard_interactive_respond(Vec::new())
                        .await?;
                    continue;
                }
                let responses = auth_client
                    .request(
                        connection,
                        name,
                        instructions,
                        prompts
                            .into_iter()
                            .map(|prompt| SshAuthPromptField {
                                prompt: prompt.prompt,
                                echo: prompt.echo,
                            })
                            .collect(),
                    )
                    .await?;
                response = session
                    .authenticate_keyboard_interactive_respond(responses)
                    .await?;
            }
        }
    }
    bail!("keyboard-interactive SSH authentication exceeded 16 challenge rounds")
}

#[cfg(unix)]
async fn authenticate_with_agent(
    session: &mut client::Handle<SshClientHandler>,
    user: &str,
) -> Result<bool> {
    let mut agent = match AgentClient::connect_env().await {
        Ok(agent) => agent,
        Err(_) => return Ok(false),
    };
    let identities = match agent.request_identities().await {
        Ok(identities) => identities,
        Err(_) => return Ok(false),
    };
    for identity in identities {
        let hash_algorithm = session.best_supported_rsa_hash().await?.flatten();
        let authenticated = match identity {
            AgentIdentity::PublicKey { key, .. } => session
                .authenticate_publickey_with(user, key, hash_algorithm, &mut agent)
                .await?
                .success(),
            AgentIdentity::Certificate { certificate, .. } => session
                .authenticate_certificate_with(user, certificate, hash_algorithm, &mut agent)
                .await?
                .success(),
        };
        if authenticated {
            return Ok(true);
        }
    }
    Ok(false)
}

#[cfg(not(unix))]
async fn authenticate_with_agent(
    _session: &mut client::Handle<SshClientHandler>,
    _user: &str,
) -> Result<bool> {
    Ok(false)
}

async fn authenticate_keyboard_interactive_with_password(
    session: &mut client::Handle<SshClientHandler>,
    user: &str,
    password: &str,
) -> Result<bool> {
    let mut response = session
        .authenticate_keyboard_interactive_start(user, None::<String>)
        .await?;
    for _ in 0..8 {
        match response {
            KeyboardInteractiveAuthResponse::Success => return Ok(true),
            KeyboardInteractiveAuthResponse::Failure { .. } => return Ok(false),
            KeyboardInteractiveAuthResponse::InfoRequest { prompts, .. } => {
                response = session
                    .authenticate_keyboard_interactive_respond(
                        prompts
                            .iter()
                            .map(|prompt| {
                                if prompt.echo {
                                    String::new()
                                } else {
                                    password.to_string()
                                }
                            })
                            .collect(),
                    )
                    .await?;
            }
        }
    }
    Ok(false)
}

fn load_private_key(path: &Path, passphrase: Option<&str>) -> Result<PrivateKey> {
    russh::keys::load_secret_key(path, passphrase).map_err(Into::into)
}

fn decode_private_key(value: &str, passphrase: Option<&str>) -> Result<PrivateKey> {
    russh::keys::decode_secret_key(value, passphrase).map_err(Into::into)
}

fn looks_like_inline_private_key(value: &str) -> bool {
    let trimmed = value.trim_start();
    trimmed.starts_with("-----BEGIN ") || trimmed.starts_with("PuTTY-User-Key-File-")
}

fn expand_identity_path(value: &str, connection: &TerminalProfileConnection) -> PathBuf {
    let expanded = value
        .replace("%h", &connection.host)
        .replace("%r", &connection.user)
        .replace("%p", &connection.port.to_string());
    expand_home_path(&expanded)
}

fn expand_home_path(value: &str) -> PathBuf {
    if let Some(relative) = value.strip_prefix("~/")
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(relative);
    }
    PathBuf::from(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::client::Handler as _;
    use russh_sftp::protocol::{Attrs, Data, Handle, OpenFlags, Status};

    #[test]
    fn remote_shell_probe_parses_supported_shells_and_rejects_commands() {
        for (program, kind) in [
            ("/bin/sh", RemoteShellKind::Sh),
            ("/usr/bin/dash", RemoteShellKind::Sh),
            ("/bin/bash", RemoteShellKind::Bash),
            ("/opt/homebrew/bin/zsh", RemoteShellKind::Zsh),
            ("/usr/local/bin/fish", RemoteShellKind::Fish),
            ("/usr/bin/nu", RemoteShellKind::Other),
        ] {
            let output = format!("login noise\n{REMOTE_SHELL_MARKER}{program}\n");
            let parsed = parse_remote_shell_program(&output).expect("shell program");
            assert_eq!(parsed, program);
            assert_eq!(remote_shell_kind(&parsed), kind);
        }

        assert!(parse_remote_shell_program("no marker").is_none());
        assert!(
            parse_remote_shell_program(&format!(
                "{REMOTE_SHELL_MARKER}/bin/zsh; touch /tmp/not-allowed\n"
            ))
            .is_none()
        );
    }

    #[test]
    fn remote_shell_capability_probes_are_shell_specific() {
        let zsh =
            remote_shell_capability_command(RemoteShellKind::Zsh, "/bin/zsh").expect("zsh probe");
        let bash = remote_shell_capability_command(RemoteShellKind::Bash, "/bin/bash")
            .expect("bash probe");
        let fish = remote_shell_capability_command(RemoteShellKind::Fish, "/bin/fish")
            .expect("fish probe");
        let sh = remote_shell_capability_command(RemoteShellKind::Sh, "/bin/sh").expect("sh probe");

        assert!(zsh.contains("autoload -Uz add-zsh-hook"));
        assert!(zsh.contains("command -v od"));
        assert!(bash.contains("--noprofile --norc"));
        assert!(bash.contains("command -v tr"));
        assert!(fish.contains("command -sq od"));
        assert!(fish.contains("--init-command"));
        assert!(sh.contains("command -v printf"));
        assert!(!sh.contains("command -v od"));
        assert!(remote_shell_capability_command(RemoteShellKind::Other, "/bin/nu").is_none());
    }

    #[test]
    fn remote_shell_launch_plans_use_native_startup_mechanisms() {
        let directory = "/tmp/ianvs-terminal-shell-test";
        let zsh = remote_shell_launch_command(RemoteShellKind::Zsh, "/bin/zsh", directory);
        let bash = remote_shell_launch_command(RemoteShellKind::Bash, "/bin/bash", directory);
        let fish = remote_shell_launch_command(RemoteShellKind::Fish, "/bin/fish", directory);
        let sh = remote_shell_launch_command(RemoteShellKind::Sh, "/bin/sh", directory);
        let other = remote_shell_launch_command(RemoteShellKind::Other, "/bin/nu", directory);

        assert!(zsh.contains("ZDOTDIR='/tmp/ianvs-terminal-shell-test'"));
        assert!(zsh.contains("IANVS_ORIGINAL_ZDOTDIR"));
        assert!(bash.contains("--rcfile '/tmp/ianvs-terminal-shell-test'/.bashrc -i"));
        assert!(fish.contains("--init-command"));
        assert!(fish.contains("IANVS_FISH_INIT"));
        assert!(sh.contains("ENV='/tmp/ianvs-terminal-shell-test'/init.sh"));
        assert!(sh.contains("IANVS_ORIGINAL_ENV"));
        assert_eq!(other, "exec '/bin/nu' -l");
    }

    #[test]
    fn remote_shell_hook_files_cover_full_and_basic_fallbacks() {
        let zsh = remote_shell_integration_files(RemoteShellKind::Zsh);
        assert_eq!(zsh.len(), 5);
        assert!(zsh.iter().any(|(name, _)| *name == ".zshrc"));

        let bash = remote_shell_integration_files(RemoteShellKind::Bash);
        assert!(bash[0].1.contains("PROMPT_COMMAND"));
        assert!(bash[0].1.contains("command_finished"));
        assert!(bash[0].1.contains("/etc/profile"));
        assert!(bash[0].1.contains(".bash_profile"));

        let fish = remote_shell_integration_files(RemoteShellKind::Fish);
        assert!(fish[0].1.contains("fish_preexec"));
        assert!(fish[0].1.contains("fish_prompt"));

        let sh = remote_shell_integration_files(RemoteShellKind::Sh);
        assert!(sh[0].1.contains("PS1="));
        assert!(sh[0].1.contains("file://"));

        assert!(remote_shell_integration_files(RemoteShellKind::Other).is_empty());
    }

    struct InMemorySftpServer {
        files: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    }

    impl russh_sftp::server::Handler for InMemorySftpServer {
        type Error = SftpStatusCode;

        fn unimplemented(&self) -> Self::Error {
            SftpStatusCode::OpUnsupported
        }

        async fn open(
            &mut self,
            id: u32,
            filename: String,
            pflags: OpenFlags,
            _attrs: SftpFileAttributes,
        ) -> std::result::Result<Handle, Self::Error> {
            let mut files = self.files.lock();
            if pflags.contains(OpenFlags::TRUNCATE) {
                files.insert(filename.clone(), Vec::new());
            } else if pflags.contains(OpenFlags::CREATE) {
                files.entry(filename.clone()).or_default();
            } else if !files.contains_key(&filename) {
                return Err(SftpStatusCode::NoSuchFile);
            }
            Ok(Handle {
                id,
                handle: filename,
            })
        }

        async fn close(
            &mut self,
            id: u32,
            _handle: String,
        ) -> std::result::Result<Status, Self::Error> {
            Ok(sftp_ok_status(id))
        }

        async fn read(
            &mut self,
            id: u32,
            handle: String,
            offset: u64,
            len: u32,
        ) -> std::result::Result<Data, Self::Error> {
            let files = self.files.lock();
            let data = files.get(&handle).ok_or(SftpStatusCode::NoSuchFile)?;
            let offset = usize::try_from(offset).map_err(|_| SftpStatusCode::Failure)?;
            if offset >= data.len() {
                return Err(SftpStatusCode::Eof);
            }
            let end = offset.saturating_add(len as usize).min(data.len());
            Ok(Data {
                id,
                data: data[offset..end].to_vec(),
            })
        }

        async fn write(
            &mut self,
            id: u32,
            handle: String,
            offset: u64,
            data: Vec<u8>,
        ) -> std::result::Result<Status, Self::Error> {
            let mut files = self.files.lock();
            let file = files.get_mut(&handle).ok_or(SftpStatusCode::NoSuchFile)?;
            let offset = usize::try_from(offset).map_err(|_| SftpStatusCode::Failure)?;
            let end = offset
                .checked_add(data.len())
                .ok_or(SftpStatusCode::Failure)?;
            if file.len() < end {
                file.resize(end, 0);
            }
            file[offset..end].copy_from_slice(&data);
            Ok(sftp_ok_status(id))
        }

        async fn stat(&mut self, id: u32, path: String) -> std::result::Result<Attrs, Self::Error> {
            let files = self.files.lock();
            let data = files.get(&path).ok_or(SftpStatusCode::NoSuchFile)?;
            Ok(Attrs {
                id,
                attrs: SftpFileAttributes {
                    size: Some(data.len() as u64),
                    permissions: Some(0o100640),
                    ..SftpFileAttributes::empty()
                },
            })
        }

        async fn fsetstat(
            &mut self,
            id: u32,
            _handle: String,
            _attrs: SftpFileAttributes,
        ) -> std::result::Result<Status, Self::Error> {
            Ok(sftp_ok_status(id))
        }

        async fn rename(
            &mut self,
            id: u32,
            oldpath: String,
            newpath: String,
        ) -> std::result::Result<Status, Self::Error> {
            let mut files = self.files.lock();
            let data = files.remove(&oldpath).ok_or(SftpStatusCode::NoSuchFile)?;
            files.insert(newpath, data);
            Ok(sftp_ok_status(id))
        }

        async fn remove(
            &mut self,
            id: u32,
            filename: String,
        ) -> std::result::Result<Status, Self::Error> {
            self.files
                .lock()
                .remove(&filename)
                .ok_or(SftpStatusCode::NoSuchFile)?;
            Ok(sftp_ok_status(id))
        }
    }

    fn sftp_ok_status(id: u32) -> Status {
        Status {
            id,
            status_code: SftpStatusCode::Ok,
            error_message: "Ok".to_string(),
            language_tag: "en-US".to_string(),
        }
    }

    const HOST_KEY_A: &str =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ4884pTXCgmNvR/oiWTLe71HqB0p1+KknbHps1cKMjH";
    const HOST_KEY_B: &str =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJjiMNIEhO7sPT1lCPs1wEFqf56/HrFkV3+PbB7g04C";

    fn wait_for_child_exit(child: &mut dyn Child, timeout: Duration) -> ExitStatus {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            if let Some(status) = child.try_wait().expect("SSH child status") {
                return status;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "SSH child did not exit before the cancellation deadline"
            );
            thread::sleep(Duration::from_millis(10));
        }
    }

    #[test]
    fn keyboard_interactive_timeout_matches_openssh_default_login_grace_time() {
        assert_eq!(SSH_AUTH_INTERACTION_TIMEOUT, Duration::from_secs(120));
    }

    #[test]
    fn sftp_client_enqueues_directory_work_without_blocking_the_caller() {
        let (sender, mut commands) = mpsc::unbounded_channel();
        let client = SshSftpClient { sender };

        let receiver = client
            .start_list_directory("/srv/app".to_string())
            .expect("enqueue directory request");
        let command = commands.try_recv().expect("queued SFTP command");
        let SshCommand::ListDirectory { path, response } = command else {
            panic!("expected an SFTP directory command");
        };
        assert_eq!(path, "/srv/app");
        response
            .send(Ok(SftpDirectoryListing {
                path,
                entries: Vec::new(),
            }))
            .expect("deliver directory response");
        assert!(
            receiver
                .blocking_recv()
                .expect("receive directory response")
                .is_ok()
        );
    }

    #[test]
    fn sftp_file_transfer_round_trips_through_the_protocol() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("SFTP transfer test runtime");
        runtime.block_on(async {
            let files = Arc::new(Mutex::new(HashMap::from([(
                "/remote.txt".to_string(),
                b"remote-before\n".to_vec(),
            )])));
            let (client_stream, server_stream) = tokio::io::duplex(1024 * 1024);
            let server = tokio::spawn(russh_sftp::server::run(
                server_stream,
                InMemorySftpServer {
                    files: Arc::clone(&files),
                },
            ));
            let sftp = SftpSession::new_with_config(
                SftpPacketLengthLimitedStream::new(client_stream, MAX_SFTP_INBOUND_PACKET_BYTES),
                SftpConfig {
                    max_packet_len: MAX_SFTP_INBOUND_PACKET_BYTES,
                    request_timeout_secs: 10,
                    ..SftpConfig::default()
                },
            )
            .await
            .expect("initialize in-memory SFTP client");
            let scratch = tempfile::tempdir().expect("local SFTP scratch directory");
            let local_path = scratch.path().join("remote.txt");
            let cancellation = SftpOperationCancellation::new();

            download_sftp_file(
                &sftp,
                "/remote.txt",
                &local_path.to_string_lossy(),
                &cancellation,
            )
            .await
            .expect("download remote fixture");
            assert_eq!(
                fs::read(&local_path).expect("read local SFTP download"),
                b"remote-before\n"
            );

            fs::write(&local_path, b"local-after\n").expect("write local SFTP edit");
            upload_sftp_file(
                None,
                &sftp,
                &local_path.to_string_lossy(),
                "/remote.txt",
                &cancellation,
            )
            .await
            .expect("upload local edit");
            assert_eq!(
                files.lock().get("/remote.txt").cloned(),
                Some(b"local-after\n".to_vec())
            );
            upload_sftp_file(
                None,
                &sftp,
                &local_path.to_string_lossy(),
                "/created.txt",
                &cancellation,
            )
            .await
            .expect("upload a new remote file");
            assert_eq!(
                files.lock().get("/created.txt").cloned(),
                Some(b"local-after\n".to_vec())
            );
            files
                .lock()
                .insert("/remote.txt".to_string(), b"remote-second\n".to_vec());
            download_sftp_file(
                &sftp,
                "/remote.txt",
                &local_path.to_string_lossy(),
                &cancellation,
            )
            .await
            .expect("atomically replace an existing local download");
            assert_eq!(
                fs::read(&local_path).expect("read replaced local SFTP download"),
                b"remote-second\n"
            );
            assert!(
                files.lock().keys().all(|path| !path.contains(".ianvs-")),
                "successful upload must remove its remote staging and backup files"
            );
            let _ = sftp.close().await;
            server.await.expect("in-memory SFTP server task");
        });
    }

    #[test]
    fn dropping_sftp_receiver_cancels_queued_directory_work() {
        let (sender, mut commands) = mpsc::unbounded_channel();
        let client = SshSftpClient { sender };

        let receiver = client
            .start_list_directory("/srv/app".to_string())
            .expect("enqueue directory request");
        let command = commands.try_recv().expect("queued SFTP command");
        let SshCommand::ListDirectory { response, .. } = command else {
            panic!("expected an SFTP directory command");
        };

        drop(receiver);
        assert!(response.is_closed());
    }

    #[test]
    fn dropping_sftp_operation_receiver_cancels_queued_work() {
        let (sender, mut commands) = mpsc::unbounded_channel();
        let client = SshSftpClient { sender };

        let receiver = client
            .start_operation(SftpOperation::DeleteEntry {
                path: "/srv/app/stale.log".to_string(),
                is_directory: false,
            })
            .expect("enqueue SFTP operation");
        let command = commands.try_recv().expect("queued SFTP operation");
        let SshCommand::SftpOperation { response, .. } = command else {
            panic!("expected an SFTP operation command");
        };

        drop(receiver);
        assert!(response.is_closed());
    }

    #[test]
    fn sftp_operation_cancellation_interrupts_a_pending_step() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let cancellation = SftpOperationCancellation::new();
            let pending =
                sftp_operation_step::<(), IoError, _>(&cancellation, std::future::pending());
            tokio::pin!(pending);
            cancellation.cancel();

            let error = pending.await.expect_err("cancellation must win");
            assert!(error.to_string().contains("cancelled"));
        });
    }

    #[test]
    fn sftp_session_cancellation_reaches_running_child_operations() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let root = SftpOperationCancellation::new();
            let child = root.child();
            let pending = sftp_operation_step::<(), IoError, _>(&child, std::future::pending());
            tokio::pin!(pending);
            root.cancel();

            let error = pending.await.expect_err("root cancellation must win");
            assert!(error.to_string().contains("cancelled"));
        });
    }

    #[test]
    fn sftp_scope_errors_still_cancel_and_drain_running_operations() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let root = SftpOperationCancellation::new();
            let child = root.child();
            let cleaned = Arc::new(AtomicBool::new(false));
            let cleaned_by_request = Arc::clone(&cleaned);
            let mut requests: FuturesUnordered<BoxFuture<'_, ()>> = FuturesUnordered::new();
            requests.push(Box::pin(async move {
                child.cancelled().await;
                cleaned_by_request.store(true, Ordering::SeqCst);
            }));

            let error = finish_sftp_request_scope::<()>(
                Err(anyhow!("shell channel write failed")),
                &root,
                &mut requests,
            )
            .await
            .expect_err("the shell error must survive cleanup");

            assert!(error.to_string().contains("shell channel write failed"));
            assert!(cleaned.load(Ordering::SeqCst));
            assert!(requests.is_empty());
        });
    }

    #[test]
    fn sftp_directory_wire_budget_rejects_escape_amplification() {
        let entry = SftpDirectoryEntry {
            name: "\\\"".repeat(MAX_SFTP_ENTRY_NAME_BYTES),
            kind: "file",
            size_bytes: Some(1),
            modified_at_epoch_seconds: None,
            permissions: Some("-rw-r--r--".to_string()),
        };
        let encoded_entry_size = serde_json::to_vec(&entry).unwrap().len();
        assert!(encoded_entry_size > entry.name.len());

        let mut wire_bytes = MAX_SFTP_DIRECTORY_WIRE_BYTES - encoded_entry_size;
        assert!(reserve_sftp_entry_wire_bytes(&mut wire_bytes, &entry).is_err());
    }

    #[test]
    fn sftp_entry_names_cannot_escape_a_local_edit_directory() {
        assert!(is_valid_sftp_entry_name("deploy.log"));
        assert!(!is_valid_sftp_entry_name("../deploy.log"));
        assert!(!is_valid_sftp_entry_name("..\\deploy.log"));
        assert!(!is_valid_sftp_entry_name("."));
        assert!(!is_valid_sftp_entry_name(".."));
    }

    #[test]
    fn sftp_stream_rejects_oversized_frame_before_reading_its_payload() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let (mut remote, transport) = tokio::io::duplex(16);
            remote
                .write_all(&(MAX_SFTP_INBOUND_PACKET_BYTES + 1).to_be_bytes())
                .await
                .expect("write forged SFTP prefix");
            let mut limited =
                SftpPacketLengthLimitedStream::new(transport, MAX_SFTP_INBOUND_PACKET_BYTES);
            let mut prefix = [0; 4];

            let error = limited
                .read_exact(&mut prefix)
                .await
                .expect_err("oversized prefix must fail without a payload");

            assert_eq!(error.kind(), ErrorKind::InvalidData);

            let terminal_error = limited
                .read_exact(&mut prefix)
                .await
                .expect_err("rejected SFTP stream must terminate on the next read");
            assert_eq!(terminal_error.kind(), ErrorKind::UnexpectedEof);
        });
    }

    #[test]
    fn sftp_stream_preserves_a_frame_within_the_inbound_limit() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let (mut remote, transport) = tokio::io::duplex(16);
            remote
                .write_all(&[0, 0, 0, 1, 0x7f])
                .await
                .expect("write bounded SFTP frame");
            let mut limited = SftpPacketLengthLimitedStream::new(transport, 1);
            let mut frame = [0; 5];

            limited
                .read_exact(&mut frame)
                .await
                .expect("bounded SFTP frame");

            assert_eq!(frame, [0, 0, 0, 1, 0x7f]);
        });
    }

    #[test]
    fn ssh_setup_timeout_restarts_after_an_interactive_prompt() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let auth = SshAuthClient::default();
            let setup_auth = auth.clone();
            let cancellation = SshCancellation::default();
            let setup = async move {
                let interaction = setup_auth.begin_interaction();
                tokio::time::sleep(Duration::from_millis(150)).await;
                drop(interaction);
                tokio::time::sleep(Duration::from_millis(80)).await;
                Ok(())
            };

            await_ssh_setup(setup, Duration::from_millis(200), &auth, &cancellation)
                .await
                .expect("interactive input should not consume the setup timeout");
        });
    }

    #[test]
    fn ssh_setup_still_times_out_without_an_interactive_prompt() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let auth = SshAuthClient::default();
            let cancellation = SshCancellation::default();
            let error = await_ssh_setup(
                std::future::pending::<Result<()>>(),
                Duration::from_millis(20),
                &auth,
                &cancellation,
            )
            .await
            .expect_err("non-interactive setup should remain bounded");

            assert!(
                error
                    .to_string()
                    .contains("SSH initialization timed out after")
            );
        });
    }

    #[test]
    fn host_key_policy_accepts_new_and_prompts_for_strict_or_changed() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let directory = tempfile::tempdir().expect("known-hosts directory");
            let known_hosts = directory.path().join("known_hosts");
            let key_a =
                russh::keys::ssh_key::PublicKey::from_openssh(HOST_KEY_A).expect("first host key");
            let key_b = russh::keys::ssh_key::PublicKey::from_openssh(HOST_KEY_B)
                .expect("replacement host key");
            let interactions = SshAuthClient::default();
            let forward_runtime = ForwardRuntime::new(SshCancellation::default());

            let accept_new = TerminalProfileConnection {
                host: "host.example.test".to_string(),
                port: 2222,
                host_key_policy: TerminalSshHostKeyPolicy::AcceptNew,
                known_hosts_file: Some(known_hosts.to_string_lossy().into_owned()),
                ..<_>::default()
            };
            let mut handler = client_handler(
                &accept_new,
                interactions.clone(),
                None,
                forward_runtime.clone(),
            );
            assert!(handler.check_server_key(&key_a).await.unwrap());
            assert!(interactions.take_host_key_prompts().is_empty());
            assert!(
                russh::keys::known_hosts::check_known_hosts_path(
                    &accept_new.host,
                    accept_new.port,
                    &key_a,
                    &known_hosts,
                )
                .unwrap()
            );

            let strict_path = directory.path().join("strict_known_hosts");
            let strict = TerminalProfileConnection {
                host: "strict.example.test".to_string(),
                port: 22,
                host_key_policy: TerminalSshHostKeyPolicy::Strict,
                known_hosts_file: Some(strict_path.to_string_lossy().into_owned()),
                ..<_>::default()
            };
            let strict_interactions = SshAuthClient::default();
            let mut strict_handler = client_handler(
                &strict,
                strict_interactions.clone(),
                None,
                forward_runtime.clone(),
            );
            let strict_key = key_a.clone();
            let strict_task =
                tokio::spawn(async move { strict_handler.check_server_key(&strict_key).await });
            let strict_prompt = tokio::time::timeout(Duration::from_secs(1), async {
                loop {
                    if let Some(prompt) = strict_interactions.take_host_key_prompts().pop() {
                        break prompt;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("strict host-key prompt");
            assert!(matches!(
                strict_prompt.reason,
                SshHostKeyPromptReason::Unknown
            ));
            assert!(strict_prompt.fingerprint.starts_with("SHA256:"));
            assert!(strict_interactions.respond_host_key(strict_prompt.challenge_id, true));
            assert!(strict_task.await.unwrap().unwrap());
            assert!(
                russh::keys::known_hosts::check_known_hosts_path(
                    &strict.host,
                    strict.port,
                    &key_a,
                    &strict_path,
                )
                .unwrap()
            );

            let changed_interactions = SshAuthClient::default();
            fs::write(
                &known_hosts,
                format!(
                    "[host.example.test]:2222,[alias.example.test]:2222 {}\n",
                    key_a.to_openssh().expect("stored key")
                ),
            )
            .expect("multi-host known_hosts entry");
            assert!(
                russh::keys::known_hosts::check_known_hosts_path(
                    &accept_new.host,
                    accept_new.port,
                    &key_a,
                    &known_hosts,
                )
                .expect("stored multi-host key")
            );
            assert!(matches!(
                russh::keys::known_hosts::check_known_hosts_path(
                    &accept_new.host,
                    accept_new.port,
                    &key_b,
                    &known_hosts,
                ),
                Err(russh::keys::Error::KeyChanged { .. })
            ));
            let mut changed_handler = client_handler(
                &accept_new,
                changed_interactions.clone(),
                None,
                forward_runtime.clone(),
            );
            let changed_key = key_b.clone();
            let changed_task =
                tokio::spawn(async move { changed_handler.check_server_key(&changed_key).await });
            let changed_prompt = tokio::time::timeout(Duration::from_secs(1), async {
                loop {
                    if let Some(prompt) = changed_interactions.take_host_key_prompts().pop() {
                        break prompt;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("changed host-key prompt");
            assert!(matches!(
                changed_prompt.reason,
                SshHostKeyPromptReason::Changed
            ));
            assert!(changed_interactions.respond_host_key(changed_prompt.challenge_id, true));
            assert!(changed_task.await.unwrap().unwrap());
            assert!(
                russh::keys::known_hosts::check_known_hosts_path(
                    &accept_new.host,
                    accept_new.port,
                    &key_b,
                    &known_hosts,
                )
                .unwrap()
            );
            let replaced = fs::read_to_string(&known_hosts).expect("replaced known_hosts");
            assert!(replaced.starts_with("[host.example.test]:2222 "));
            assert!(!replaced.contains("alias.example.test"));
        });
    }

    #[test]
    fn identity_tokens_are_expanded() {
        let connection = TerminalProfileConnection {
            host: "example.test".to_string(),
            user: "ianvs".to_string(),
            port: 2222,
            ..<_>::default()
        };
        assert_eq!(
            expand_identity_path("/keys/%r-%h-%p", &connection),
            PathBuf::from("/keys/ianvs-example.test-2222")
        );
    }

    #[test]
    fn proxy_command_placeholders_cannot_inject_additional_arguments() {
        let connection = TerminalProfileConnection {
            host: "target host --unexpected-option".to_string(),
            user: "remote user".to_string(),
            port: 2222,
            ..<_>::default()
        };
        assert_eq!(
            proxy_command_arguments("proxy --host %h --user '%r' --port %p", &connection)
                .expect("ProxyCommand arguments"),
            vec![
                "proxy",
                "--host",
                "target host --unexpected-option",
                "--user",
                "remote user",
                "--port",
                "2222",
            ]
        );
    }

    #[test]
    fn proxy_jump_uses_only_its_independent_credentials() {
        let destination = TerminalProfileConnection {
            host: "target.internal".to_string(),
            user: "target-user".to_string(),
            port: 2222,
            auth: TerminalSshAuthMethod::Password,
            password: Some("target-secret".to_string()),
            private_keys: vec!["/keys/target".to_string()],
            proxy_command: Some("must-not-leak-to-jump".to_string()),
            proxy_jump: Some("jump-user@[2001:db8::7]:2200".to_string()),
            ..<_>::default()
        };
        let profile = TerminalSshJumpProfile {
            auth: TerminalSshAuthMethod::Password,
            password: Some("jump-secret".to_string()),
            private_keys: vec!["/keys/jump".to_string()],
            ..<_>::default()
        };

        let jump = proxy_jump_connection(
            &destination,
            destination.proxy_jump.as_deref().expect("proxy jump"),
            Some(&profile),
        )
        .expect("valid proxy jump");

        assert_eq!(jump.host, "2001:db8::7");
        assert_eq!(jump.user, "jump-user");
        assert_eq!(jump.port, 2200);
        assert_eq!(jump.auth, TerminalSshAuthMethod::Password);
        assert_eq!(jump.password.as_deref(), Some("jump-secret"));
        assert_eq!(jump.private_keys, vec!["/keys/jump"]);
        assert_ne!(jump.password, destination.password);
        assert!(!jump.private_keys.contains(&"/keys/target".to_string()));
        assert!(jump.proxy_command.is_none());
        assert!(jump.proxy_jump.is_none());
    }

    #[test]
    fn proxy_jump_rejects_implicit_destination_secrets() {
        for auth in [
            TerminalSshAuthMethod::Auto,
            TerminalSshAuthMethod::Password,
            TerminalSshAuthMethod::PublicKey,
            TerminalSshAuthMethod::KeyboardInteractive,
        ] {
            let destination = TerminalProfileConnection {
                user: "target-user".to_string(),
                auth,
                password: Some("target-secret".to_string()),
                private_keys: vec!["/keys/target".to_string()],
                ..<_>::default()
            };
            let error = proxy_jump_connection(&destination, "jump.internal", None).unwrap_err();
            assert!(error.to_string().contains("independent jump profile"));
        }
    }

    #[test]
    fn proxy_jump_defaults_user_and_port_and_parses_chains() {
        let mut destination = TerminalProfileConnection {
            user: "ianvs".to_string(),
            ..<_>::default()
        };
        let jump_profile = TerminalSshJumpProfile {
            user: "ianvs".to_string(),
            ..<_>::default()
        };
        let jump = proxy_jump_connection(&destination, "jump.internal", Some(&jump_profile))
            .expect("defaulted proxy jump");
        assert_eq!(jump.host, "jump.internal");
        assert_eq!(jump.user, "ianvs");
        assert_eq!(jump.port, 22);
        destination.proxy_jump_profiles = vec![TerminalSshJumpProfile::default(); 3];
        let chain = proxy_jump_connections(
            &destination,
            "first, hop-user@second:2222, [2001:db8::2]:2200",
        )
        .expect("valid ProxyJump chain");
        assert_eq!(chain.len(), 3);
        assert_eq!(chain[0].host, "first");
        assert_eq!(chain[1].host, "second");
        assert_eq!(chain[1].user, "hop-user");
        assert_eq!(chain[1].port, 2222);
        assert_eq!(chain[2].host, "2001:db8::2");
        assert_eq!(chain[2].port, 2200);
        assert!(proxy_jump_connections(&destination, "first,,second").is_err());
    }

    #[test]
    fn x11_display_resolves_tcp_and_unix_targets_like_tabby() {
        assert_eq!(
            x11_target_from_display("localhost:2.0"),
            Some(X11Target::Tcp("localhost".to_string(), 6002))
        );
        assert_eq!(
            x11_target_from_display("display.example.test:6010"),
            Some(X11Target::Tcp("display.example.test".to_string(), 6010))
        );
        #[cfg(unix)]
        {
            assert_eq!(
                x11_target_from_display(":3"),
                Some(X11Target::Unix(PathBuf::from("/tmp/.X11-unix/X3")))
            );
            assert_eq!(
                x11_target_from_display("/private/tmp/x11.sock"),
                Some(X11Target::Unix(PathBuf::from("/private/tmp/x11.sock")))
            );
        }
        assert!(x11_target_from_display("not-a-display").is_none());
    }

    #[test]
    fn generated_x11_cookie_is_a_fresh_hex_token() {
        let first = generate_x11_auth_cookie().expect("X11 cookie");
        let second = generate_x11_auth_cookie().expect("X11 cookie");
        let encoded = encode_x11_cookie(&first);
        assert_eq!(encoded.len(), 32);
        assert!(encoded.bytes().all(|byte| byte.is_ascii_hexdigit()));
        assert_eq!(decode_x11_cookie(&encoded).expect("decode cookie"), first);
        assert_ne!(first, second);
    }

    fn x11_setup(byte_order: u8, cookie: &[u8; 16]) -> Vec<u8> {
        let encode_u16 = |value: u16| match byte_order {
            b'l' => value.to_le_bytes(),
            b'B' => value.to_be_bytes(),
            _ => value.to_le_bytes(),
        };
        let mut setup = vec![byte_order, 0];
        setup.extend_from_slice(&encode_u16(11));
        setup.extend_from_slice(&encode_u16(0));
        setup.extend_from_slice(&encode_u16(X11_AUTH_PROTOCOL.len() as u16));
        setup.extend_from_slice(&encode_u16(cookie.len() as u16));
        setup.extend_from_slice(&[0, 0]);
        setup.extend_from_slice(X11_AUTH_PROTOCOL);
        setup.extend_from_slice(&[0, 0]);
        setup.extend_from_slice(cookie);
        setup
    }

    #[test]
    fn x11_setup_proxy_validates_fake_and_substitutes_real_cookie() {
        let fake = [0x11; 16];
        let real = [0xa5; 16];
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            for byte_order in [b'l', b'B'] {
                let (mut remote_writer, mut remote_reader) = tokio::io::duplex(256);
                let (mut local_writer, mut local_reader) = tokio::io::duplex(256);
                remote_writer
                    .write_all(&x11_setup(byte_order, &fake))
                    .await
                    .expect("remote setup");
                rewrite_x11_setup(&mut remote_reader, &mut local_writer, &fake, &real)
                    .await
                    .expect("rewrite setup");
                drop(local_writer);
                let mut forwarded = Vec::new();
                local_reader
                    .read_to_end(&mut forwarded)
                    .await
                    .expect("forwarded setup");
                assert_eq!(forwarded, x11_setup(byte_order, &real));
            }
        });
    }

    #[test]
    fn x11_setup_proxy_rejects_invalid_order_lengths_protocol_and_cookie() {
        let fake = [0x11; 16];
        let real = [0xa5; 16];
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let mut invalid_order = x11_setup(b'?', &fake);
            let (mut writer, mut reader) = tokio::io::duplex(256);
            let (mut local, _local_reader) = tokio::io::duplex(256);
            writer.write_all(&invalid_order).await.expect("setup");
            assert!(
                rewrite_x11_setup(&mut reader, &mut local, &fake, &real)
                    .await
                    .expect_err("invalid byte order")
                    .to_string()
                    .contains("byte order")
            );

            invalid_order[0] = b'l';
            invalid_order[6..8].copy_from_slice(&5000_u16.to_le_bytes());
            let (mut writer, mut reader) = tokio::io::duplex(256);
            let (mut local, _local_reader) = tokio::io::duplex(256);
            writer
                .write_all(&invalid_order[..12])
                .await
                .expect("header");
            assert!(
                rewrite_x11_setup(&mut reader, &mut local, &fake, &real)
                    .await
                    .expect_err("oversized setup")
                    .to_string()
                    .contains("too large")
            );

            let mut wrong_protocol = x11_setup(b'l', &fake);
            wrong_protocol[12..12 + X11_AUTH_PROTOCOL.len()].fill(b'X');
            let (mut writer, mut reader) = tokio::io::duplex(256);
            let (mut local, _local_reader) = tokio::io::duplex(256);
            writer
                .write_all(&wrong_protocol)
                .await
                .expect("wrong protocol");
            assert!(
                rewrite_x11_setup(&mut reader, &mut local, &fake, &real)
                    .await
                    .expect_err("wrong protocol")
                    .to_string()
                    .contains("protocol")
            );

            let (mut writer, mut reader) = tokio::io::duplex(256);
            let (mut local, _local_reader) = tokio::io::duplex(256);
            writer
                .write_all(&x11_setup(b'l', &[0x22; 16]))
                .await
                .expect("wrong cookie");
            assert!(
                rewrite_x11_setup(&mut reader, &mut local, &fake, &real)
                    .await
                    .expect_err("wrong cookie")
                    .to_string()
                    .contains("cookie mismatch")
            );
        });
    }

    #[test]
    fn x11_setup_proxy_times_out_a_silent_remote_before_forwarding() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let (_silent_writer, mut remote_reader) = tokio::io::duplex(256);
            let (mut local_writer, mut local_reader) = tokio::io::duplex(256);
            let error = rewrite_x11_setup_with_timeout(
                &mut remote_reader,
                &mut local_writer,
                &[0x11; 16],
                &[0xa5; 16],
                Duration::from_millis(25),
            )
            .await
            .expect_err("silent X11 peer must time out");
            assert!(error.to_string().contains("timed out"));
            drop(local_writer);
            let mut forwarded = Vec::new();
            local_reader
                .read_to_end(&mut forwarded)
                .await
                .expect("local stream");
            assert!(forwarded.is_empty());
        });
    }

    #[test]
    fn x11_forwarding_fails_closed_without_an_explicit_real_cookie() {
        let connection = TerminalProfileConnection {
            x11_forwarding: true,
            x11_target_host: Some("127.0.0.1".to_string()),
            x11_target_port: 6000,
            ..<_>::default()
        };
        let error = build_x11_proxy(&connection)
            .err()
            .expect("missing X11 cookie must fail closed");
        assert!(error.to_string().contains("explicit local"));
    }

    #[test]
    fn a_reset_during_the_socks_success_reply_is_connection_scoped() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let (mut server, client) = tokio::io::duplex(64);
            drop(client);
            assert!(
                !send_socks_reply(&mut server, 0).await,
                "a reset success reply must be reported without propagating an error"
            );
        });
    }

    #[test]
    fn unresolved_network_teardown_is_bounded_and_drops_its_future() {
        struct DropProbe(Arc<AtomicBool>);

        impl Drop for DropProbe {
            fn drop(&mut self) {
                self.0.store(true, Ordering::Release);
            }
        }

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let dropped = Arc::new(AtomicBool::new(false));
            let probe = DropProbe(Arc::clone(&dropped));
            let started = std::time::Instant::now();
            let completed = await_bounded_ssh_teardown(
                async move {
                    let _probe = probe;
                    std::future::pending::<()>().await;
                },
                Duration::from_millis(25),
            )
            .await;
            assert!(!completed);
            assert!(started.elapsed() < Duration::from_secs(1));
            assert!(
                dropped.load(Ordering::Acquire),
                "timed-out network teardown retained its transport handles"
            );
        });
    }

    #[test]
    fn dynamic_listeners_share_one_handshake_cap_and_recover_after_rejection() {
        let first_reservation =
            std::net::TcpListener::bind(("127.0.0.1", 0)).expect("reserve first port");
        let first_port = first_reservation
            .local_addr()
            .expect("first address")
            .port();
        let second_reservation =
            std::net::TcpListener::bind(("127.0.0.1", 0)).expect("reserve second port");
        let second_port = second_reservation
            .local_addr()
            .expect("second address")
            .port();
        drop((first_reservation, second_reservation));
        let connection = TerminalProfileConnection {
            port_forwards: vec![first_port, second_port]
                .into_iter()
                .map(|bind_port| TerminalSshPortForward {
                    kind: TerminalSshPortForwardKind::Dynamic,
                    bind_host: "127.0.0.1".to_string(),
                    bind_port,
                    target_host: String::new(),
                    target_port: 0,
                })
                .collect(),
            ..<_>::default()
        };
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .expect("runtime");
        runtime.block_on(async move {
            let cancellation = SshCancellation::default();
            let forward_runtime = ForwardRuntime::with_limits(cancellation, 1, 1);
            let (sender, mut receiver) = mpsc::channel(MAX_PENDING_FORWARD_HANDSHAKES);
            let tasks = start_local_forward_listeners(&connection, sender, forward_runtime.clone())
                .await
                .expect("listeners");

            let slow = TcpStream::connect(("127.0.0.1", first_port))
                .await
                .expect("slow client");
            tokio::time::timeout(Duration::from_secs(1), async {
                while forward_runtime.available_handshake_permits() != 0 {
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("first listener did not acquire the shared permit");

            let mut rejected = TcpStream::connect(("127.0.0.1", second_port))
                .await
                .expect("rejected client");
            let mut rejection = [0_u8; 1];
            let rejected_bytes =
                tokio::time::timeout(Duration::from_secs(1), rejected.read(&mut rejection))
                    .await
                    .expect("second listener did not close at the shared cap")
                    .expect("rejection read");
            assert_eq!(rejected_bytes, 0);

            drop(slow);
            tokio::time::timeout(Duration::from_secs(1), async {
                while forward_runtime.available_handshake_permits() != 1 {
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("dropped handshake did not release the shared permit");

            let mut accepted = TcpStream::connect(("127.0.0.1", second_port))
                .await
                .expect("accepted client");
            accepted.write_all(&[5, 1, 0]).await.expect("greeting");
            let mut method = [0_u8; 2];
            tokio::time::timeout(Duration::from_secs(1), accepted.read_exact(&mut method))
                .await
                .expect("listener remained head-of-line blocked")
                .expect("method reply");
            assert_eq!(method, [5, 0]);
            accepted
                .write_all(&[5, 1, 0, 1, 127, 0, 0, 1, 0, 22])
                .await
                .expect("connect request");
            let accepted = tokio::time::timeout(Duration::from_secs(1), receiver.recv())
                .await
                .expect("accepted forward timeout")
                .expect("accepted forward");
            assert_eq!(accepted.target_host, "127.0.0.1");
            assert_eq!(accepted.target_port, 22);

            tasks.abort_all();
            forward_runtime.shutdown().await;
            assert_eq!(forward_runtime.available_handshake_permits(), 1);
            assert_eq!(forward_runtime.tracked_task_count(), 0);
        });
    }

    #[test]
    fn relay_cap_exhaustion_is_isolated_and_cancellation_cleans_up() {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let cancellation = SshCancellation::default();
            let forward_runtime = ForwardRuntime::with_limits(cancellation.clone(), 1, 1);
            let permit = forward_runtime
                .try_relay_permit()
                .expect("first relay permit");
            let (relay_left, mut peer_left) = tokio::io::duplex(64);
            let (relay_right, mut peer_right) = tokio::io::duplex(64);
            assert!(forward_runtime.spawn_relay(relay_left, relay_right, permit));
            assert!(
                forward_runtime.try_relay_permit().is_none(),
                "the active relay cap must reject only the new connection"
            );

            peer_left.write_all(b"still-alive").await.expect("write");
            let mut relayed = [0_u8; 11];
            tokio::time::timeout(Duration::from_secs(1), peer_right.read_exact(&mut relayed))
                .await
                .expect("existing relay stopped when a later relay was rejected")
                .expect("relay read");
            assert_eq!(&relayed, b"still-alive");

            cancellation.cancel();
            tokio::time::timeout(Duration::from_secs(1), async {
                while forward_runtime.available_relay_permits() != 1 {
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("cancelled relay did not release its permit");
            let mut eof = [0_u8; 1];
            assert_eq!(
                tokio::time::timeout(Duration::from_secs(1), peer_left.read(&mut eof))
                    .await
                    .expect("cancelled relay left its stream open")
                    .expect("peer read"),
                0
            );
            forward_runtime.shutdown().await;
            assert_eq!(forward_runtime.tracked_task_count(), 0);
        });
    }

    #[test]
    fn a_slow_socks_client_does_not_block_later_handshakes() {
        let port = std::net::TcpListener::bind(("127.0.0.1", 0))
            .expect("reserve port")
            .local_addr()
            .expect("reserved address")
            .port();
        let connection = TerminalProfileConnection {
            port_forwards: vec![TerminalSshPortForward {
                kind: TerminalSshPortForwardKind::Dynamic,
                bind_host: "127.0.0.1".to_string(),
                bind_port: port,
                target_host: String::new(),
                target_port: 0,
            }],
            ..<_>::default()
        };
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .expect("runtime");
        runtime.block_on(async move {
            let (sender, mut receiver) = mpsc::channel(MAX_PENDING_FORWARD_HANDSHAKES);
            let forward_runtime = ForwardRuntime::new(SshCancellation::default());
            let tasks = start_local_forward_listeners(&connection, sender, forward_runtime.clone())
                .await
                .expect("listener");
            let _slow = TcpStream::connect(("127.0.0.1", port))
                .await
                .expect("slow client");
            let mut fast = TcpStream::connect(("127.0.0.1", port))
                .await
                .expect("fast client");
            fast.write_all(&[5, 1, 0]).await.expect("greeting");
            let mut method = [0_u8; 2];
            tokio::time::timeout(Duration::from_secs(1), fast.read_exact(&mut method))
                .await
                .expect("second client was blocked")
                .expect("method response");
            assert_eq!(method, [5, 0]);
            fast.write_all(&[5, 1, 0, 1, 127, 0, 0, 1, 0, 22])
                .await
                .expect("connect request");
            let accepted = tokio::time::timeout(Duration::from_secs(1), receiver.recv())
                .await
                .expect("accepted forward timeout")
                .expect("accepted forward");
            assert_eq!(accepted.target_host, "127.0.0.1");
            assert_eq!(accepted.target_port, 22);
            tasks.abort_all();
            forward_runtime.shutdown().await;
        });
    }

    #[test]
    fn dropping_forward_listeners_releases_the_bound_port() {
        let port = std::net::TcpListener::bind(("127.0.0.1", 0))
            .expect("reserve port")
            .local_addr()
            .expect("reserved address")
            .port();
        let connection = TerminalProfileConnection {
            port_forwards: vec![TerminalSshPortForward {
                kind: TerminalSshPortForwardKind::Local,
                bind_host: "127.0.0.1".to_string(),
                bind_port: port,
                target_host: "target.internal".to_string(),
                target_port: 22,
            }],
            ..<_>::default()
        };
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .expect("runtime");
        runtime.block_on(async move {
            let (sender, _receiver) = mpsc::channel(MAX_PENDING_FORWARD_HANDSHAKES);
            let forward_runtime = ForwardRuntime::new(SshCancellation::default());
            let tasks = start_local_forward_listeners(&connection, sender, forward_runtime.clone())
                .await
                .expect("listener");
            assert!(std::net::TcpListener::bind(("127.0.0.1", port)).is_err());
            drop(tasks);
            let rebound = tokio::time::timeout(Duration::from_secs(1), async {
                loop {
                    if let Ok(listener) = TcpListener::bind(("127.0.0.1", port)).await {
                        break listener;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("listener task did not release its port");
            drop(rebound);
            forward_runtime.shutdown().await;
        });
    }

    #[test]
    fn close_interrupts_a_hanging_ssh_handshake() {
        let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("listener");
        let port = listener.local_addr().expect("listener address").port();
        let (accepted_sender, accepted_receiver) = std_mpsc::sync_channel(1);
        let (release_sender, release_receiver) = std_mpsc::sync_channel(1);
        let server = thread::spawn(move || {
            let (_stream, _) = listener.accept().expect("accepted connection");
            accepted_sender.send(()).expect("accepted signal");
            let _ = release_receiver.recv();
        });
        let connection = TerminalProfileConnection {
            connection_type: crate::model::TerminalConnectionType::Ssh,
            host: "127.0.0.1".to_string(),
            user: "cancel-test".to_string(),
            port,
            host_key_policy: TerminalSshHostKeyPolicy::Insecure,
            connect_timeout_seconds: 120,
            ..<_>::default()
        };
        let runtime = spawn_ssh(connection, 24, 80).expect("SSH runtime");
        accepted_receiver
            .recv_timeout(Duration::from_secs(2))
            .expect("transport did not connect");
        let SshRuntime { mut child, .. } = runtime;
        child.kill().expect("cancel SSH");
        let status = wait_for_child_exit(child.as_mut(), Duration::from_secs(2));
        assert_eq!(status.exit_code(), 255);
        let _ = release_sender.send(());
        server.join().expect("server thread");
    }

    #[cfg(unix)]
    #[test]
    fn common_session_teardown_reaps_proxy_command_without_child_kill() {
        use std::os::unix::fs::PermissionsExt;

        let directory = tempfile::tempdir().expect("tempdir");
        let fixture_directory = directory.path().join("proxy fixtures");
        std::fs::create_dir(&fixture_directory).expect("proxy fixture directory");
        let pid_file = fixture_directory.join("normal-close-proxy.pid");
        let script = fixture_directory.join("normal-close-proxy-command");
        std::fs::write(
            &script,
            "#!/bin/sh\nprintf '%s' \"$$\" > \"$1\"\nexec sleep 30\n",
        )
        .expect("proxy script");
        let mut permissions = std::fs::metadata(&script)
            .expect("proxy metadata")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&script, permissions).expect("proxy permissions");

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime");
        runtime.block_on(async {
            let cancellation = SshCancellation::default();
            let forward_runtime = ForwardRuntime::new(cancellation.clone());
            let connection = TerminalProfileConnection {
                host: "normal-close-target.invalid".to_string(),
                user: "normal-close-test".to_string(),
                ..<_>::default()
            };
            let proxy_command = format!(
                "{} {}",
                shell_words::quote(script.to_str().expect("script path")),
                shell_words::quote(pid_file.to_str().expect("pid path")),
            );
            let stream =
                ProxyCommandStream::spawn(&proxy_command, &connection, cancellation.clone())
                    .expect("ProxyCommand stream");
            tokio::time::timeout(Duration::from_secs(2), async {
                while !pid_file.exists() {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await
            .expect("ProxyCommand did not start");
            let pid = std::fs::read_to_string(&pid_file)
                .expect("proxy pid")
                .parse::<i32>()
                .expect("numeric proxy pid");

            shutdown_ssh_resources(&cancellation, &forward_runtime).await;

            assert_ne!(
                unsafe { libc::kill(pid, 0) },
                0,
                "common teardown returned before ProxyCommand {pid} was reaped"
            );
            assert_eq!(forward_runtime.tracked_task_count(), 0);
            drop(stream);
        });
    }

    #[cfg(unix)]
    #[test]
    fn cancelling_proxy_command_terminates_the_child_process() {
        use std::os::unix::fs::PermissionsExt;

        let directory = tempfile::tempdir().expect("tempdir");
        let fixture_directory = directory.path().join("proxy fixtures");
        std::fs::create_dir(&fixture_directory).expect("proxy fixture directory");
        let pid_file = fixture_directory.join("proxy.pid");
        let script = fixture_directory.join("proxy-command");
        std::fs::write(
            &script,
            "#!/bin/sh\nprintf '%s' \"$$\" > \"$1\"\nexec sleep 30\n",
        )
        .expect("proxy script");
        let mut permissions = std::fs::metadata(&script)
            .expect("proxy metadata")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&script, permissions).expect("proxy permissions");

        let connection = TerminalProfileConnection {
            connection_type: crate::model::TerminalConnectionType::Ssh,
            host: "proxy-target.invalid".to_string(),
            user: "proxy-test".to_string(),
            proxy_command: Some(format!(
                "{} {}",
                shell_words::quote(script.to_str().expect("script path")),
                shell_words::quote(pid_file.to_str().expect("pid path")),
            )),
            host_key_policy: TerminalSshHostKeyPolicy::Insecure,
            connect_timeout_seconds: 120,
            ..<_>::default()
        };
        let SshRuntime {
            mut reader,
            mut child,
            ..
        } = spawn_ssh(connection, 24, 80).expect("SSH runtime");
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while !pid_file.exists() && std::time::Instant::now() < deadline {
            if let Some(status) = child.try_wait().expect("SSH child status") {
                let mut output = String::new();
                reader
                    .read_to_string(&mut output)
                    .expect("SSH diagnostic output");
                panic!(
                    "SSH transport exited with code {} before ProxyCommand wrote its startup marker: {}",
                    status.exit_code(),
                    output.trim()
                );
            }
            thread::sleep(Duration::from_millis(10));
        }
        assert!(
            pid_file.exists(),
            "ProxyCommand did not start before deadline"
        );
        let pid = std::fs::read_to_string(&pid_file)
            .expect("proxy pid")
            .parse::<i32>()
            .expect("numeric proxy pid");
        child.kill().expect("cancel SSH");
        let _ = wait_for_child_exit(child.as_mut(), Duration::from_secs(2));
        let deadline = std::time::Instant::now() + Duration::from_secs(2);
        loop {
            let alive = unsafe { libc::kill(pid, 0) } == 0;
            if !alive {
                break;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "ProxyCommand process {pid} survived SSH cancellation"
            );
            thread::sleep(Duration::from_millis(10));
        }
    }
}
