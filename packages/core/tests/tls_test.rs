#![cfg(all(feature = "http", feature = "fs"))]

//! Integration tests for the T-005 "fs namespace requires TLS" gate.
//!
//! Acceptance criteria from `tickets/P1-mvp/T-005-server-tls-enforcement.md`:
//!
//! 1. `tls_off_skips_fs_routes` — `start_with_port({tls: None, enable_fs: true})`
//!    → `GET /api/localsend/v2/fs/roots` returns 404.
//! 2. `tls_on_registers_fs_routes` — same, with `tls = Some(_)`, returns 200
//!    with an empty `{"roots":[]}` body (the default whitelist is empty).
//! 3. `enable_fs_false_skips_routes` — TLS on, `enable_fs = false`, returns 404.
//! 4. `tls_off_emits_error_log` — captures the fixed
//!    `"fs namespace requires TLS; skipping registration"` line via a custom
//!    `tracing-subscriber` writer. The wording is part of the contract
//!    because it seeds the N-SEC-5 audit trail.
//!
//! Each test owns its own server on port 0, so they run in parallel without
//! collisions.

use std::io;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use localsend::crypto::cert::generate_self_signed;
use localsend::fs::FsConfig;
use localsend::http::server::start_with_port;
use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::web::WebConfig;
use localsend::http::server::{ServerConfigV2, TlsConfig};
use localsend::http::state::ClientInfo;
use reqwest::StatusCode;
use tokio::sync::{mpsc, oneshot};

// ===========================================================================
// tracing capture — installed once per test-binary process
// ===========================================================================

/// In-memory `MakeWriter` that appends every formatted log line to a shared
/// `Vec<u8>`. We don't reimplement formatting — `tracing_subscriber::fmt`
/// renders the line (level, timestamp, message, …) and writes the bytes
/// through us unchanged. The buffer ends up with the same content you'd see
/// during a normal test run.
#[derive(Clone)]
struct CaptureWriter(Arc<Mutex<Vec<u8>>>);

impl io::Write for CaptureWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0
            .lock()
            .expect("log buffer poisoned")
            .extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for CaptureWriter {
    type Writer = CaptureWriter;
    fn make_writer(&'a self) -> Self::Writer {
        self.clone()
    }
}

/// Returns the global log buffer, installing the capture subscriber on the
/// first call. Subsequent calls share the same buffer; that's fine here
/// because the four tests either don't care about logs or only assert that
/// the message *appears* somewhere in the captured bytes.
///
/// `try_init` is idempotent at the process level — a second call in the
/// same process is a no-op. The other tests in this binary deliberately do
/// *not* call `try_init`, so within this binary this is the only subscriber
/// installation site.
fn log_buffer() -> Arc<Mutex<Vec<u8>>> {
    static BUF: OnceLock<Arc<Mutex<Vec<u8>>>> = OnceLock::new();
    BUF.get_or_init(|| {
        let buf = Arc::new(Mutex::new(Vec::<u8>::new()));
        let writer = CaptureWriter(buf.clone());
        let _ = tracing_subscriber::fmt()
            .with_writer(writer)
            // We only care about the ERROR line that `fs::register` emits
            // when TLS is missing — keep noise out of the buffer.
            .with_max_level(tracing::Level::ERROR)
            .try_init();
        buf
    })
    .clone()
}

// ===========================================================================
// Test server / client helpers
// ===========================================================================

struct TestServer {
    port: u16,
    /// Held so the channel stays open and the runtime drops the task at
    /// end-of-test rather than the channel closing it mid-test.
    _stop_tx: oneshot::Sender<()>,
}

async fn start_test_server(
    tls: Option<TlsConfig>,
    enable_fs: bool,
    fs_config: Option<FsConfig>,
) -> TestServer {
    let (event_tx, _event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (stop_tx, stop_rx) = oneshot::channel::<()>();

    let handle = start_with_port(
        0,
        tls,
        ClientInfo {
            alias: "T-005 Test".to_string(),
            version: "2.2".to_string(),
            device_model: None,
            device_type: None,
            token: "test-fingerprint".to_string(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
            enable_fs,
        }),
        WebConfig::default(),
        stop_rx,
        fs_config,
    )
    .await
    .expect("Failed to start T-005 test server");

    TestServer {
        port: handle.port(),
        _stop_tx: stop_tx,
    }
}

/// Plain-HTTP reqwest client. Used by the TLS-off tests; reqwest ignores
/// TLS settings for `http://` URLs.
fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .connect_timeout(Duration::from_secs(2))
        .build()
        .expect("reqwest client")
}

