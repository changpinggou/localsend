// T-006: protocol v2.3 capability helper.
//
// Substitutes the protocol default `{send, receive}` when a peer omits
// the `capabilities` field. The Rust core does the same substitution at
// the discovery boundary; the Dart-side helper exists so the FRB `Set`
// (which is always present, never empty) and the wire-level list
// (which may be empty / missing) round-trip cleanly in app code.

import 'package:localsend_isolates/model/capability.dart';

/// The protocol default `{send, receive}` for a v2.2 peer that does not
/// advertise the `capabilities` field.
const Set<Capability> defaultCapabilities = {
  Capability.send,
  Capability.receive,
};

/// Apply the default-substitution rule to a wire-level capability list.
///
/// The Rust core already substitutes the default before a peer reaches
/// the Dart side, so this helper exists mostly to support app code that
/// wants to reason about the wire format (e.g. tests, log diagnostics).
/// Passing `null` or an empty list returns a fresh copy of
/// [defaultCapabilities]; any non-empty list is preserved verbatim.
Set<Capability> parseCapabilitiesFromList(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) {
    return Set.of(defaultCapabilities);
  }
  return raw
      .whereType<Capability>()
      .toSet();
}
