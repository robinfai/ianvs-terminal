use ianvs_core::IanvsGraphicAssetMeta;
use serde_json::Value;
use std::mem::{align_of, offset_of, size_of};
use std::path::PathBuf;

#[test]
fn checked_in_abi_manifest_matches_host_struct_layout() {
    let manifest_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("ianvs_core_abi_v1.json");
    let manifest: Value = serde_json::from_slice(
        &std::fs::read(&manifest_path)
            .unwrap_or_else(|error| panic!("read {}: {error}", manifest_path.display())),
    )
    .expect("parse ABI manifest");
    let host = &manifest["host_layout"];
    assert_eq!(host["pointer_width"], Value::from(usize::BITS));
    let layout = &host["IanvsGraphicAssetMeta"];
    assert_eq!(
        layout["size"],
        Value::from(size_of::<IanvsGraphicAssetMeta>())
    );
    assert_eq!(
        layout["alignment"],
        Value::from(align_of::<IanvsGraphicAssetMeta>())
    );
    assert_eq!(
        layout["offsets"]["width"],
        Value::from(offset_of!(IanvsGraphicAssetMeta, width))
    );
    assert_eq!(
        layout["offsets"]["height"],
        Value::from(offset_of!(IanvsGraphicAssetMeta, height))
    );
    assert_eq!(
        layout["offsets"]["rgba_len"],
        Value::from(offset_of!(IanvsGraphicAssetMeta, rgba_len))
    );
    assert_eq!(
        layout["offsets"]["version"],
        Value::from(offset_of!(IanvsGraphicAssetMeta, version))
    );
}