/// HTTPS reqwest client that authenticates with the given identity. The
/// test server pins its own certificate as a trust anchor
/// (`CustomClientCertVerifier::try_new`), so the simplest setup is to reuse
/// the server's identity as the client's identity.
fn m_tls_http_client(cert_pem: &str, key_pem: &str) -> reqwest::Client {
    // reqwest's `Identity::from_pem` accepts a single PEM bundle with cert
    // + key concatenated; concatenating here keeps the test self-contained.
    let mut buf = Vec::with_capacity(cert_pem.len() + key_pem.len());
    buf.extend_from_slice(cert_pem.as_bytes());
    buf.extend_from_slice(key_pem.as_bytes());
    reqwest::Client::builder()
        .identity(reqwest::Identity::from_pem(&buf).expect("client identity"))
        .danger_accept_invalid_certs(true)
        .connect_timeout(Duration::from_secs(2))
        .build()
        .expect("reqwest mTLS client")
}

async fn get_fs_roots(client: &reqwest::Client, port: u16, scheme: &str) -> StatusCode {
    let url = format!("{scheme}://127.0.0.1:{port}/api/localsend/v2/fs/roots");
    let resp = client.get(&url).send().await.expect("send");
    resp.status()
}

// ===========================================================================
// Tests
// ===========================================================================

/// TLS off → the dispatcher never installs the fs routes (see
/// `http::server::mod.rs` and `fs::rest::register`), so the request falls
/// through to the catch-all 404.
#[tokio::test]
async fn tls_off_skips_fs_routes() {
    let server = start_test_server(None, true, Some(FsConfig::default())).await;
    let client = http_client();
    let status = get_fs_roots(&client, server.port, "http").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

/// TLS on + `enable_fs = true` → the routes are registered and the handler
/// returns 200 with `{"roots":[]}` (the default whitelist is empty;
/// populated whitelists are exercised by T-003's tests).
#[tokio::test]
async fn tls_on_registers_fs_routes() {
    let identity = generate_self_signed().expect("self-signed cert");
    let tls = TlsConfig {
        cert: identity.certificate_pem.clone(),
        private_key: identity.private_key_pem.clone(),
    };

    let server = start_test_server(Some(tls), true, Some(FsConfig::default())).await;

    // The mTLS handshake requires the client to present a certificate;
    // we reuse the server's identity — the server trusts its own cert.
    let client = m_tls_http_client(&identity.certificate_pem, &identity.private_key_pem);
    let status = get_fs_roots(&client, server.port, "https").await;
    assert_eq!(
        status,
        StatusCode::OK,
        "fs routes must be registered when TLS is on and enable_fs is true"
    );
}

/// TLS on but the operator explicitly disables fs → the routes are not
/// registered, 404. Mirrors the "Disable file sharing" toggle in the
/// settings page (T-005 §6).
#[tokio::test]
async fn enable_fs_false_skips_routes() {
    let identity = generate_self_signed().expect("self-signed cert");
    let tls = TlsConfig {
        cert: identity.certificate_pem.clone(),
        private_key: identity.private_key_pem.clone(),
    };

    let server = start_test_server(Some(tls), false, Some(FsConfig::default())).await;

    let client = m_tls_http_client(&identity.certificate_pem, &identity.private_key_pem);
    let status = get_fs_roots(&client, server.port, "https").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

/// Capture the fixed ERROR log line that the audit-trail seed relies on.
/// `tls_off_skips_fs_routes` already triggers the same line, but that test
/// only checks the response status; this one exists specifically to keep
/// the wording stable — `tracing::error!` is emitted from inside
/// `start_with_port`, *before* the test makes its request, so installing
/// the subscriber up-front is essential.
#[tokio::test]
async fn tls_off_emits_error_log() {
    // Install the capture subscriber BEFORE the server boots: the error is
    // emitted synchronously inside `fs::rest::register`, which runs as
    // part of `start_with_port`.
    let buf = log_buffer();

    let server = start_test_server(None, true, Some(FsConfig::default())).await;
    let client = http_client();
    // The request itself is incidental — we only need the server to have
    // booted (which is when the register() decision fires).
    let _status = get_fs_roots(&client, server.port, "http").await;

    let bytes = buf.lock().expect("log buffer poisoned").clone();
    let captured = String::from_utf8(bytes).expect("log buffer is utf-8");

    assert!(
        captured.contains("fs namespace requires TLS; skipping registration"),
        "expected the fixed T-005 error log message; got:\n{captured}"
    );
}
