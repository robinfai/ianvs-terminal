use ianvs_core::proto::frame_diff as pb;
use ianvs_core::session;

fn take_packet(session_id: u64, after_sequence: Option<u64>) -> Option<pb::TerminalFramePacketV1> {
    let mut len = 0usize;
    let pointer = unsafe {
        ianvs_core::ffi::ianvs_session_take_frame_packet_v1_protobuf(
            session_id,
            after_sequence.unwrap_or_default(),
            u8::from(after_sequence.is_some()),
            &mut len,
        )
    };
    if pointer.is_null() {
        assert_eq!(len, 0);
        return None;
    }
    assert!(len > 0);
    let bytes = unsafe { std::slice::from_raw_parts(pointer, len) }.to_vec();
    unsafe { ianvs_core::ffi::ianvs_bytes_free(pointer, len) };
    Some(
        ianvs_core::frame_diff_proto::decode_frame_packet_v1_for_test(&bytes)
            .expect("Frame Packet v1 must decode"),
    )
}

fn replay_profile(id: &str) -> String {
    serde_json::json!({
        "id": id,
        "name": "Frame Packet",
        "launch": {"program": "/definitely/not/a/child"}
    })
    .to_string()
}

#[test]
fn frame_packet_v1_crosses_ffi_with_identity_sequence_and_timestamp() {
    let session_id = session::create_replay_session(&replay_profile("frame-packet-v1")).unwrap();

    let packet = take_packet(session_id, None).expect("initial Snapshot packet");
    assert_eq!(packet.schema_version, 1);
    assert_eq!(packet.contract, "ianvs-terminal-frame-packet-v1");
    assert_eq!(packet.message_class, "frame");
    assert_eq!(packet.message_name, "frame_diff");
    assert_eq!(packet.session_id, session_id.to_string());
    assert_eq!(packet.sequence, 0);
    assert!(packet.timestamp_micros > 0);
    assert_eq!(packet.frame_schema_version, "terminal-frame-diff-v1");
    let frame = packet.frame.expect("nested Frame payload");
    assert_eq!(frame.frame_schema_version, packet.frame_schema_version);
    assert_eq!(frame.frame_kind, pb::TerminalFrameKind::Snapshot as i32);

    assert!(take_packet(session_id, Some(0)).is_none());
    session::close_session(session_id).unwrap();
}

#[test]
fn stale_frame_packet_acknowledgement_forces_the_next_snapshot() {
    let session_id =
        session::create_replay_session(&replay_profile("frame-packet-resync")).unwrap();
    session::replay_session_output(session_id, b"seed").unwrap();
    let initial = take_packet(session_id, None).unwrap();
    assert_eq!(initial.sequence, 0);

    session::replay_session_output(session_id, b"first").unwrap();
    let incremental = take_packet(session_id, Some(0)).unwrap();
    assert_eq!(incremental.sequence, 1);
    assert_eq!(
        incremental.frame.unwrap().frame_kind,
        pb::TerminalFrameKind::Delta as i32
    );

    session::replay_session_output(session_id, b"second").unwrap();
    let recovered = take_packet(session_id, Some(0)).unwrap();
    assert_eq!(recovered.sequence, 2);
    assert_eq!(
        recovered.frame.unwrap().frame_kind,
        pb::TerminalFrameKind::Snapshot as i32
    );

    session::close_session(session_id).unwrap();
}
