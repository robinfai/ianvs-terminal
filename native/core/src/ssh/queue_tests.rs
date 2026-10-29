use super::*;

#[test]
fn oversized_write_all_streams_through_byte_budget_in_order() {
    let budget = buffer::InputBudget::new(SSH_INPUT_CHUNK_BYTES + SSH_INPUT_ITEM_OVERHEAD);
    let (sender, mut receiver) = mpsc::unbounded_channel();
    let mut writer = SshWriter { sender, budget };
    let expected: Vec<u8> = (0..SSH_INPUT_QUEUE_BYTES * 3)
        .map(|i| (i % 251) as u8)
        .collect();
    let input = expected.clone();
    let producer = thread::spawn(move || writer.write_all(&input).unwrap());
    let mut actual = Vec::new();
    while let Some(command) = receiver.blocking_recv() {
        let SshCommand::Data(input) = command else {
            panic!("expected data");
        };
        assert!(input.bytes.len() <= SSH_INPUT_CHUNK_BYTES);
        actual.extend_from_slice(&input.bytes);
        // Dropping only after consumption releases the next producer chunk.
    }
    producer.join().unwrap();
    assert_eq!(actual, expected);
}

#[test]
fn saturated_input_does_not_prevent_local_kill_and_wakes_writer() {
    let budget = buffer::InputBudget::new(SSH_INPUT_CHUNK_BYTES + SSH_INPUT_ITEM_OVERHEAD);
    let (sender, mut receiver) = mpsc::unbounded_channel();
    let mut writer = SshWriter {
        sender: sender.clone(),
        budget: budget.clone(),
    };
    writer
        .write_all(&vec![b'a'; SSH_INPUT_CHUNK_BYTES])
        .unwrap();
    let held = receiver.blocking_recv().unwrap();
    let cancellation = SshCancellation::default();
    let mut child = SshChild {
        sender,
        status: Arc::new((StdMutex::new(None), Condvar::new())),
        auth: SshAuthClient::default(),
        cancellation: cancellation.clone(),
        input_budget: budget,
    };
    let (done, result) = std_mpsc::channel();
    let producer =
        thread::spawn(move || done.send(writer.write(b"b").unwrap_err().kind()).unwrap());
    child.kill().unwrap();
    assert!(cancellation.cancelled.load(Ordering::Acquire));
    assert!(matches!(receiver.try_recv().unwrap(), SshCommand::Close));
    assert_eq!(
        result.recv_timeout(Duration::from_secs(2)).unwrap(),
        ErrorKind::BrokenPipe
    );
    drop(held);
    producer.join().unwrap();
}

#[test]
fn remote_zero_window_does_not_block_cancellation_or_release_input_early() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let budget = buffer::InputBudget::new(8 + SSH_INPUT_ITEM_OVERHEAD);
        let mut pending = VecDeque::from([reserve_ssh_input(&budget, b"abcdefgh", false).unwrap()]);
        let (mut writer, mut remote) = tokio::io::duplex(2);
        write_ssh_input(&mut writer, &mut pending).await.unwrap();
        assert_eq!(pending.front().unwrap().offset, 2);
        assert!(budget.reserve(1, false).is_err());
        // Actually poll the full writer before dropping the pending future, as
        // select! does when another branch wins. A pre-cancelled biased branch
        // alone would never exercise cancellation of an in-flight write.
        let mut blocked_write = Box::pin(write_ssh_input(&mut writer, &mut pending));
        assert!(matches!(futures_util::poll!(blocked_write.as_mut()), Poll::Pending));
        drop(blocked_write);
        let cancellation = SshCancellation::default();
        cancellation.cancel();
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => {},
            result = write_ssh_input(&mut writer, &mut pending) => panic!("full writer advanced: {result:?}"),
        }
        assert_eq!(pending.front().unwrap().offset, 2);
        let mut actual = [0; 8];
        remote.read_exact(&mut actual[..2]).await.unwrap();
        for offset in [2, 4, 6] {
            write_ssh_input(&mut writer, &mut pending).await.unwrap();
            remote.read_exact(&mut actual[offset..offset + 2]).await.unwrap();
        }
        assert_eq!(&actual, b"abcdefgh");
        assert!(pending.is_empty());
        assert!(budget.reserve(8 + SSH_INPUT_ITEM_OVERHEAD, false).is_ok());
    });
}

