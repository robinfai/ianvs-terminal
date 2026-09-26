use super::storage::{StorageError, StorageResult, open_regular_file};
use prost::Message;
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;

pub const MAX_ASSET_BYTES: usize = 32 * 1024 * 1024;
pub const MAX_FRAME_ASSETS: usize = 256;
const MAGIC: &[u8; 8] = b"TRLRGBA2";

/// Immutable content reference carried by every visual sample. Native IDs are
/// scoped to this recording; the digest includes dimensions and RGBA bytes.
#[derive(Clone, PartialEq, Eq, Message)]
pub struct AssetBinding {
    #[prost(uint64, tag = "1")]
    pub asset_id: u64,
    #[prost(uint64, tag = "2")]
    pub asset_version: u64,
    #[prost(uint32, tag = "3")]
    pub width: u32,
    #[prost(uint32, tag = "4")]
    pub height: u32,
    #[prost(bytes = "vec", tag = "5")]
    pub digest: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RecordedAsset {
    pub asset_id: u64,
    pub asset_version: u64,
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

pub(super) fn expected_bytes(width: u32, height: u32) -> StorageResult<usize> {
    let bytes = u64::from(width)
        .checked_mul(u64::from(height))
        .and_then(|pixels| pixels.checked_mul(4))
        .ok_or(StorageError::Invalid("asset dimensions overflow"))?;
    if width == 0 || height == 0 || bytes > MAX_ASSET_BYTES as u64 {
        return Err(StorageError::Invalid("asset dimensions exceed limit"));
    }
    Ok(bytes as usize)
}

impl AssetBinding {
    pub(super) fn validate(&self) -> StorageResult<()> {
        expected_bytes(self.width, self.height)?;
        if self.digest.len() != 32 {
            return Err(StorageError::Invalid("invalid asset digest"));
        }
        Ok(())
    }

    fn filename(&self) -> StorageResult<String> {
        self.validate()?;
        use std::fmt::Write;
        let mut name = String::with_capacity(69);
        for byte in &self.digest {
            write!(&mut name, "{byte:02x}").expect("writing to String cannot fail");
        }
        name.push_str(".rgba");
        Ok(name)
    }
}

pub(super) fn store_asset(root: &Path, asset: &RecordedAsset) -> StorageResult<AssetBinding> {
    if expected_bytes(asset.width, asset.height)? != asset.rgba.len() {
        return Err(StorageError::Invalid(
            "RGBA byte count does not match dimensions",
        ));
    }
    let mut prefix = [0u8; 16];
    prefix[..8].copy_from_slice(MAGIC);
    prefix[8..12].copy_from_slice(&asset.width.to_le_bytes());
    prefix[12..16].copy_from_slice(&asset.height.to_le_bytes());
    let mut hasher = Sha256::new();
    hasher.update(prefix);
    hasher.update(&asset.rgba);
    let binding = AssetBinding {
        asset_id: asset.asset_id,
        asset_version: asset.asset_version,
        width: asset.width,
        height: asset.height,
        digest: hasher.finalize().to_vec(),
    };
    let destination = root.join(binding.filename()?);
    match fs::symlink_metadata(&destination) {
        Ok(_) => {
            // Never overwrite an existing blob, including corrupt files or links.
            load_asset(root, &binding)?;
            return Ok(binding);
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    let mut temporary = tempfile::NamedTempFile::new_in(root)?;
    temporary.write_all(&prefix)?;
    temporary.write_all(&asset.rgba)?;
    temporary.as_file().sync_all()?;
    match temporary.persist_noclobber(&destination) {
        Ok(_) => {}
        Err(error) if error.error.kind() == std::io::ErrorKind::AlreadyExists => {
            load_asset(root, &binding)?;
        }
        Err(error) => return Err(error.error.into()),
    }
    // Persist the blob's name before a durable frame is allowed to refer to it.
    sync_directory(root)?;
    Ok(binding)
}

pub(super) fn load_asset(root: &Path, binding: &AssetBinding) -> StorageResult<RecordedAsset> {
    binding.validate()?;
    let expected = expected_bytes(binding.width, binding.height)?;
    let mut file = open_regular_file(&root.join(binding.filename()?))?;
    if file.metadata()?.len() != expected as u64 + 16 {
        return Err(StorageError::Invalid("asset file length mismatch"));
    }
    let mut prefix = [0u8; 16];
    file.read_exact(&mut prefix)?;
    if &prefix[..8] != MAGIC
        || prefix[8..12] != binding.width.to_le_bytes()
        || prefix[12..16] != binding.height.to_le_bytes()
    {
        return Err(StorageError::Invalid("asset header mismatch"));
    }
    let mut rgba = vec![0; expected];
    file.read_exact(&mut rgba)?;
    let mut hasher = Sha256::new();
    hasher.update(prefix);
    hasher.update(&rgba);
    if hasher.finalize().as_slice() != binding.digest {
        return Err(StorageError::Invalid("asset checksum mismatch"));
    }
    Ok(RecordedAsset {
        asset_id: binding.asset_id,
        asset_version: binding.asset_version,
        width: binding.width,
        height: binding.height,
        rgba,
    })
}

pub(super) fn sync_directory(path: &Path) -> StorageResult<()> {
    // Directory fsync is supported on the first-release macOS/Linux targets.
    #[cfg(unix)]
    File::open(path)?.sync_all()?;
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}
