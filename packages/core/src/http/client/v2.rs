use super::{ClientError, ResponseExt, ResultWithPublicKey};
use crate::http::client::url::{ApiVersion, TargetUrl};
use crate::http::dto_v2::{
    InfoResponseDtoV2, PrepareDownloadResponseDtoV2, PrepareUploadRequestDtoV2,
    PrepareUploadResponseDtoV2, PrepareUploadResultV2, RegisterDtoV2, RegisterResponseDtoV2,
};
use crate::model::discovery::ProtocolType;
use futures_util::StreamExt;
use reqwest::{Response, StatusCode};
use tokio::io::AsyncWriteExt;
use tokio_util::sync::CancellationToken;

/// HTTP client for LocalSend Protocol v2.2.
pub struct LsHttpClientV2 {
    client: reqwest::Client,
}

impl LsHttpClientV2 {
    /// Creates a new HTTP client for v2.2 protocol.
    ///
    /// # Arguments
    /// * `private_key` - PEM-encoded private key for client certificate
    /// * `cert` - PEM-encoded certificate for client authentication
    /// * `expected_fingerprint` - SHA-256 fingerprint (uppercase hex) the peer
    ///   certificate must have. Enforced during the TLS handshake, so nothing
    ///   is sent to a mismatching peer. [`None`] accepts any valid certificate
    ///   and must only be used for discovery.
    /// * `timeout` - Optional total request timeout (e.g. for discovery scans)
    ///
    /// # Returns
    /// A new client instance or an error if TLS setup fails.
    pub fn try_new(
        private_key: &str,
        cert: &str,
        expected_fingerprint: Option<String>,
        timeout: Option<std::time::Duration>,
    ) -> Result<Self, ClientError> {
        Ok(Self {
            client: super::create_reqwest_client(private_key, cert, expected_fingerprint, timeout)?,
        })
    }

    /// Creates a new HTTP client without TLS client certificate.
    ///
    /// Use this for HTTP-only connections or when client authentication is not needed.
    pub fn try_new_without_cert() -> Result<Self, ClientError> {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let client = reqwest::Client::builder()
            .use_rustls_tls()
            .danger_accept_invalid_certs(true)
            .tls_info(true)
            // Same as `create_reqwest_client`: peers are local, never proxy
            // and never redirect.
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .build()?;

        Ok(Self { client })
    }