#[test]
fn retired_route_cancels_pending_endpoint_before_reused_socket_can_execute() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let mut bootstrap = crate::shell_bootstrap::Bootstrap::new("test".into(), true);
        let enter =
            b"\x1b]6973;test;a;enter;root;/tmp/reused;host;user;22\x07\x1b]6973;a;a;init;bash\x07";
        bootstrap.feed(enter);
        let (route, lifetime) = bootstrap.bound_route_for("a@1").unwrap();
        let endpoint = SftpEndpoint {
            session: None,
            route,
            route_cancellation: Some(lifetime),
        };
        let (release, blocked) = oneshot::channel::<()>();
        let executed = Arc::new(AtomicBool::new(false));
        let observed = executed.clone();
        // Same lifetime guard used by open_stream, stopped exactly before a
        // hypothetical SFTP init/first request can use the socket path.
        let mut request = Box::pin(endpoint.bind_route(async move {
            blocked.await.unwrap();
            observed.store(true, Ordering::Release);
            Ok(())
        }));
        assert!(matches!(
            futures_util::poll!(request.as_mut()),
            Poll::Pending
        ));
        bootstrap.feed(b"\x1b]6973;test;root;resume;done\x07");
        bootstrap.feed(enter);
        assert!(bootstrap.bound_route_for("a@1").is_err());
        assert!(bootstrap.bound_route_for("a").is_err());
        let (route, lifetime) = bootstrap.bound_route_for("a@2").unwrap();
        assert_eq!(route, endpoint.route); // Reuse the exact path and host.
        release.send(()).unwrap();
        assert!(request.await.is_err());
        assert!(!executed.load(Ordering::Acquire));
        let current = SftpEndpoint {
            session: None,
            route,
            route_cancellation: Some(lifetime),
        };
        assert!(current.bind_route(async { Ok(()) }).await.is_ok());
        // Merely switching into a nested shell does not retire the host route.
        bootstrap.feed(b"\x1b]6973;a;shell;enter_shell;a;bash\x07");
        assert!(current.bind_route(async { Ok(()) }).await.is_ok());
    });
}

#[test]
fn route_retirement_is_observed_by_post_handshake_operation_steps() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let route = SftpOperationCancellation::new();
        let request = SftpOperationCancellation::new().with_route(Some(&route));
        route.cancel();
        let writes = AtomicUsize::new(0);
        let result = sftp_operation_step(&request, async {
            writes.fetch_add(1, Ordering::Relaxed);
            Ok::<(), IoError>(())
        })
        .await;
        assert!(result.is_err());
        assert_eq!(writes.load(Ordering::Relaxed), 0);
    });
}

#[test]
fn queued_atomic_commit_checks_route_lifetime_when_worker_starts() {
    let route = SftpOperationCancellation::new();
    let request = SftpOperationCancellation::new().with_route(Some(&route));
    let (release, start) = std::sync::mpsc::channel();
    let commits = Arc::new(AtomicUsize::new(0));
    let observed = commits.clone();
    let worker = thread::spawn(move || {
        start.recv().unwrap();
        sftp_blocking_commit(&request, || {
            observed.fetch_add(1, Ordering::Relaxed);
            Ok(())
        })
    });
    route.cancel();
    release.send(()).unwrap();
    assert_eq!(
        worker.join().unwrap().unwrap_err().kind(),
        ErrorKind::Interrupted
    );
    assert_eq!(commits.load(Ordering::Relaxed), 0);
    let request = SftpOperationCancellation::new();
    assert!(
        sftp_blocking_commit(&request, || {
            // Cancellation after the worker begins the OS commit does not falsely
            // report that an already committed replacement was rolled back.
            request.cancel();
            Ok(())
        })
        .is_ok()
    );
}
