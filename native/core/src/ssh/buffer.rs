//! Bounded bridge between the asynchronous SSH task and the synchronous PTY reader.
//! Credits are released by actual reads, not by dequeueing an owned chunk.
use parking_lot::{Condvar, Mutex};
use std::collections::VecDeque;
use std::io::{self, Read};
use std::sync::Arc;
use tokio::sync::Notify;

struct State {
    bytes: VecDeque<u8>,
    senders: usize,
    reader_closed: bool,
    diagnostic: VecDeque<u8>,
}

struct Shared {
    state: Mutex<State>,
    capacity: usize,
    readable: Condvar,
    space: Notify,
}

pub(super) struct Sender(Arc<Shared>);
pub(super) struct Reader(Arc<Shared>);

pub(super) fn channel(capacity: usize) -> (Sender, Reader) {
    assert!(capacity > 0);
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            bytes: VecDeque::new(),
            senders: 1,
            reader_closed: false,
            diagnostic: VecDeque::new(),
        }),
        capacity,
        readable: Condvar::new(),
        space: Notify::new(),
    });
    (Sender(shared.clone()), Reader(shared))
}

impl Clone for Sender {
    fn clone(&self) -> Self {
        self.0.state.lock().senders += 1;
        Self(self.0.clone())
    }
}

impl Sender {
    /// Nonblocking, possibly partial append. The caller retains the unsent suffix.
    pub(super) fn send_prefix(&self, bytes: &[u8]) -> io::Result<usize> {
        let mut state = self.0.state.lock();
        if state.reader_closed {
            return Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "SSH output reader closed",
            ));
        }
        let count = bytes.len().min(self.0.capacity - state.bytes.len());
        state.bytes.extend(&bytes[..count]);
        if count != 0 {
            self.0.readable.notify_one();
        }
        Ok(count)
    }

    pub(super) async fn space_changed(&self) {
        // notify_one retains a permit when the consumer wins the race with select!.
        self.0.space.notified().await;
    }

    pub(super) fn reader_closed(&self) -> bool {
        self.0.state.lock().reader_closed
    }

    pub(super) fn finish_diagnostic(&self, message: &str) {
        let mut state = self.0.state.lock();
        // A bounded tail follows queued output without waiting for data credit.
        // Preserve the PTY contract: diagnostic text, then child exit 255.
        let mut end = message.len().min(4096);
        while !message.is_char_boundary(end) {
            end -= 1;
        }
        state.diagnostic = message.as_bytes()[..end].iter().copied().collect();
        self.0.readable.notify_all();
    }
}

impl Drop for Sender {
    fn drop(&mut self) {
        let mut state = self.0.state.lock();
        state.senders -= 1;
        if state.senders == 0 {
            self.0.readable.notify_all();
        }
    }
}

impl Read for Reader {
    fn read(&mut self, target: &mut [u8]) -> io::Result<usize> {
        if target.is_empty() {
            return Ok(0);
        }
        let mut state = self.0.state.lock();
        loop {
            let count = target.len().min(state.bytes.len());
            if count != 0 {
                for (target, byte) in target[..count].iter_mut().zip(state.bytes.drain(..count)) {
                    *target = byte;
                }
                self.0.space.notify_one();
                return Ok(count);
            }
            if state.senders == 0 {
                let count = target.len().min(state.diagnostic.len());
                for (target, byte) in target[..count]
                    .iter_mut()
                    .zip(state.diagnostic.drain(..count))
                {
                    *target = byte;
                }
                return Ok(count);
            }
            self.0.readable.wait(&mut state);
        }
    }
}

impl Drop for Reader {
    fn drop(&mut self) {
        let mut state = self.0.state.lock();
        state.reader_closed = true;
        state.bytes.clear();
        self.0.space.notify_one();
    }
}

/// At most one processed channel batch waits outside the reader budget. Pausing
/// channel.wait() while this is nonempty propagates pressure to russh's window.
pub(super) struct Pending {
    bytes: Vec<u8>,
    offset: usize,
    limit: usize,
}

impl Pending {
    pub(super) fn new(limit: usize) -> Self {
        Self {
            bytes: Vec::new(),
            offset: 0,
            limit,
        }
    }

    pub(super) fn is_empty(&self) -> bool {
        self.offset == self.bytes.len()
    }

    pub(super) fn push(&mut self, bytes: Vec<u8>) -> io::Result<()> {
        if bytes.len() > self.limit.saturating_sub(self.bytes.len()) {
            return Err(io::Error::other(
                "SSH processed output batch exceeds byte budget",
            ));
        }
        self.bytes.extend(bytes);
        Ok(())
    }

    pub(super) fn flush(&mut self, output: &Sender) -> io::Result<()> {
        self.offset += output.send_prefix(&self.bytes[self.offset..])?;
        if self.is_empty() {
            self.bytes.clear();
            self.offset = 0;
        }
        Ok(())
    }
}

#[derive(Debug)]
struct InputState {
    available: usize,
    closed: bool,
}

#[derive(Debug)]
pub(super) struct InputBudget {
    state: Mutex<InputState>,
    capacity: usize,
    changed: Condvar,
}

#[derive(Debug)]
pub(super) struct InputPermit {
    budget: Arc<InputBudget>,
    charge: usize,
}

