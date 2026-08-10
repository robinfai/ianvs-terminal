use crate::proto::graphic_asset as pb;
use crate::runtime_contract::{GRAPHIC_ASSET_PACKET_CONTRACT, GRAPHIC_ASSET_PACKET_SCHEMA_VERSION};
use prost::Message;

pub fn encode_graphic_asset_packet_v1(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
    width: u32,
    height: u32,
    rgba: &[u8],
) -> Result<Vec<u8>, prost::EncodeError> {
    let packet = pb::GraphicAssetPacketV1 {
        schema_version: GRAPHIC_ASSET_PACKET_SCHEMA_VERSION,
        contract: GRAPHIC_ASSET_PACKET_CONTRACT.to_owned(),
        message_class: "asset_transfer".to_owned(),
        message_name: "graphic_asset".to_owned(),
        session_id: session_id.to_string(),
        asset_id: asset_id.to_string(),
        asset_version: asset_version.to_string(),
        width,
        height,
        rgba: rgba.to_vec(),
    };
    let mut bytes = Vec::with_capacity(packet.encoded_len());
    packet.encode(&mut bytes)?;
    Ok(bytes)
}

pub fn decode_graphic_asset_packet_v1_for_test(
    bytes: &[u8],
) -> Result<pb::GraphicAssetPacketV1, prost::DecodeError> {
    pb::GraphicAssetPacketV1::decode(bytes)
}
