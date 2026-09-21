// T-006: protocol v2.3 capability extension.
//
// The capability set a LocalSend peer advertises. Introduced in protocol
// v2.3; a v2.2 peer does not send the field and is treated as advertising
// the protocol default `{send, receive}` (see `capability_helper.dart`).
//
// The wire values are lowercase to match the protocol spec; the
// `dart_mappable` codegen mirrors that on the Dart side.

import 'package:dart_mappable/dart_mappable.dart';

part 'capability.mapper.dart';

@MappableEnum()
enum Capability {
  /// Send files to other devices (default).
  send,

  /// Receive files from other devices (default).
  receive,

  /// Serve the read-only `fs` namespace (mounted-end, LocalU).
  fs;

  /// The protocol default `{send, receive}` for v2.2 peers that do not
  /// advertise `capabilities`. Mirrors
  /// `localsend::model::capability::default_capabilities` on the Rust side.
  static const Set<Capability> defaultSet = {Capability.send, Capability.receive};
}
