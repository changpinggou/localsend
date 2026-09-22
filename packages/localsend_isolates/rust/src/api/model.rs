use flutter_rust_bridge::frb;
pub use localsend::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, RegisterDto, RegisterResponseDto,
};
pub use localsend::model::capability::Capability;
pub use localsend::model::discovery::DeviceType;
pub use localsend::model::discovery::ProtocolType;
pub use localsend::model::transfer::{FileDto, FileMetadata};
pub use localsend::fs::{FsEntry, FsRoot, ListResponse, RootsResponse};
use std::collections::HashMap;

#[frb(mirror(RegisterDto))]
pub struct _RegisterDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[frb(mirror(RegisterResponseDto))]
pub struct _RegisterResponseDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub has_web_interface: bool,
}

#[frb(mirror(DeviceType))]
pub enum _DeviceType {
    Mobile,
    Desktop,
    Web,
    Headless,
    Server,
}

#[frb(mirror(Capability))]
pub enum _Capability {
    Send,
    Receive,
    Fs,
}

#[frb(mirror(ProtocolType))]
pub enum _ProtocolType {
    Http,
    Https,
}

#[frb(mirror(FileDto))]
pub struct _FileDto {
    pub id: String,
    pub file_name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub preview: Option<String>,
    pub metadata: Option<FileMetadata>,
}

#[frb(mirror(FileMetadata))]
pub struct _FileMetadata {
    pub modified: Option<String>,
    pub accessed: Option<String>,
}

#[frb(mirror(PrepareUploadRequestDto))]
pub struct _PrepareUploadRequestDto {
    pub info: RegisterDto,
    pub files: HashMap<String, FileDto>,
}

#[frb(mirror(PrepareUploadResponseDto))]
pub struct _PrepareUploadResponseDto {
    pub session_id: String,
    pub files: HashMap<String, String>,
}

#[frb(mirror(FsRoot))]
pub struct _FsRoot {
    pub id: String,
    pub label: String,
    pub path: String,
    pub total_bytes: u64,
    pub free_bytes: u64,
    pub filesystem: String,
    pub is_removable: bool,
    pub is_read_only: bool,
}

#[frb(mirror(RootsResponse))]
pub struct _RootsResponse {
    pub roots: Vec<FsRoot>,
}

#[frb(mirror(FsEntry))]
pub struct _FsEntry {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    /// Unix epoch seconds.
    pub mtime: i64,
    /// Best-effort MIME guess based on the file extension. `None` for
    /// directories and unknown extensions.
    pub mime: Option<String>,
}

#[frb(mirror(ListResponse))]
pub struct _ListResponse {
    pub entries: Vec<FsEntry>,
    pub total: usize,
    pub has_more: bool,
}
