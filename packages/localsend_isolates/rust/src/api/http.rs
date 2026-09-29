use crate::api::cancel::RsCancellationToken;
use crate::api::stream;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
pub use localsend::http::client::{ClientError, LsHttpClientVersion};
pub use localsend::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, PrepareUploadResult,
    RegisterDto, RegisterResponseDto,
};
use localsend::model::discovery::ProtocolType;
use localsend::util::error::ErrorChain;

pub use localsend::fs::{
    DeleteFailure, DeleteResponse, FsEntry, FsRoot, ListResponse, MoveResponse, RootsResponse,
    StatResponse,
};

pub struct RsHttpClient {
    inner: localsend::http::client::LsHttpClient,
}

/// Creates an HTTP client.
///
/// `expected_fingerprint` pins the peer to the certificate with that SHA-256
/// fingerprint (uppercase hex). It is enforced during the TLS handshake, so a
/// peer that does not present the expected certificate never receives the
/// request. Pass `None` only for discovery, where the peer is not known yet.
#[frb(sync)]
pub fn create_client(
    private_key: String,
    cert: String,
    version: LsHttpClientVersion,
    expected_fingerprint: Option<String>,
    timeout_ms: Option<u32>,
) -> Result<RsHttpClient, RsHttpClientError> {
    let inner = localsend::http::client::LsHttpClient::new(
        &private_key,
        &cert,
        version,
        expected_fingerprint,
        timeout_ms.map(|ms| std::time::Duration::from_millis(ms as u64)),
    )
    .map_err(RsHttpClientError::from)?;

    Ok(RsHttpClient { inner })
}

/// Creates a plain HTTP client without any TLS or client certificate.
///
/// Used for `fs/roots` and `fs/list` which are served on the same port as
/// the HTTPS server but accept plain HTTP. The client does not send a
/// certificate and does not verify the server certificate.
#[frb(sync)]
pub fn create_http_only_client() -> Result<RsHttpClient, RsHttpClientError> {
    let inner = localsend::http::client::LsHttpClient::V2(
        localsend::http::client::LsHttpClientV2::try_new_without_cert()
            .map_err(RsHttpClientError::from)?,
    );
    Ok(RsHttpClient { inner })
}

impl RsHttpClient {
    pub async fn register(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: RegisterDto,
    ) -> Result<ResultWithPublicKeyRegisterResponseDto, RsHttpClientError> {
        let response = self
            .inner
            .register(protocol, ip, port, payload)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(ResultWithPublicKeyRegisterResponseDto {
            public_key: response.public_key,
            body: response.body,
        })
    }

    pub async fn prepare_upload(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: PrepareUploadRequestDto,
        public_key: Option<String>,
        pin: Option<String>,
        cancel_token: &RsCancellationToken,
    ) -> Result<PrepareUploadResult, RsHttpClientError> {
        let response = self
            .inner
            .prepare_upload(
                protocol,
                ip,
                port,
                public_key,
                payload,
                pin.as_deref(),
                cancel_token.inner.clone(),
            )
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(response)
    }

    /// Uploads a single file, emitting [RsUploadEvent]s on [sink].
    ///
    /// Failures are emitted as [RsUploadEvent::Failed] instead of being
    /// returned: flutter_rust_bridge discards the returned `Result` of
    /// functions taking a [StreamSink], so a returned error would become an
    /// uncaught async error killing the calling isolate.
    pub async fn upload(
        &self,
        sink: StreamSink<RsUploadEvent>,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        session_id: &str,
        file_id: &str,
        token: &str,
        binary: Option<stream::Dart2RustStreamReceiver>,
        path: Option<String>,
        file_descriptor: Option<i32>,
        content_length: u64,
        cancel_token: &RsCancellationToken,
    ) {
        let result = async {
            let content = resolve_file_content(binary, path, file_descriptor)?;
            let last_emit = std::cell::Cell::new(None::<std::time::Instant>);
            let progress_sink = sink.clone();
            let progress = move |sent| {
                let now = std::time::Instant::now();
                let is_final = sent >= content_length;
                if !is_final {
                    if let Some(last) = last_emit.get() {
                        if now.duration_since(last) < std::time::Duration::from_millis(20) {
                            return;
                        }
                    }
                }
                last_emit.set(Some(now));
                let progress = if content_length == 0 {
                    1.0
                } else {
                    (sent as f64 / content_length as f64).min(1.0)
                };
                let _ = progress_sink.add(RsUploadEvent::Progress { progress });
            };

            self.inner
                .upload(
                    protocol,
                    ip,
                    port,
                    public_key,
                    session_id,
                    file_id,
                    token,
                    content,
                    progress,
                    cancel_token.inner.clone(),
                )
                .await
                .map_err(RsHttpClientError::from)?;

            Ok(())
        }
        .await;

        if let Err(error) = result {
            let _ = sink.add(RsUploadEvent::Failed { error });
        }
    }

