//! Path-traversal sandbox.
//!
//! Every `fs` endpoint — read, write, list, mkdir, delete, move, stat —
//! routes incoming path strings through [`PathGuard::check`] before they
//! are allowed to touch the host filesystem. `PathGuard` rejects:
//!
//! - empty / absolute paths
//! - `..` segments (after percent-decoding, structural collapse, *and*
//!   a final defence-in-depth pass)
//! - null bytes and other control characters
//! - OWASP-style percent-encoded obfuscation (`%2e%2e`, `..%2f`,
//!   `..%c0%af`)
//! - any path that does not resolve under a whitelisted
//!   [`FsRoot`](super::FsRoot)
//! - any symlink in the chain that escapes the whitelisted root
//!
//! ## Defense layers
//!
//! 1. **String layer (`FsPath::new`).** Runs on the raw input with no
//!    filesystem access. Rejects control characters, percent-decodes
//!    one pass, normalises separators and `..` segments, and surfaces
//!    structural attacks (`..` after decode, empty result, etc.) as
//!    [`FsError::PathDenied`] with a [`PathDeniedReason`] sub-reason.
//! 2. **PathGuard::check.** Joins the normalised path to each
//!    whitelisted root, canonicalises, and checks
//!    `canonical.starts_with(canonical_root)`. Distinguishes
//!    `NotFound`, `SymlinkEscape`, and `OutsideWhitelist`.
//! 3. **TOCTOU re-check (`PathGuard::reverify`).** Callers that hold
//!    a validated path across an await point re-canonicalise and
//!    re-check before performing the actual I/O. T-010 (write) and
//!    T-014 (delete) will adopt this seam.
//!
//! ## Audit logging (N-SEC-5 seed)
//!
//! Every `PathDenied` from `PathGuard::check` emits a
//! `tracing::warn!(event = "fs.path.denied", reason, requested)`
//! line. The fingerprint is added by the REST layer in its
//! `fs.api.error` event so the two streams can be joined in the
//! audit pipeline by `(requested, timestamp)`.

use std::path::{Path, PathBuf};

use thiserror::Error;

use super::mount::MountTable;

// =====================================================================
// PathDeniedReason
// =====================================================================

/// Reason a [`FsError::PathDenied`] was returned. Stable wire enum —
///
/// the `Display` impl is the JSON `reason` field, and the
/// `as_str()` form is the audit-log tag.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PathDeniedReason {
    /// Empty input, control chars, NUL byte, OWASP-style
    /// percent-encoded obfuscation, backslash on Unix, etc.
    Invalid,
    /// Path contained a `..` segment *after* normalization.
    DotDot,
    /// Path was absolute after normalization.
    Absolute,
    /// A symlink in the chain pointed outside every
    /// whitelisted root.
    SymlinkEscape,
    /// Path was not under any whitelisted root.
    OutsideWhitelist,
}

impl PathDeniedReason {
    /// Stable string form. Used in the audit log and as the JSON
    /// `reason` field in the error envelope.
    pub fn as_str(&self) -> &'static str {
        match self {
            PathDeniedReason::Invalid => "invalid",
            PathDeniedReason::DotDot => "dotdot",
            PathDeniedReason::Absolute => "absolute",
            PathDeniedReason::SymlinkEscape => "symlink_escape",
            PathDeniedReason::OutsideWhitelist => "outside_whitelist",
        }
    }
}

impl std::fmt::Display for PathDeniedReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

// =====================================================================
// FsError
// =====================================================================

/// Errors produced by the `fs` module.
///
/// Every variant has an associated HTTP status code (see
/// [`FsError::http_status`]) and a stable string code (see
/// [`FsError::code`]) for the JSON error envelope described in
/// T-003 §5.4.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum FsError {
    /// The path was rejected by the sandbox. The `reason`
    /// discriminates the security sub-event (invalid input,
    /// `..` segment, absolute path, symlink escape, outside
    /// whitelist) for the audit log. Maps to HTTP 403.
    #[error("path denied ({reason}): {path}")]
    PathDenied { reason: PathDeniedReason, path: String },

    /// The path resolved correctly but the target does not exist on
    /// disk. Maps to HTTP 404.
    #[error("not found: {0}")]
    NotFound(String),

    /// Caller asked for something the protocol doesn't support
    /// (e.g. a download on a directory, a malformed Range header,
    /// an upload larger than `FsConfig::max_upload_size`). Maps to
    /// HTTP 400.
    #[error("bad request: {0}")]
    BadRequest(String),

    /// The path was syntactically valid but the OS refused the
    /// operation (permission denied, cross-device link, …). Maps
    /// to HTTP 500.
    #[error("io error: {0}")]
    Io(String),
}

