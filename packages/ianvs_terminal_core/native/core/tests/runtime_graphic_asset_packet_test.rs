use ianvs_core::model::TerminalFrameDiff;
use ianvs_core::proto::graphic_asset as pb;
use ianvs_core::session;

fn take_packet(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
) -> Option<pb::GraphicAssetPacketV1> {
    let mut len = 0usize;
    let pointer = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_packet_v1_protobuf(
            session_id,
            asset_id,
            asset_version,
            &mut len,
        )
    };
    if pointer.is_null() {
        assert_eq!(len, 0);
        return None;
    }
    let bytes = unsafe { std::slice::from_raw_parts(pointer, len) }.to_vec();
    unsafe { ianvs_core::ffi::ianvs_bytes_free(pointer, len) };
    Some(
        ianvs_core::graphic_asset_proto::decode_graphic_asset_packet_v1_for_test(&bytes)
            .expect("Graphic Asset Packet v1 must decode"),
    )
}

fn replay_profile() -> String {
    serde_json::json!({
        "id": "graphic-asset-packet-v1",
        "name": "Graphic Asset Packet",
        "launch": {"program": "/definitely/not/a/child"}
    })
    .to_string()
}

#[test]
fn graphic_asset_packet_v1_crosses_ffi_atomically_with_exact_identity() {
    let session_id = session::create_replay_session(&replay_profile()).unwrap();
    session::replay_session_output(
        session_id,
        b"\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;/wAA/w==\x1b\\",
    )
    .unwrap();
    let frame_json = session::take_frame_diff(session_id).unwrap().unwrap();
    let frame: TerminalFrameDiff = serde_json::from_str(&frame_json).unwrap();
    let placement = frame.graphics.first().expect("graphic placement");

    let packet = take_packet(session_id, placement.asset_id, placement.asset_version)
        .expect("versioned asset packet");

    assert_eq!(packet.schema_version, 1);
    assert_eq!(packet.contract, "ianvs-graphic-asset-packet-v1");
    assert_eq!(packet.message_class, "asset_transfer");
    assert_eq!(packet.message_name, "graphic_asset");
    assert_eq!(packet.session_id, session_id.to_string());
    assert_eq!(packet.asset_id, placement.asset_id.to_string());
    assert_eq!(packet.asset_version, placement.asset_version.to_string());
    assert_eq!(packet.width, 1);
    assert_eq!(packet.height, 1);
    assert_eq!(packet.rgba, [255, 0, 0, 255]);
    assert!(take_packet(session_id, placement.asset_id, 0).is_none());

    let legacy_meta = ianvs_core::ffi::ianvs_session_graphic_asset_meta;
    let legacy_copy = ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy;
    let _ = (legacy_meta, legacy_copy);
    session::close_session(session_id).unwrap();
}