    pub async fn cancel(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<(), RsHttpClientError> {
        self.inner
            .cancel(protocol, ip, port, session_id)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(())
    }

    /// `GET /api/localsend/v2/fs/roots` — fetch the peer's whitelisted
    /// mount points. Used by the remote file browser (T-008).
    pub async fn list_roots(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
    ) -> Result<RootsResponse, RsHttpClientError> {
        self.inner
            .list_roots(protocol, ip, port)
            .await
            .map(Into::into)
            .map_err(RsHttpClientError::from)
    }

    /// `GET /api/localsend/v2/fs/list` — paginated directory listing under
    /// a whitelisted root. `path` is relative to the mount-point root and
    /// uses `/` as the separator; pass `""` to list the root contents.
    /// `sort` is one of `name_asc` / `name_desc` / `size_asc` / `size_desc` /
    /// `mtime_desc` (default `name_asc`).
    pub async fn list_dir(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: String,
        page: u32,
        size: u32,
        sort: String,
    ) -> Result<ListResponse, RsHttpClientError> {
        self.inner
            .list_dir(protocol, ip, port, &path, page as usize, size as usize, &sort)
            .await
            .map(Into::into)
            .map_err(RsHttpClientError::from)
    }

    /// `GET /api/localsend/v2/fs/download?path=...` — stream a single
    /// file from a whitelisted root. Emits [RsFsDownloadEvent]s on [sink]:
    ///
    ///   * `Started { total_size, status }` — once, when headers arrive.
    ///     `status` is `200` for a whole-file fetch, `206` for a Range.
    ///   * `Chunk { bytes }`                — many times, body chunks.
    ///   * `Finished`                       — once, on successful EOF.
    ///   * `Failed { error }`               — once, on any error.
    ///
    /// The sink pattern mirrors [Self::upload]; flutter_rust_bridge
    /// discards the returned `Result` of functions taking a [StreamSink],
    /// so errors are emitted as a `Failed` event rather than returned
    /// (otherwise an uncaught async error would kill the calling isolate).
    ///
    /// `range_start` / `range_end`: when both are `Some`, sends
    /// `Range: bytes=start-end`. When only `start` is `Some`, sends
    /// `Range: bytes=start-` (open-ended). When both are `None`, fetches
    /// the whole file with no Range header.
    #[allow(clippy::too_many_arguments)]
    pub async fn fs_download(
        &self,
        sink: StreamSink<RsFsDownloadEvent>,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: String,
        range_start: Option<u64>,
        range_end: Option<u64>,
        cancel_token: &RsCancellationToken,
    ) {
        let range = match (range_start, range_end) {
            (Some(s), e) => Some((s, e)),
            (None, _) => None,
        };

        let result = async {
            let response = self
                .inner
                .fs_download(protocol, ip, port, &path, range)
                .await
                .map_err(RsHttpClientError::from)?;

            let total_size = response
                .content_length()
                .unwrap_or(0);
            let status = response.status().as_u16();
            let _ = sink.add(RsFsDownloadEvent::Started { total_size, status });

            use futures_util::StreamExt;
            let mut stream = response.bytes_stream();
            let mut transferred: u64 = 0;
            while let Some(chunk) = stream.next().await {
                if cancel_token.inner.is_cancelled() {
                    let _ = sink.add(RsFsDownloadEvent::Cancelled);
                    return Ok(());
                }
                let chunk = chunk.map_err(|e| {
                    RsHttpClientError::Reqwest(localsend::util::error::ErrorChain(&e).to_string())
                })?;
                transferred = transferred.saturating_add(chunk.len() as u64);
                let _ = sink.add(RsFsDownloadEvent::Chunk {
                    bytes: chunk.to_vec(),
                    transferred,
                });
            }

            let _ = sink.add(RsFsDownloadEvent::Finished);
            Ok(())
        }
        .await;

        if let Err(error) = result {
            let _ = sink.add(RsFsDownloadEvent::Failed { error });
        }
    }

    /// `POST /api/localsend/v2/fs/upload` — upload a file to a remote directory.
    /// Implements the session-based upload protocol (init → chunk → finish).
    /// Emits [RsFsUploadEvent]s on [sink].
    ///
    /// The isolate is responsible for reading the file and streaming chunks
    /// to this method via the `binary` parameter. This method handles the
    /// HTTP session management (init, chunk POSTs, finish, cancel).
    #[allow(clippy::too_many_arguments)]
    pub async fn fs_upload(
        &self,
        sink: StreamSink<RsFsUploadEvent>,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        remote_dir: String,
        filename: String,
        file_size: u64,
        binary: stream::Dart2RustStreamReceiver,
        resume_session_id: Option<String>,
        resume_etag: Option<String>,
        resume_offset: Option<u64>,
        cancel_token: &RsCancellationToken,
    ) {
        let result = async {
            // Step 1: Initialize the upload session
            let init_response = self
                .inner
                .fs_upload_init(
                    protocol,
                    ip,
                    port,
                    &remote_dir,
                    &filename,
                    file_size,
                )
                .await
                .map_err(RsHttpClientError::from)?;

            tracing::info!(
                event = "fs.upload.client.init_response",
                "Upload init response: {:?}",
                init_response
            );

            let session_id = init_response["sessionId"]
                .as_str()
                .ok_or_else(|| RsHttpClientError::Other("Missing sessionId in init response".into()))?
                .to_string();

            let etag = init_response["etag"]
                .as_str()
                .unwrap_or("")
                .to_string();

            let received = init_response["received"]
                .as_u64()
                .unwrap_or(0);

            let _ = sink.add(RsFsUploadEvent::Started {
                session_id: session_id.clone(),
                etag,
                received,
            });

            // Step 2: Stream chunks from the binary receiver
            let mut receiver = binary.receiver;
            let mut offset = received;

            while let Some(chunk) = receiver.recv().await {
                if cancel_token.inner.is_cancelled() {
                    // Cancel the session on the server
                    let _ = self
                        .inner
                        .fs_upload_cancel(protocol, ip, port, &session_id)
                        .await;
                    let _ = sink.add(RsFsUploadEvent::Cancelled);
                    return Ok(());
                }

                let chunk_len = chunk.len() as u64;

                // POST the chunk to /fs/upload/:session_id
                let _ = self
                    .inner
                    .fs_upload_chunk(protocol, ip, port, &session_id, chunk, offset, file_size)
                    .await
                    .map_err(RsHttpClientError::from)?;

                offset += chunk_len;
                let _ = sink.add(RsFsUploadEvent::Progress { sent: offset });
            }

            // Step 3: Finalize the upload
            let finish_response = self
                .inner
                .fs_upload_finish(protocol, ip, port, &session_id)
                .await
                .map_err(RsHttpClientError::from)?;

            let final_path = finish_response["path"]
                .as_str()
                .unwrap_or("")
                .to_string();

            let final_size = finish_response["size"]
                .as_u64()
                .unwrap_or(file_size);

            let _ = sink.add(RsFsUploadEvent::Finished {
                path: final_path,
                size: final_size,
            });

            Ok(())
        }
        .await;

        if let Err(error) = result {
            let _ = sink.add(RsFsUploadEvent::Failed { error });
        }
    }

    /// `POST /api/localsend/v2/fs/mkdir` — create a directory on the remote device.
    pub async fn fs_mkdir(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: String,
    ) -> Result<(), RsHttpClientError> {
        self.inner
            .fs_mkdir(protocol, ip, port, &path)
            .await
            .map_err(RsHttpClientError::from)?;
        Ok(())
    }

    /// `GET /api/localsend/v2/fs/stat` — get file/directory metadata.
    pub async fn fs_stat(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: String,
    ) -> Result<StatResponse, RsHttpClientError> {
        let response = self
            .inner
            .fs_stat(protocol, ip, port, &path)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(StatResponse::from_json(response))
    }

    /// `POST /api/localsend/v2/fs/move` — move/rename file or directory.
    pub async fn fs_move(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        from: String,
        to: String,
    ) -> Result<MoveResponse, RsHttpClientError> {
        let response = self
            .inner
            .fs_move(protocol, ip, port, &from, &to)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(MoveResponse::from_json(response))
    }

    /// `POST /api/localsend/v2/fs/delete` — delete files/directories.
    pub async fn fs_delete(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        paths: Vec<String>,
        recycle: bool,
    ) -> Result<DeleteResponse, RsHttpClientError> {
        let paths_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        let response = self
            .inner
            .fs_delete(protocol, ip, port, &paths_refs, recycle)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(DeleteResponse::from_json(response))
    }
}

fn resolve_file_content(
    binary: Option<stream::Dart2RustStreamReceiver>,
    path: Option<String>,
    file_descriptor: Option<i32>,
) -> Result<localsend::model::transfer::FileContent, RsHttpClientError> {
    match (binary, path, file_descriptor) {
        (Some(binary), None, None) => Ok(localsend::model::transfer::FileContent::Stream(
            binary.receiver,
        )),
        (None, Some(path), None) => Ok(localsend::model::transfer::FileContent::Path(path.into())),
        (None, None, Some(file_descriptor)) => {
            #[cfg(target_os = "android")]
            {
                Ok(localsend::model::transfer::FileContent::Fd(file_descriptor))
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = file_descriptor;
                Err(RsHttpClientError::Other(
                    "File descriptors are only supported on Android".into(),
                ))
            }
        }
        _ => Err(RsHttpClientError::Other(
            "Exactly one upload content source must be provided".into(),
        )),
    }
}

/// An event emitted while a file is being uploaded by [RsHttpClient::upload].
#[derive(Clone)]
pub enum RsUploadEvent {
    /// The upload progress as a fraction (0.0 to 1.0). Throttled.
    Progress { progress: f64 },