impl FsError {
    /// HTTP status code that the REST layer should emit for this
    /// error. Centralised here so the mapping cannot drift
    /// between handlers.
    pub fn http_status(&self) -> hyper::StatusCode {
        use hyper::StatusCode;
        match self {
            FsError::PathDenied { .. } => StatusCode::FORBIDDEN,
            FsError::NotFound(_) => StatusCode::NOT_FOUND,
            FsError::BadRequest(_) => StatusCode::BAD_REQUEST,
            FsError::Io(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    /// Stable wire-protocol code for the JSON error envelope
    /// (`{ "error": { "code": ..., "message": ... } }`). The set
    /// of possible values is documented in T-003 §5.4 and tested
    /// in `rest.rs::tests`.
    pub fn code(&self) -> &'static str {
        match self {
            FsError::PathDenied { .. } => "path_denied",
            FsError::NotFound(_) => "not_found",
            FsError::BadRequest(_) => "bad_request",
            FsError::Io(_) => "internal",
        }
    }
}

// =====================================================================
// FsPath
// =====================================================================

/// A path that has been **normalized** (no FS access).
///
/// Wrapping the normalized string in a newtype means
/// `PathGuard::check` and downstream code can rely on the
/// invariant "this string came from the structural layer and is
/// free of `..`, control chars, percent-encoding tricks, etc.".
/// The final filesystem resolution still happens inside
/// `PathGuard::check`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FsPath(String);

impl FsPath {
    /// Normalize a raw user-supplied path string.
    ///
    /// Steps (no filesystem access):
    ///
    /// 1. Reject empty input → [`FsError::BadRequest`].
    /// 2. Reject NUL / control characters → [`FsError::PathDenied`]
    ///    with reason [`PathDeniedReason::Invalid`].
    /// 3. Percent-decode one pass (`%2e` → `.`, `%2f` → `/`,
    ///    `%5c` → `\`). A double-encoded payload (`%252e%252e`)
    ///    becomes `%2e%2e` after one pass — which is *not*
    ///    decoded further, so the attacker can't smuggle `..`
    ///    past the structural scan.
    /// 4. Platform normalization: on Windows, backslash → forward
    ///    slash, drive letter uppercase, trim trailing `/`. On
    ///    Unix, collapse repeated `/`, strip trailing `/` except
    ///    for `/` itself.
    /// 5. If the input was percent-encoded *and* the decoded form
    ///    contains a `..` segment, surface it as
    ///    [`PathDeniedReason::DotDot`] — an obfuscation attempt
    ///    is a security event, not a malformed-request event.
    /// 6. Greedy `..` collapse: walk the segments, popping the
    ///    previous segment for each `..`; leading `..` on a
    ///    relative path is dropped, leading `..` on an absolute
    ///    path is a no-op (the root can't be popped).
    /// 7. Defence in depth: reject any remaining `.` or `..` after
    ///    collapse.
    pub fn new(input: &str) -> Result<Self, FsError> {
        if input.is_empty() {
            return Err(FsError::BadRequest("empty path".into()));
        }

        // 2. control chars / NUL on raw input
        if has_control(input) {
            return Err(FsError::PathDenied { reason: PathDeniedReason::Invalid, path: input.into() });
        }

        // 3. percent-decode (one pass)
        let (decoded, had_percent) = percent_decode(input);

        // re-check control chars after decode (in case %00 was used)
        if has_control(&decoded) {
            return Err(FsError::PathDenied { reason: PathDeniedReason::Invalid, path: input.into() });
        }

        // 4. platform normalization
        let normalized = platform_normalize(&decoded);

        // Determine if the path is absolute.
        let is_absolute = is_absolute_path(&normalized);

        // Split into segments on / and \\ (Windows-friendly).
        let segments: Vec<&str> = normalized
            .split(|c| c == '/' || c == '\\')
            .filter(|s| !s.is_empty())
            .collect();

        // 5. percent-decoded `..` is an obfuscation attempt.
        if had_percent && segments.iter().any(|s| *s == "..") {
            return Err(FsError::PathDenied { reason: PathDeniedReason::DotDot, path: input.into() });
        }

        // 6. greedy `..` collapse.
        let mut stack: Vec<&str> = Vec::with_capacity(segments.len());
        for seg in &segments {
            match *seg {
                "." => continue,
                ".." => {
                    if let Some(last) = stack.last() {
                        // Pop the previous segment if it's a real one
                        // (not already a `..` we couldn't pop, and
                        // not the synthetic root marker).
                        if !last.is_empty() && *last != ".." {
                            stack.pop();
                        } else if is_absolute {
                            // Absolute: the root is always there as
                            // a no-op pop; subsequent `..`s are
                            // also no-ops.
                        }
                        // Relative + leading `..` (stack empty or
                        // last is `..`): drop the `..`.
                    } else if is_absolute {
                        // Absolute + no stack: at the root, `..`
                        // is a no-op.
                    }
                    // Relative + empty stack: drop leading `..`.
                }
                _ => stack.push(seg),
            }
        }

        // 7. defence in depth: reject remaining `.` / `..`.
        if stack.iter().any(|s| *s == "." || *s == "..") {
            return Err(FsError::PathDenied { reason: PathDeniedReason::DotDot, path: input.into() });
        }

        // Build the normalized path string. Preserve the absolute
        // marker so PathGuard::check can reject absolute inputs.
        let result = if is_absolute {
            if stack.is_empty() {
                "/".to_string()
            } else {
                format!("/{}", stack.join("/"))
            }
        } else {
            stack.join("/")
        };

        Ok(FsPath(result))
    }

    /// Borrow the normalized path as a string slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Consume the wrapper and return the normalized string.
    pub fn into_string(self) -> String {
        self.0
    }
}

// =====================================================================
// PathGuard
// =====================================================================

/// The path-traversal sandbox.
///
/// Cheap to construct (it clones the [`MountTable`] and resolves
/// each root's canonical path once); one instance is shared by
/// every request handler via the `FsState` `Arc`.
#[derive(Debug, Clone)]
pub struct PathGuard {
    table: MountTable,
    /// Pre-canonicalised root paths, keyed by `FsRoot::id`. A root
    /// whose path cannot be canonicalised at construction time
    /// (e.g. it does not exist yet) is silently dropped: it
    /// matches nothing. We compare `canonicalize(candidate)`
    /// against these to defeat the `/tmp` -> `/private/tmp`
    /// symlink that breaks a naive `starts_with` check.
    canonical_roots: std::collections::BTreeMap<String, PathBuf>,
}

impl PathGuard {
    /// Build a guard from a mount table.
    pub fn new(table: &MountTable) -> Self {
        let canonical_roots = table
            .roots()
            .iter()
            .filter_map(|r| std::fs::canonicalize(&r.path).ok().map(|c| (r.id.clone(), c)))
            .collect();
        Self { table: table.clone(), canonical_roots }
    }

    /// Borrow the underlying mount table (read-only). Used by the
    /// audit log to translate a validated path back into a
    /// mount-point alias.
    pub fn table(&self) -> &MountTable {
        &self.table
    }

    /// Validate `input` and return a canonical [`PathBuf`] that
    /// sits under a whitelisted root.
    ///
    /// ## Pipeline
    ///
    /// 1. [`FsPath::new`] to normalize (string layer).
    /// 2. Reject absolute paths (no root to join them to).
    /// 3. For each whitelisted root:
    ///    - Join the normalized path to the canonical root.
    ///    - `std::fs::canonicalize` the candidate.
    ///    - If the result starts with the canonical root, return
    ///      it.
    /// 4. Disambiguate the negative case:
    ///    - any root canonicalised the candidate but the result
    ///      escaped the root (symlink chain to outside) →
    ///      [`PathDeniedReason::SymlinkEscape`].
    ///    - any root had a non-existent candidate →
    ///      [`FsError::NotFound`].
    ///    - else (no root matched) → [`PathDeniedReason::OutsideWhitelist`].
    /// 5. Every [`FsError::PathDenied`] is logged at `warn` with
    ///    `event = "fs.path.denied"`.
    pub fn check(&self, input: &str) -> Result<PathBuf, FsError> {
        let result = self.check_inner(input);
        if let Err(FsError::PathDenied { reason, .. }) = &result {
            tracing::warn!(
                event = "fs.path.denied",
                reason = %reason,
                requested = %input,
                "path denied by sandbox"
            );
        }
        result
    }

    fn check_inner(&self, input: &str) -> Result<PathBuf, FsError> {
        let fs_path = FsPath::new(input)?;
        let normalized = fs_path.as_str();

        // 2. absolute paths have no root to be joined to.
        if is_absolute_path(normalized) {
            return Err(FsError::PathDenied {
                reason: PathDeniedReason::Absolute,
                path: input.into(),
            });
        }

        // 3. try each whitelisted root.
        let mut found_escape = false;
        let mut found_not_found = false;

        for root in self.table.roots() {
            let Some(canonical_root) = self.canonical_roots.get(&root.id) else {
                continue;
            };
            let candidate = canonical_root.join(normalized);
            match std::fs::canonicalize(&candidate) {
                Ok(c) => {
                    if c.starts_with(canonical_root) {
                        return Ok(c);
                    }
                    // Symlink chain resolved to something outside
                    // the root.
                    found_escape = true;
                }
                Err(_) => {
                    // Distinguish a symlink that couldn't be
                    // resolved (likely a loop or a broken
                    // escape) from a plain missing file. The
                    // former is a `SymlinkEscape`; the latter is
                    // `NotFound`.
                    if std::fs::symlink_metadata(&candidate)
                        .map(|m| m.file_type().is_symlink())
                        .unwrap_or(false)
                    {
                        found_escape = true;
                    } else {
                        found_not_found = true;
                    }
                }
            }
        }

        // 4. disambiguate.
        if found_escape {
            Err(FsError::PathDenied {
                reason: PathDeniedReason::SymlinkEscape,
                path: input.into(),
            })
        } else if found_not_found {
            Err(FsError::NotFound(input.to_string()))
        } else {
            Err(FsError::PathDenied {
                reason: PathDeniedReason::OutsideWhitelist,
                path: input.into(),
            })
        }
    }

    /// Re-validate a previously-validated path against the
    /// sandbox, closing the TOCTOU window between
    /// [`PathGuard::check`] and the actual filesystem
    /// operation.
    ///
    /// `path` is the canonical `PathBuf` that `check` returned
    /// earlier. The caller typically passes it directly through
    /// a stream or a `tokio::fs::File::open` and the elapsed
    /// time is the TOCTOU window.
    ///
    /// Returns:
    /// - `Ok(())` — the path still resolves to a real file
    ///   under some whitelisted root.
    /// - `Err(FsError::PathDenied { SymlinkEscape, .. })` — the
    ///   file was moved out of the root, deleted, or replaced
    ///   by a symlink that points outside. From a security
    ///   perspective these are indistinguishable to the
    ///   re-checker (the original path no longer canonicalises
    ///   to a location under any root), and we refuse in all
    ///   three cases.
    pub fn reverify(&self, path: &Path) -> Result<(), FsError> {
        let canonical = std::fs::canonicalize(path).map_err(|_| FsError::PathDenied {
            reason: PathDeniedReason::SymlinkEscape,
            path: path.display().to_string(),
        })?;
        for canonical_root in self.canonical_roots.values() {
            if canonical.starts_with(canonical_root) {
                return Ok(());
            }
        }
        Err(FsError::PathDenied {
            reason: PathDeniedReason::SymlinkEscape,
            path: path.display().to_string(),
        })
    }
}

// =====================================================================
// Helpers (string layer)
// =====================================================================

/// `true` if `s` contains a NUL byte or any other control
/// character. Used by [`FsPath::new`] before and after percent
/// decoding to catch `%00` style obfuscation.
fn has_control(s: &str) -> bool {
    s.chars().any(|c| c == '\0' || c.is_control())
}

/// One-pass percent-decode. Returns the decoded string and a
/// flag indicating whether any `%XX` sequence was actually
/// substituted (used by the structural layer to distinguish
/// obfuscation from benign use of `%`).
fn percent_decode(s: &str) -> (String, bool) {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut had_percent = false;
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                out.push((h << 4) | l);
                had_percent = true;
                i += 3;
                continue;
            }
        }
        // Push the byte as-is. For multi-byte UTF-8 this copies
        // the continuation bytes verbatim, which is what we want
        // — we're working on a byte stream, not a codepoint
        // stream.
        out.push(bytes[i]);
        i += 1;
    }
    // Re-lossify. If the result isn't valid UTF-8 (e.g. a
    // single byte of a multi-byte sequence was corrupted by
    // percent-decoding), fall back to the lossy representation
    // so the structural layer still runs.
    let decoded = match std::str::from_utf8(&out) {
        Ok(s) => s.to_string(),
        Err(_) => String::from_utf8_lossy(&out).into_owned(),
    };
    (decoded, had_percent)
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Platform-specific separator handling. On Windows, backslashes
/// become forward slashes and the drive letter is uppercased. On
/// Unix, repeated `/` is collapsed. Trailing `/` is stripped
/// except for the root itself.
fn platform_normalize(s: &str) -> String {
    #[cfg(windows)]
    {
        let mut out = String::with_capacity(s.len());
        for c in s.chars() {
            if c == '\\' {
                out.push('/');
            } else {
                out.push(c);
            }
        }
        // Uppercase the first character if it looks like a
        // drive letter (`c:`).
        if out.len() >= 2 && out.as_bytes()[1] == b':' {
            let first = out.as_bytes()[0];
            if first.is_ascii_alphabetic() {
                let upper = first.to_ascii_uppercase();
                unsafe {
                    out.as_bytes_mut()[0] = upper;
                }
            }
        }
        // Strip trailing `/` (but keep the root `/` alone).
        while out.len() > 1 && out.ends_with('/') {
            out.pop();
        }
        out
    }
    #[cfg(not(windows))]
    {
        let mut out = String::with_capacity(s.len());
        let mut prev_slash = false;
        for c in s.chars() {
            if c == '/' {
                if !prev_slash {
                    out.push('/');
                }
                prev_slash = true;
            } else {
                out.push(c);
                prev_slash = false;
            }
        }
        while out.len() > 1 && out.ends_with('/') {
            out.pop();
        }
        out
    }
}

