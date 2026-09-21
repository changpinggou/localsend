//! Capability bits advertised by a LocalSend peer (T-006).
//!
//! Introduced in protocol v2.3, this is the wire-level vocabulary a device
//! uses to tell its peers what it can do on top of the default
//! `{Send, Receive}` set:
//!
//! - `Send`    — send files to other devices (default).
//! - `Receive` — receive files from other devices (default).
//! - `Fs`      — serve the read-only `/api/localsend/v2/fs/*` namespace, the
//!               LocalU mounted-end feature (T-003, T-005).
//!
//! ## Wire format
//!
//! The capability list is part of the announcement (multicast) and the
//! register / register-response / info payloads. It is **optional**:
//! a v2.2 peer that does not know the field is treated as if it had
//! announced `{Send, Receive}`. A peer that *does* send the field but with
//! an unknown value is rejected — old clients never have to learn the new
//! vocabulary, but new clients reject typos and stale branches.
//!
//! ## Default handling
//!
//! `[Capability::default()]` would be meaningless, so the `Default` impl
//! is purely the single-value fallback for `Capability::default()` calls
//! elsewhere. The protocol-level default `{Send, Receive}` lives in
//! [`default_capabilities`].
//!
//! Tests: `capability_serialize`, `capability_default`,
//! `capability_unknown_field`.

use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// The set of capabilities a peer advertises on the wire.
///
/// `#[serde(rename = "...")]` keeps the wire value lowercase (matching the
/// v2.3 protocol spec) regardless of the Rust variant name.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Capability {
    /// Send files to other devices.
    #[serde(rename = "send")]
    Send,

    /// Receive files from other devices.
    #[serde(rename = "receive")]
    Receive,

    /// Serve the read-only `fs` namespace (mounted-end, LocalU).
    #[serde(rename = "fs")]
    Fs,
}

impl Default for Capability {
    /// `Send` is just a single-value fallback. The protocol-level default
    /// for the *set* is `{Send, Receive}` and lives in [`default_capabilities`].
    fn default() -> Self {
        Capability::Send
    }
}

/// The protocol-level default capability set.
///
/// Used when a peer omits the `capabilities` field entirely (most common
/// case: a v2.2 device that does not know the field exists). Always
/// returns a fresh `HashSet` so callers can mutate it freely.
pub fn default_capabilities() -> HashSet<Capability> {
    HashSet::from([Capability::Send, Capability::Receive])
}

/// Interpret a wire-level capability list, substituting the protocol
/// default when the list is empty.
///
/// An empty list is *not* the same as "has no capabilities": a v2.2 peer
/// advertises no list at all, which the deserializer turns into an empty
/// `Vec`. That case (and only that case) must be upgraded to the default
/// set so the UI can keep treating "no info" as "send + receive".
pub fn parse_capabilities(raw: &[Capability]) -> HashSet<Capability> {
    if raw.is_empty() {
        default_capabilities()
    } else {
        raw.iter().copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capability_serialize() {
        // The round-trip the ticket pins: `vec![Fs]` ↔ `["fs"]`.
        let caps = vec![Capability::Fs];
        let json = serde_json::to_string(&caps).expect("serialize");
        assert_eq!(json, r#"["fs"]"#);

        let parsed: Vec<Capability> = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(parsed, vec![Capability::Fs]);
    }

    #[test]
    fn capability_serialize_lowercase() {
        // All known variants must serialise to the lowercase wire form.
        let json = serde_json::to_string(&vec![
            Capability::Send,
            Capability::Receive,
            Capability::Fs,
        ])
        .expect("serialize");
        assert_eq!(json, r#"["send","receive","fs"]"#);
    }

    #[test]
    fn capability_default() {
        // `None` on the wire (the deserializer turns missing fields into
        // empty Vecs) upgrades to the protocol default set.
        assert_eq!(parse_capabilities(&[]), default_capabilities());
        assert_eq!(
            default_capabilities(),
            HashSet::from([Capability::Send, Capability::Receive])
        );
    }

    #[test]
    fn capability_explicit_set_is_preserved() {
        // A peer that includes `[fs]` advertises exactly that; the
        // default-substitution must NOT clobber an explicit empty-or-non
        // empty list.
        let caps = vec![Capability::Fs];
        let parsed = parse_capabilities(&caps);
        assert_eq!(parsed, HashSet::from([Capability::Fs]));
    }

    #[test]
    fn capability_unknown_field() {
        // A typo / unknown variant on the wire must be rejected. The
        // server-side verifier relies on serde's strict enum matching to
        // catch bad clients early.
        let err = serde_json::from_str::<Vec<Capability>>(r#"["fxs"]"#)
            .expect_err("unknown variant must error");
        // The error is a serde "unknown variant" diagnostic.
        let msg = err.to_string();
        assert!(
            msg.contains("unknown variant") || msg.contains("Fxs"),
            "unexpected error: {msg}"
        );
    }
}