    /// The upload failed. Always the last event of the stream.
    Failed { error: RsHttpClientError },
}

/// An event emitted while a file is being downloaded by
/// [RsHttpClient::fs_download] (T-009). The stream starts with a single
/// `Started` event, then any number of `Chunk`s, then ends with either
/// `Finished`, `Cancelled`, or `Failed` (mutually exclusive — only one
/// terminal event per stream).
#[derive(Clone)]
pub enum RsFsDownloadEvent {
    /// Headers arrived. `total_size` is `content_length` (0 if the
    /// server did not advertise one). `status` is the HTTP status
    /// code (200 for whole-file, 206 for partial).
    Started { total_size: u64, status: u16 },

    /// A chunk of body bytes. `transferred` is the cumulative byte
    /// count received so far.
    Chunk { bytes: Vec<u8>, transferred: u64 },

    /// Successful end of stream.
    Finished,

    /// The user cancelled the download via the cancel token.
    Cancelled,

    /// The download failed. Always the last event of the stream.
    Failed { error: RsHttpClientError },
}

/// An event emitted while a file is being uploaded by
/// [RsHttpClient::fs_upload] (T-012). The stream starts with a single
/// `Started` event (containing the session ID), then any number of
/// `Progress` events, then ends with either `Finished`, `Cancelled`,
/// or `Failed` (mutually exclusive — only one terminal event per stream).
#[derive(Clone)]
pub enum RsFsUploadEvent {
    /// The upload session was initialized on the server.
    Started {
        /// The session ID for subsequent chunk/finish/cancel requests.
        session_id: String,
        /// The ETag for resume support.
        etag: String,
        /// How many bytes the server already has (for resume).
        received: u64,
    },