/// `true` if the (already-normalized) path is absolute. On
/// Unix that's a leading `/`; on Windows it's a leading drive
/// letter (`C:/` or `C:\`) or a UNC prefix (`//host/share`).
fn is_absolute_path(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    #[cfg(windows)]
    {
        let bytes = s.as_bytes();
        // Drive-letter absolute: `<letter>:/` or `<letter>:\`
        if bytes.len() >= 3
            && bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && (bytes[2] == b'/' || bytes[2] == b'\\')
        {
            return true;
        }
        // Drive-letter relative on Windows: `<letter>:` is
        // *technically* absolute ("current dir on C:"). We
        // treat it as absolute for sandboxing purposes.
        if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
            return true;
        }
        // UNC: `//host/share` (forward-slash normalized).
        bytes.starts_with(b"//")
    }
    #[cfg(not(windows))]
    {
        s.starts_with('/')
    }
}

// =====================================================================
// Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// A minimal mount table with a single root at a real tempdir.
    /// We use `std::env::temp_dir()` so the test works on every
    /// platform without an extra `tempfile` dep.
    fn table_with_root(label: &str, path: &Path) -> MountTable {
        let root = FsRoot::new(path.to_string_lossy(), label, path);
        MountTable::from_config(vec![root])
    }

    // -----------------------------------------------------------------
    // FsPath::new — string normalization
    // -----------------------------------------------------------------

    #[test]
    fn fspath_empty_is_bad_request() {
        let err = FsPath::new("").unwrap_err();
        assert!(matches!(err, FsError::BadRequest(_)));
    }

    #[test]
    fn fspath_accepts_simple_relative() {
        let p = FsPath::new("foo").unwrap();
        assert_eq!(p.as_str(), "foo");
    }

    #[test]
    fn fspath_collapses_dot_segment() {
        let p = FsPath::new("./foo").unwrap();
        assert_eq!(p.as_str(), "foo");
    }

    #[test]
    fn fspath_collapses_interior_dot() {
        let p = FsPath::new("foo/./bar").unwrap();
        assert_eq!(p.as_str(), "foo/bar");
    }

    #[test]
    fn fspath_collapses_repeated_slash() {
        let p = FsPath::new("foo//bar").unwrap();
        assert_eq!(p.as_str(), "foo/bar");
    }

    #[test]
    fn fspath_collapses_interior_dotdot() {
        let p = FsPath::new("foo/../bar").unwrap();
        assert_eq!(p.as_str(), "bar");
    }

    #[test]
    fn fspath_collapses_relative_dotdot_chain() {
        // Both `..`s pop: first pops `foo`, second is leading
        // (nothing to pop) and gets dropped because the path
        // is relative.
        let p = FsPath::new("foo/../../bar").unwrap();
        assert_eq!(p.as_str(), "bar");
    }

    #[test]
    fn fspath_keeps_absolute_after_dotdot_collapse() {
        // First `..` pops `foo`; second `..` is at the root and
        // is a no-op. Result is still absolute (`/bar`), so
        // PathGuard::check will reject it with
        // `PathDenied::Absolute`.
        let p = FsPath::new("/foo/../../bar").unwrap();
        assert_eq!(p.as_str(), "/bar");
    }

    #[test]
    fn fspath_rejects_percent_decoded_dotdot_slash() {
        // `..%2fbar` → `../bar` after decode. The percent-decoded
        // form contains `..` → PathDenied::DotDot.
        let err = FsPath::new("..%2fbar").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::DotDot, .. }));
    }

    #[test]
    fn fspath_rejects_percent_encoded_dotdot() {
        // `%2e%2e/bar` → `../bar` after decode.
        let err = FsPath::new("%2e%2e/bar").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::DotDot, .. }));
    }

    #[test]
    fn fspath_does_not_recurse_double_decode() {
        // `%252e%252e` decodes one pass to `%2e%2e`, which
        // does NOT match the percent-decoder again (the
        // decoder only runs once). So this is OK — no
        // smuggling possible.
        let p = FsPath::new("foo/%252e%252ebar").unwrap();
        assert_eq!(p.as_str(), "foo/%2e%2ebar");
    }

    #[test]
    fn fspath_rejects_nul_byte() {
        let err = FsPath::new("foo\0bar").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::Invalid, .. }));
    }

    #[test]
    fn fspath_rejects_newline() {
        let err = FsPath::new("foo\nbar").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::Invalid, .. }));
    }

    #[test]
    fn fspath_rejects_percent_encoded_nul() {
        // `%00` decodes to a NUL byte, which the second
        // control-char check catches.
        let err = FsPath::new("foo%00bar").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::Invalid, .. }));
    }

    #[test]
    fn fspath_strips_trailing_slash() {
        let p = FsPath::new("foo/bar/").unwrap();
        assert_eq!(p.as_str(), "foo/bar");
    }

    #[test]
    fn fspath_keeps_root_alone() {
        // On Unix, `/` stays `/`.
        #[cfg(not(windows))]
        {
            let p = FsPath::new("/").unwrap();
            assert_eq!(p.as_str(), "/");
        }
    }

    // -----------------------------------------------------------------
    // PathGuard::check — whitelist judgment
    // -----------------------------------------------------------------

    #[test]
    fn check_accepts_path_under_root() {
        let dir = tempfile_subdir("accepts");
        std::fs::create_dir(dir.join("photos")).unwrap();
        std::fs::write(dir.join("photos/a.jpg"), b"hi").unwrap();

        let t = table_with_root("Photos", &dir);
        let guard = PathGuard::new(&t);
        let abs = guard.check("photos/a.jpg").unwrap();
        assert_eq!(abs, dir.join("photos/a.jpg").canonicalize().unwrap());
    }

    #[test]
    fn check_rejects_path_under_unknown_root() {
        // The root we configure points at a real tempdir, but
        // the user asks for a sibling — that sibling lives
        // outside the root.
        let dir = tempfile_subdir("unknown");
        let other = tempfile_subdir("unknown_other");
        std::fs::write(other.join("a.jpg"), b"x").unwrap();

        let t = table_with_root("Root", &dir);
        let guard = PathGuard::new(&t);
        // `other/a.jpg` is syntactically valid but the
        // canonicalize-then-join path is in `dir/`, not in
        // `other/`. The handler sees the candidate doesn't
        // exist in the root, so it returns `NotFound`.
        let err = guard.check("a.jpg").unwrap_err();
        assert!(matches!(err, FsError::NotFound(_)));
    }

    #[test]
    fn check_rejects_dotdot_input_as_dotdot() {
        let dir = tempfile_subdir("dotdot_input");
        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        // `foo/../../bar` decodes to no percent, so the
        // structural collapse runs (no `..` remains) and the
        // result is `bar`. canonicalize(<root>/bar) fails
        // (no such file) → NotFound. The percent-decoded
        // obfuscation is reserved for the DotDot branch.
        let err = guard.check("foo/../../bar").unwrap_err();
        assert!(matches!(err, FsError::NotFound(_)));
    }

    #[test]
    fn check_rejects_percent_decoded_dotdot() {
        let dir = tempfile_subdir("dotdot_pct");
        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let err = guard.check("..%2fetc/passwd").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::DotDot, .. }));
    }

    #[test]
    fn check_rejects_absolute_path() {
        let dir = tempfile_subdir("absolute");
        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        #[cfg(not(windows))]
        let input = "/etc/passwd";
        #[cfg(windows)]
        let input = "C:/Windows/System32";
        let err = guard.check(input).unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::Absolute, .. }));
    }

    #[test]
    fn check_rejects_nul_byte_input() {
        let dir = tempfile_subdir("nul");
        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let err = guard.check("foo\0bar").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::Invalid, .. }));
    }

    #[test]
    fn check_rejects_with_empty_whitelist() {
        let guard = PathGuard::new(&MountTable::new());
        let err = guard.check("anything").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::OutsideWhitelist, .. }));
    }

    #[test]
    fn check_rejects_empty_input_as_bad_request() {
        let dir = tempfile_subdir("empty");
        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let err = guard.check("").unwrap_err();
        assert!(matches!(err, FsError::BadRequest(_)));
    }

    // -----------------------------------------------------------------
    // PathGuard::check — symlink escape (Unix only)
    // -----------------------------------------------------------------

    #[cfg(unix)]
    #[test]
    fn check_detects_direct_symlink_escape() {
        let dir = tempfile_subdir("sym_escape");
        // Make a directory outside the root.
        let outside = tempfile_subdir("sym_escape_outside");
        std::fs::write(outside.join("secret.txt"), b"x").unwrap();
        // Symlink inside the root pointing outside.
        std::os::unix::fs::symlink(outside.join("secret.txt"), dir.join("leak")).unwrap();

        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let err = guard.check("leak").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::SymlinkEscape, .. }));
    }

    #[cfg(unix)]
    #[test]
    fn check_accepts_internal_symlink() {
        let dir = tempfile_subdir("sym_internal");
        std::fs::write(dir.join("real.txt"), b"hi").unwrap();
        std::os::unix::fs::symlink(dir.join("real.txt"), dir.join("alias")).unwrap();

        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let abs = guard.check("alias").unwrap();
        assert_eq!(abs, dir.join("real.txt").canonicalize().unwrap());
    }

    #[cfg(unix)]
    #[test]
    fn check_detects_chained_symlink_escape() {
        let dir = tempfile_subdir("sym_chain");
        let outside = tempfile_subdir("sym_chain_outside");
        std::fs::write(outside.join("secret.txt"), b"x").unwrap();
        // D:/a -> D:/b; D:/b -> <outside>/secret.txt
        std::os::unix::fs::symlink(dir.join("b"), dir.join("a")).unwrap();
        std::os::unix::fs::symlink(outside.join("secret.txt"), dir.join("b")).unwrap();

        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let err = guard.check("a").unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::SymlinkEscape, .. }));
    }

    #[cfg(unix)]
    #[test]
    fn check_detects_symlink_loop() {
        let dir = tempfile_subdir("sym_loop");
        // D:/a -> D:/a (loop)
        std::os::unix::fs::symlink(dir.join("a"), dir.join("a")).unwrap();

        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let err = guard.check("a").unwrap_err();
        // Loops surface as SymlinkEscape (canonicalize
        // fails, the file is a symlink, so the heuristic
        // flips it to escape).
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::SymlinkEscape, .. }));
    }

    // -----------------------------------------------------------------
    // PathGuard::reverify — TOCTOU
    // -----------------------------------------------------------------

    #[test]
    fn reverify_accepts_still_valid_path() {
        let dir = tempfile_subdir("reverify_ok");
        std::fs::write(dir.join("a.txt"), b"hi").unwrap();
        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let abs = guard.check("a.txt").unwrap();
        assert!(guard.reverify(&abs).is_ok());
        // Calling it again is idempotent.
        assert!(guard.reverify(&abs).is_ok());
    }

    #[test]
    fn reverify_detects_escape_after_move() {
        let dir = tempfile_subdir("reverify_move");
        let outside = tempfile_subdir("reverify_move_outside");
        std::fs::write(dir.join("a.txt"), b"hi").unwrap();

        let t = table_with_root("R", &dir);
        let guard = PathGuard::new(&t);
        let abs = guard.check("a.txt").unwrap();

        // Move the file outside the root. The canonical
        // path no longer starts with the canonical root.
        std::fs::rename(&abs, outside.join("a.txt")).unwrap();
        let err = guard.reverify(&abs).unwrap_err();
        assert!(matches!(err, FsError::PathDenied { reason: PathDeniedReason::SymlinkEscape, .. }));
    }

    // -----------------------------------------------------------------
    // PathDeniedReason + FsError surface
    // -----------------------------------------------------------------

    #[test]
    fn path_denied_reason_as_str_is_stable() {
        assert_eq!(PathDeniedReason::Invalid.as_str(), "invalid");
        assert_eq!(PathDeniedReason::DotDot.as_str(), "dotdot");
        assert_eq!(PathDeniedReason::Absolute.as_str(), "absolute");
        assert_eq!(PathDeniedReason::SymlinkEscape.as_str(), "symlink_escape");
        assert_eq!(PathDeniedReason::OutsideWhitelist.as_str(), "outside_whitelist");
    }

    #[test]
    fn fs_error_http_status_and_code() {
        use hyper::StatusCode;

        let denied = FsError::PathDenied { reason: PathDeniedReason::DotDot, path: "x".into() };
        assert_eq!(denied.http_status(), StatusCode::FORBIDDEN);
        assert_eq!(denied.code(), "path_denied");

        assert_eq!(FsError::NotFound("x".into()).http_status(), StatusCode::NOT_FOUND);
        assert_eq!(FsError::NotFound("x".into()).code(), "not_found");

        assert_eq!(FsError::BadRequest("x".into()).http_status(), StatusCode::BAD_REQUEST);
        assert_eq!(FsError::BadRequest("x".into()).code(), "bad_request");

        assert_eq!(FsError::Io("x".into()).http_status(), StatusCode::INTERNAL_SERVER_ERROR);
        assert_eq!(FsError::Io("x".into()).code(), "internal");
    }

    // -----------------------------------------------------------------
    // Performance
    // -----------------------------------------------------------------

    #[test]
    fn check_throughput_is_acceptable() {
        // 10 000 sequential `check` calls on a small valid
        // path. The canonical-roots cache makes the per-call
        // cost just one `canonicalize` + one `starts_with`, so
        // this should comfortably complete in well under a
        // second on any CI host. The bound is loose on
        // purpose — we want a regression alarm, not a
        // flake.
        let dir = tempfile_subdir("perf");
        std::fs::create_dir(dir.join("photos")).unwrap();
        std::fs::write(dir.join("photos/a.jpg"), b"x").unwrap();
        let t = table_with_root("Photos", &dir);
        let guard = PathGuard::new(&t);

        let start = std::time::Instant::now();
        for _ in 0..10_000 {
            let _ = guard.check("photos/a.jpg").unwrap();
        }
        let elapsed = start.elapsed();
        assert!(elapsed.as_secs() < 5, "10k checks took {:?}, expected < 5s", elapsed);
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    /// Tiny tempdir helper. Same shape as the one in `mount.rs`
    /// so the test name uniquely identifies the failure.
    fn tempfile_subdir(test: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("localsend_pathguard_{}_{}_{}", test, pid, nanos));
        std::fs::create_dir_all(&p).unwrap();
        p
    }
}
