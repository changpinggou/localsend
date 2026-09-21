// T-006: protocol v2.3 capability helper unit tests.
//
// `parseCapabilitiesFromList` substitutes the protocol default
// `{send, receive}` whenever the peer omits the `capabilities` field
// (legacy v2.2 peers). The Dart-side helper exists so FRB-typed `Set` and
// wire-level `List` (which may be missing / empty) round-trip cleanly.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/model/capability.dart';
import 'package:localsend_isolates/util/capability_helper.dart';

void main() {
  group('parseCapabilitiesFromList', () {
    test('null falls back to protocol default {send, receive}', () {
      final result = parseCapabilitiesFromList(null);
      expect(result, defaultCapabilities);
      expect(result, {Capability.send, Capability.receive});
    });

    test('empty list falls back to protocol default {send, receive}', () {
      // Mirrors the v2.2 wire format: a peer that never sent the field is
      // seen by serde as an empty Vec, which FRB turns into an empty
      // List<dynamic>.
      final result = parseCapabilitiesFromList(const []);
      expect(result, defaultCapabilities);
      expect(result, {Capability.send, Capability.receive});
    });

    test('explicit [fs] is preserved (not overridden by default)', () {
      final result = parseCapabilitiesFromList(const [Capability.fs]);
      expect(result, {Capability.fs});
    });

    test('explicit full set is preserved verbatim', () {
      final result = parseCapabilitiesFromList(
        const [Capability.send, Capability.receive, Capability.fs],
      );
      expect(
        result,
        {Capability.send, Capability.receive, Capability.fs},
      );
    });

    test('drops non-Capability entries (defensive against malformed input)', () {
      // A misbehaving peer could send a string instead of an enum value;
      // the wire-format layer would reject that, but the helper should also
      // be tolerant when called from app code (e.g. log diagnostics).
      final result = parseCapabilitiesFromList(const [
        Capability.send,
        'garbage',
        42,
        null,
        Capability.fs,
      ]);
      expect(result, {Capability.send, Capability.fs});
    });

    test('result is mutable (a fresh Set, not the shared default)', () {
      final a = parseCapabilitiesFromList(const []);
      a.add(Capability.fs);
      final b = parseCapabilitiesFromList(const []);
      expect(b, isNot(contains(Capability.fs)));
      expect(a, contains(Capability.fs));
    });
  });

  group('defaultCapabilities', () {
    test('is the protocol-level {send, receive} pair', () {
      expect(
        defaultCapabilities,
        {Capability.send, Capability.receive},
      );
    });

    test('matches the Dart Capability.defaultSet constant', () {
      // The Rust core uses `default_capabilities()` and the Dart isolate
      // package exposes `Capability.defaultSet`. Both must agree, otherwise
      // a peer that deserialised on the Rust side would see a different
      // default than code that relied on the Dart constant.
      expect(defaultCapabilities, Capability.defaultSet);
    });
  });
}