    /// Registers with another device for discovery.
    ///
    /// POST /api/localsend/v2/register
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Target device IP address
    /// * `port` - Target device port
    /// * `payload` - Device information to register
    ///
    /// # Returns
    /// Registration result containing the remote device info and optional public key.
    pub async fn register(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: RegisterDtoV2,
    ) -> Result<ResultWithPublicKey<RegisterResponseDtoV2>, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/register",
            params: &[],
        }
        .to_string();

        let res = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .body(serde_json::to_string(&payload)?)
            .send()
            .await?;

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        let (public_key, cert_fingerprint) = match protocol {
            ProtocolType::Https => (
                Some(super::verify_cert_from_res(&res, None)?),
                Some(super::cert_fingerprint_from_res(&res)?),
            ),
            _ => (None, None),
        };

        let body = res.json::<RegisterResponseDtoV2>().await?;

        Ok(ResultWithPublicKey {
            public_key,
            cert_fingerprint,
            body,
        })
    }

    /// Prepares a file upload session with the receiver.
    ///
    /// POST /api/localsend/v2/prepare-upload
    ///
    /// The receiver will decide if this request gets accepted, partially accepted, or rejected.
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Receiver's IP address
    /// * `port` - Receiver's port
    /// * `public_key` - Expected public key for verification (HTTPS only)
    /// * `payload` - Upload request with device info and file metadata
    /// * `pin` - Optional PIN if required by receiver
    /// * `cancel` - Cancellation token; cancelling it aborts the request with
    ///   [`ClientError::Cancelled`]. Aborting closes the connection, which
    ///   tells the receiver that the sender is no longer waiting for a
    ///   decision.
    ///
    /// # Returns
    /// Session ID and accepted file tokens, or an error.
    ///
    /// # Errors
    /// * 204 - No file transfer needed (e.g. text-only transfer)
    /// * 400 - Invalid body
    /// * 401 - PIN required or invalid
    /// * 403 - Rejected by user
    /// * 409 - Blocked by another session
    /// * 429 - Too many requests
    /// * 500 - Unknown error
    pub async fn prepare_upload(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        payload: PrepareUploadRequestDtoV2,
        pin: Option<&str>,
        cancel: CancellationToken,
    ) -> Result<PrepareUploadResultV2, ClientError> {
        let pin_params: &[(&'static str, &str)] = match &pin {
            Some(pin) => &[("pin", pin)],
            None => &[],
        };
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/prepare-upload",
            params: pin_params,
        }
        .to_string();

        let send = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .body(serde_json::to_string(&payload)?)
            .send();

        let res = tokio::select! {
            res = send => res?,
            _ = cancel.cancelled() => return Err(ClientError::Cancelled),
        };

        if protocol == ProtocolType::Https {
            super::verify_cert_from_res(&res, public_key)?;
        }

        let status = res.status();

        if status.as_u16() >= 400 {
            return res.into_error().await;
        }

        if status == StatusCode::NO_CONTENT {
            return Ok(PrepareUploadResultV2 {
                status_code: status.as_u16(),
                response: None,
            });
        }

        let body = res.json::<PrepareUploadResponseDtoV2>().await?;

        Ok(PrepareUploadResultV2 {
            status_code: status.as_u16(),
            response: Some(body),
        })
    }

    /// Uploads a file to the receiver.
    ///
    /// POST /api/localsend/v2/upload?sessionId=...&fileId=...&token=...
    ///
    /// Use the session_id, file_id, and token from prepare_upload response.
    /// This method can be called in parallel for multiple files.
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Receiver's IP address
    /// * `port` - Receiver's port
    /// * `session_id` - Session ID from prepare_upload
    /// * `file_id` - File ID to upload
    /// * `token` - File-specific token from prepare_upload
    /// * `body` - The streaming request body carrying the file content
    /// * `cancel` - Cancellation token; cancelling it aborts the upload with [`ClientError::Cancelled`]
    ///
    /// # Errors
    /// * 400 - Missing parameters
    /// * 403 - Invalid token or IP address
    /// * 409 - Blocked by another session
    /// * 422 - Checksum mismatch
    /// * 500 - Unknown error
    pub async fn upload(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        session_id: &str,
        file_id: &str,
        token: &str,
        body: reqwest::Body,
        cancel: CancellationToken,
    ) -> Result<(), ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/upload",
            params: &[
                ("sessionId", session_id),
                ("fileId", file_id),
                ("token", token),
            ],
        }
        .to_string();

        let res = tokio::select! {
            res = self.client.post(&url).body(body).send() => res?,
            _ = cancel.cancelled() => return Err(ClientError::Cancelled),
        };

        if protocol == ProtocolType::Https {
            super::verify_cert_from_res(&res, public_key)?;
        }

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        Ok(())
    }

    /// Cancels an ongoing file transfer session.
    ///
    /// POST /api/localsend/v2/cancel?sessionId=...
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Receiver's IP address
    /// * `port` - Receiver's port
    /// * `session_id` - Session ID to cancel
    pub async fn cancel(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<(), ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/cancel",
            params: &[("sessionId", session_id)],
        }
        .to_string();

        self.client.post(&url).send().await?;

        Ok(())
    }

    /// Gets device info from a remote device.
    ///
    /// GET /api/localsend/v2/info
    ///
    /// This is primarily for debugging purposes.
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Target device IP address
    /// * `port` - Target device port
    ///
    /// # Returns
    /// Device information including alias, version, device type, fingerprint, etc.
    pub async fn info(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
    ) -> Result<InfoResponseDtoV2, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/info",
            params: &[],
        }
        .to_string();

        let res = self.client.get(&url).send().await?;

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        let body = res.json::<InfoResponseDtoV2>().await?;

        Ok(body)
    }

    /// `GET /api/localsend/v2/fs/roots` — fetch the peer's whitelisted mount
    /// points. The fs namespace is gated by [`crate::fs::register`] on the
    /// server side, so an empty list is the expected response when the peer
    /// has not exposed anything (or the namespace was disabled because TLS
    /// is off).
    #[cfg(feature = "fs")]
    pub async fn list_roots(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
    ) -> Result<crate::fs::RootsResponse, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/roots",
            params: &[],
        }
        .to_string();

        let res = self.client.get(&url).send().await?;

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        let body = res.json::<crate::fs::RootsResponse>().await?;
        Ok(body)
    }

    /// `GET /api/localsend/v2/fs/list` — paginated directory listing under a
    /// whitelisted root. `path` uses `/` as the separator and is relative to
    /// the mount-point root; an empty `path` lists the root contents.
    /// `page` and `size` are clamped server-side to the configured ceiling.
    #[cfg(feature = "fs")]
    pub async fn list_dir(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: &str,
        page: usize,
        size: usize,
        sort: &str,
    ) -> Result<crate::fs::ListResponse, ClientError> {
        let page_str = page.to_string();
        let size_str = size.to_string();
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/list",
            params: &[
                ("path", path),
                ("page", &page_str),
                ("size", &size_str),
                ("sort", sort),
            ],
        }
        .to_string();

        let res = self.client.get(&url).send().await?;

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        let body = res.json::<crate::fs::ListResponse>().await?;
        Ok(body)
    }

    /// Prepares to download files from a sender (Download API).
    ///
    /// POST /api/localsend/v2/prepare-download
    ///
    /// This is used in reverse file transfer mode where the sender hosts the files
    /// and receivers download them.
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Sender's IP address
    /// * `port` - Sender's port
    /// * `session_id` - Optional existing session ID (for browser refresh scenarios)
    /// * `pin` - Optional PIN if required by sender
    ///
    /// # Returns
    /// Sender info, session ID, and available files.
    ///
    /// # Errors
    /// * 401 - PIN required or invalid
    /// * 403 - Rejected
    /// * 429 - Too many requests
    /// * 500 - Unknown error
    pub async fn prepare_download(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: Option<&str>,
        pin: Option<&str>,
    ) -> Result<PrepareDownloadResponseDtoV2, ClientError> {
        let mut params: Vec<(&'static str, &str)> = Vec::new();
        if let Some(session_id) = session_id {
            params.push(("sessionId", session_id));
        }
        if let Some(pin) = pin {
            params.push(("pin", pin));
        }
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/prepare-download",
            params: &params,
        }
        .to_string();

        let res = self.client.post(&url).send().await?;

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        let body = res.json::<PrepareDownloadResponseDtoV2>().await?;

        Ok(body)
    }

    /// Downloads a file from a sender (Download API).
    ///
    /// GET /api/localsend/v2/download?sessionId=...&fileId=...
    ///
    /// This method can be called in parallel for multiple files.
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Sender's IP address
    /// * `port` - Sender's port
    /// * `session_id` - Session ID from prepare_download
    /// * `file_id` - File ID to download
    ///
    /// # Returns
    /// Response containing the file data stream.
    pub async fn download(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
        file_id: &str,
    ) -> Result<Response, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/download",
            params: &[("sessionId", session_id), ("fileId", file_id)],
        }
        .to_string();

        let res = self.client.get(&url).send().await?;

        if res.status() != StatusCode::OK {
            return res.into_error().await;
        }

        Ok(res)
    }

    /// Downloads a file to a writer (convenience method).
    ///
    /// # Arguments
    /// * `protocol` - HTTP or HTTPS
    /// * `ip` - Sender's IP address
    /// * `port` - Sender's port
    /// * `session_id` - Session ID from prepare_download
    /// * `file_id` - File ID to download
    /// * `writer` - AsyncWrite destination for file data
    ///
    /// # Returns
    /// Total bytes written.
    pub async fn download_to_writer<W: tokio::io::AsyncWrite + Unpin>(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
        file_id: &str,
        writer: &mut W,
    ) -> Result<u64, ClientError> {
        let response = self
            .download(protocol, ip, port, session_id, file_id)
            .await?;

        let mut stream = response.bytes_stream();
        let mut total_bytes = 0u64;

        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            writer.write_all(&chunk).await?;
            total_bytes += chunk.len() as u64;
        }

        writer.flush().await?;

        Ok(total_bytes)
    }

    /// `GET /api/localsend/v2/fs/download?path=...` — stream a file
    /// from a whitelisted mount point. T-009: returns the raw
    /// `reqwest::Response` so callers can pipe the body into a stream
    /// (FRB `StreamSink`) or buffer it to disk / memory.
    ///
    /// `range` is `(start, Some(end))` for closed ranges or
    /// `(start, None)` for "from start to EOF". `None` means "no
    /// Range header", i.e. download the whole file.
    #[cfg(feature = "fs")]
    pub async fn fs_download(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: &str,
        range: Option<(u64, Option<u64>)>,
    ) -> Result<reqwest::Response, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/download",
            params: &[("path", path)],
        }
        .to_string();

        tracing::info!(
            event = "fs.download.request",
            url = %url,
            range = ?range,
            "fs download request"
        );

        let mut req = self.client.get(&url);
        if let Some((start, end)) = range {
            let end_str = end.map(|e| e.to_string()).unwrap_or_default();
            req = req.header(reqwest::header::RANGE, format!("bytes={start}-{end_str}"));
        }
        let res = req.send().await?;

        tracing::info!(
            event = "fs.download.response",
            status = %res.status(),
            url = %url,
            "fs download response"
        );

        if !res.status().is_success() && res.status() != reqwest::StatusCode::PARTIAL_CONTENT {
            return res.into_error().await;
        }
        Ok(res)
    }

    /// POST /api/localsend/v2/fs/mkdir — create a directory on the remote
    /// device's whitelisted mount point. T-010: returns the created path
    /// (server may canonicalize it).
    #[cfg(feature = "fs")]
    pub async fn fs_mkdir(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: &str,
    ) -> Result<serde_json::Value, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/mkdir",
            params: &[],
        }
        .to_string();

        tracing::info!(
            event = "fs.mkdir.request",
            url = %url,
            remote_path = %path,
            "fs mkdir request"
        );

        let body = serde_json::json!({ "path": path });
        let res = self.client.post(&url).json(&body).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.mkdir.response",
            status = %status,
            url = %url,
            "fs mkdir response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }

    /// POST /api/localsend/v2/fs/upload/init — initialize an upload session.
    /// T-011: returns session_id, etag, and received offset (for resume).
    #[cfg(feature = "fs")]
    pub async fn fs_upload_init(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        dir: &str,
        filename: &str,
        total_size: u64,
    ) -> Result<serde_json::Value, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/upload/init",
            params: &[("path", dir), ("filename", filename)],
        }
        .to_string();

        tracing::info!(
            event = "fs.upload.init.request",
            url = %url,
            total_size,
            "fs upload init request"
        );

        let body = serde_json::json!({ "total": total_size });
        let res = self.client.post(&url).json(&body).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.upload.init.response",
            status = %status,
            url = %url,
            "fs upload init response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }

    /// POST /api/localsend/v2/fs/upload/:session_id — upload a chunk of data.
    /// T-011: sends raw bytes with Content-Range header for resume support.
    #[cfg(feature = "fs")]
    pub async fn fs_upload_chunk(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
        chunk: bytes::Bytes,
        offset: u64,
        total_size: u64,
    ) -> Result<serde_json::Value, ClientError> {
        // TargetUrl.path is `&'static str`, so build the URL manually when
        // the path contains a dynamic session id.
        let url = format!(
            "{}://{}:{}/api/localsend/v2/fs/upload/{}",
            protocol.as_str(),
            ip,
            port,
            session_id
        );

        let chunk_len = chunk.len() as u64;
        let end = offset + chunk_len - 1;
        let content_range = format!("bytes {offset}-{end}/{total_size}");

        tracing::debug!(
            event = "fs.upload.chunk.request",
            url = %url,
            offset,
            chunk_len,
            total_size,
            "fs upload chunk request"
        );

        let res = self
            .client
            .post(&url)
            .header(reqwest::header::CONTENT_RANGE, content_range)
            .header(reqwest::header::CONTENT_TYPE, "application/octet-stream")
            .body(chunk)
            .send()
            .await?;
        let status = res.status();

        tracing::debug!(
            event = "fs.upload.chunk.response",
            status = %status,
            url = %url,
            "fs upload chunk response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }

    /// POST /api/localsend/v2/fs/upload/:session_id/finish — finalize the upload.
    /// T-011: server fsyncs and renames the temp file to the final path.
    #[cfg(feature = "fs")]
    pub async fn fs_upload_finish(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<serde_json::Value, ClientError> {
        let url = format!(
            "{}://{}:{}/api/localsend/v2/fs/upload/{}/finish",
            protocol.as_str(),
            ip,
            port,
            session_id
        );

        tracing::info!(
            event = "fs.upload.finish.request",
            url = %url,
            "fs upload finish request"
        );

        let res = self.client.post(&url).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.upload.finish.response",
            status = %status,
            url = %url,
            "fs upload finish response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }

    /// DELETE /api/localsend/v2/fs/upload/:session_id — cancel the upload.
    /// T-011: server removes the temp file and session state.
    #[cfg(feature = "fs")]
    pub async fn fs_upload_cancel(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<(), ClientError> {
        let url = format!(
            "{}://{}:{}/api/localsend/v2/fs/upload/{}",
            protocol.as_str(),
            ip,
            port,
            session_id
        );

        tracing::info!(
            event = "fs.upload.cancel.request",
            url = %url,
            "fs upload cancel request"
        );

        let res = self.client.delete(&url).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.upload.cancel.response",
            status = %status,
            url = %url,
            "fs upload cancel response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(())
    }

    /// GET /api/localsend/v2/fs/stat — get file/directory metadata.
    /// T-014: returns size, mtime, etag for resume support.
    #[cfg(feature = "fs")]
    pub async fn fs_stat(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: &str,
    ) -> Result<serde_json::Value, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/stat",
            params: &[("path", path)],
        }
        .to_string();

        tracing::info!(
            event = "fs.stat.request",
            url = %url,
            "fs stat request"
        );

        let res = self.client.get(&url).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.stat.response",
            status = %status,
            url = %url,
            "fs stat response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }

    /// GET /api/localsend/v2/fs/thumbnail — fetch a PNG thumbnail
    /// for an image file. T-021: returns the raw image bytes
    /// (PNG, ≤ 256×256). The server's LRU cache makes repeat
    /// requests O(1).
    ///
    /// `width` and `height` are the requested bounding box; the
    /// server preserves the source's aspect ratio and scales to
    /// fit within the box.
    ///
    /// `#[cfg(feature = "fs-thumb")]` so a build that doesn't
    /// link the `image` crate (just `fs`) still compiles. The
    /// HTTP request itself is plain reqwest GET — the `image`
    /// dependency is only used by the *server* handler.
    #[cfg(feature = "fs-thumb")]
    pub async fn fs_thumbnail(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        path: &str,
        width: u16,
        height: u16,
    ) -> Result<bytes::Bytes, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/thumbnail",
            params: &[
                ("path", path),
                ("w", &width.to_string()),
                ("h", &height.to_string()),
            ],
        }
        .to_string();

        tracing::debug!(
            event = "fs.thumbnail.request",
            url = %url,
            "fs thumbnail request"
        );

        let res = self.client.get(&url).send().await?;
        let status = res.status();

        tracing::debug!(
            event = "fs.thumbnail.response",
            status = %status,
            url = %url,
            "fs thumbnail response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }

        // Stream into bytes — thumbnails are small but we don't
        // know the exact Content-Length up front, so use
        // reqwest's `bytes()` to materialise the response.
        Ok(res.bytes().await?)
    }

    /// POST /api/localsend/v2/fs/move — move/rename file or directory.
    /// T-014: requires confirm=true to prevent accidental moves.
    #[cfg(feature = "fs")]
    pub async fn fs_move(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        from: &str,
        to: &str,
    ) -> Result<serde_json::Value, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/move",
            params: &[],
        }
        .to_string();

        tracing::info!(
            event = "fs.move.request",
            url = %url,
            from = %from,
            to = %to,
            "fs move request"
        );

        let body = serde_json::json!({
            "from": from,
            "to": to,
            "confirm": true
        });

        let res = self.client.post(&url).json(&body).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.move.response",
            status = %status,
            url = %url,
            "fs move response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }

    /// POST /api/localsend/v2/fs/delete — delete files/directories.
    /// T-014: supports batch delete with recycle bin option.
    #[cfg(feature = "fs")]
    pub async fn fs_delete(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        paths: &[&str],
        recycle: bool,
    ) -> Result<serde_json::Value, ClientError> {
        let url = TargetUrl {
            version: ApiVersion::V2,
            protocol: protocol.as_str(),
            host: ip.to_string(),
            port,
            path: "/fs/delete",
            params: &[],
        }
        .to_string();

        tracing::info!(
            event = "fs.delete.request",
            url = %url,
            paths = ?paths,
            recycle = recycle,
            "fs delete request"
        );

        let body = serde_json::json!({
            "paths": paths,
            "recycle": recycle,
            "confirm": true
        });

        let res = self.client.post(&url).json(&body).send().await?;
        let status = res.status();

        tracing::info!(
            event = "fs.delete.response",
            status = %status,
            url = %url,
            "fs delete response"
        );

        if !status.is_success() {
            return res.into_error().await;
        }
        Ok(res.json().await?)
    }
}