impl InputBudget {
    pub(super) fn new(capacity: usize) -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(InputState {
                available: capacity,
                closed: false,
            }),
            capacity,
            changed: Condvar::new(),
        })
    }

    pub(super) fn reserve(self: &Arc<Self>, charge: usize, wait: bool) -> io::Result<InputPermit> {
        if charge > self.capacity {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "SSH input chunk exceeds byte budget",
            ));
        }
        let mut state = self.state.lock();
        loop {
            if state.closed {
                return Err(io::Error::new(
                    io::ErrorKind::BrokenPipe,
                    "SSH input closed",
                ));
            }
            if state.available >= charge {
                state.available -= charge;
                return Ok(InputPermit {
                    budget: self.clone(),
                    charge,
                });
            }
            if !wait {
                return Err(io::Error::new(
                    io::ErrorKind::WouldBlock,
                    "SSH input byte budget exhausted",
                ));
            }
            self.changed.wait(&mut state);
        }
    }

    pub(super) fn close(&self) {
        self.state.lock().closed = true;
        self.changed.notify_all();
    }
}

impl Drop for InputPermit {
    fn drop(&mut self) {
        self.budget.state.lock().available += self.charge;
        self.budget.changed.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn partial_reads_release_only_consumed_bytes_and_preserve_order() {
        let (sender, mut reader) = channel(4);
        assert_eq!(sender.send_prefix(b"abcdef").unwrap(), 4);
        assert_eq!(sender.send_prefix(b"ef").unwrap(), 0);
        let mut bytes = [0; 2];
        assert_eq!(reader.read(&mut bytes).unwrap(), 2);
        assert_eq!(&bytes, b"ab");
        assert_eq!(sender.send_prefix(b"ef").unwrap(), 2);
        drop(sender);
        let mut rest = Vec::new();
        reader.read_to_end(&mut rest).unwrap();
        assert_eq!(&rest, b"cdef");
    }

    #[test]
    fn slow_consumer_drains_pending_batches_without_loss_or_growth() {
        let (sender, mut reader) = channel(7);
        let mut pending = Pending::new(32);
        let expected: Vec<u8> = (0..200).collect();
        let mut actual = Vec::new();
        for batch in expected.chunks(13) {
            pending.push(batch.to_vec()).unwrap();
            while !pending.is_empty() {
                pending.flush(&sender).unwrap();
                assert!(sender.0.state.lock().bytes.len() <= 7);
                let mut part = [0; 3];
                let count = reader.read(&mut part).unwrap();
                actual.extend_from_slice(&part[..count]);
            }
        }
        drop(sender);
        reader.read_to_end(&mut actual).unwrap();
        assert_eq!(actual, expected);
    }

    #[test]
    fn closing_last_sender_wakes_waiting_reader() {
        let (sender, mut reader) = channel(4);
        let other_sender = sender.clone();
        let (done, result) = mpsc::channel();
        let thread = thread::spawn(move || done.send(reader.read(&mut [0; 1])).unwrap());
        drop(sender);
        assert!(result.try_recv().is_err());
        drop(other_sender);
        assert_eq!(
            result
                .recv_timeout(Duration::from_secs(2))
                .unwrap()
                .unwrap(),
            0
        );
        thread.join().unwrap();
    }

    #[test]
    fn full_queue_keeps_bounded_failure_diagnostic_after_original_bytes() {
        let (sender, mut reader) = channel(4);
        sender.send_prefix(b"data").unwrap();
        sender.finish_diagnostic("error");
        drop(sender);
        let mut bytes = Vec::new();
        reader.read_to_end(&mut bytes).unwrap();
        assert_eq!(&bytes, b"dataerror");
    }

    #[test]
    fn consumer_close_and_credit_release_notify_async_producer() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async {
            let (sender, mut reader) = channel(1);
            sender.send_prefix(b"a").unwrap();
            reader.read_exact(&mut [0; 1]).unwrap();
            // The consumer already won the race: the notification must be retained.
            tokio::time::timeout(Duration::from_secs(2), sender.space_changed())
                .await
                .unwrap();
            drop(reader);
            tokio::time::timeout(Duration::from_secs(2), sender.space_changed())
                .await
                .unwrap();
            assert_eq!(
                sender.send_prefix(b"b").unwrap_err().kind(),
                io::ErrorKind::BrokenPipe
            );
        });
    }

    #[test]
    fn input_credit_is_released_by_drop_and_close_wakes_blocked_producer() {
        let budget = InputBudget::new(8);
        let permit = budget.reserve(8, false).unwrap();
        assert_eq!(
            budget.reserve(1, false).unwrap_err().kind(),
            io::ErrorKind::WouldBlock
        );
        drop(permit);
        let permit = budget.reserve(8, false).unwrap();
        let other = budget.clone();
        let (done, result) = mpsc::channel();
        let thread = thread::spawn(move || {
            done.send(other.reserve(1, true).unwrap_err().kind())
                .unwrap()
        });
        budget.close();
        assert_eq!(
            result.recv_timeout(Duration::from_secs(2)).unwrap(),
            io::ErrorKind::BrokenPipe
        );
        drop(permit);
        thread.join().unwrap();
    }

    #[test]
    fn oversized_processed_batch_is_rejected_without_mutating_pending() {
        let mut pending = Pending::new(3);
        pending.push(b"ab".to_vec()).unwrap();
        assert!(pending.push(b"cd".to_vec()).is_err());
        let (sender, mut reader) = channel(4);
        pending.flush(&sender).unwrap();
        drop(sender);
        let mut bytes = Vec::new();
        reader.read_to_end(&mut bytes).unwrap();
        assert_eq!(&bytes, b"ab");
    }
}