    /// Progress update: `sent` is the cumulative byte count sent so far.
    Progress { sent: u64 },

    /// The upload completed successfully.
    Finished {
        /// The final path on the server.
        path: String,
        /// The final size in bytes.
        size: u64,
    },

    /// The user cancelled the upload via the cancel token.
    Cancelled,

    /// The upload failed. Always the last event of the stream.
    Failed { error: RsHttpClientError },
}

#[derive(Clone)]
pub enum RsHttpClientError {
    StatusCode {
        status: u16,
        message: Option<String>,
    },
    Reqwest(String),
    Json(String),
    Io(String),
    Other(String),
}

impl From<ClientError> for RsHttpClientError {
    fn from(e: ClientError) -> Self {
        match e {
            ClientError::StatusCode(e) => RsHttpClientError::StatusCode {
                status: e.status,
                message: e.message,
            },
            ClientError::Reqwest(e) => RsHttpClientError::Reqwest(ErrorChain(&e).to_string()),
            ClientError::Json(e) => RsHttpClientError::Json(e.to_string()),
            ClientError::Io(e) => RsHttpClientError::Io(e.to_string()),
            ClientError::Other(e) => RsHttpClientError::Other(e.to_string()),
            ClientError::Cancelled => RsHttpClientError::Other("Upload cancelled".to_string()),
        }
    }
}

#[frb(mirror(LsHttpClientVersion))]
pub enum _LsHttpClientVersion {
    V2,
    V3,
}

#[frb(mirror(PrepareUploadResult))]
pub struct _PrepareUploadResult {
    pub status_code: u16,
    pub response: Option<PrepareUploadResponseDto>,
}

pub struct ResultWithPublicKeyRegisterResponseDto {
    pub public_key: Option<String>,
    pub body: RegisterResponseDto,
}
