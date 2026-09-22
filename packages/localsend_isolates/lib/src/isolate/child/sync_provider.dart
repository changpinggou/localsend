import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_isolates/model/capability.dart';
import 'package:localsend_isolates/model/device_info_result.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:refena_flutter/refena_flutter.dart';

part 'sync_provider.mapper.dart';

/// Represents the state that is synchronized from the main isolate to the child isolate.
/// In other words, the main isolate sends this state to the child isolate.
@MappableClass()
class SyncState with SyncStateMappable {
  final Object rootIsolateToken;
  final StoredSecurityContext securityContext;
  final DeviceInfoResult deviceInfo;
  final String alias;
  final int port;
  final List<String>? networkWhitelist;
  final List<String>? networkBlacklist;
  final ProtocolType protocol;
  final String multicastGroup;
  final int discoveryTimeout;

  final bool serverRunning;
  final bool download;

  /// The capabilities this device advertises on the wire (T-006, protocol
  /// v2.3). Never empty: a v2.2-only app falls back to the protocol default
  /// `{send, receive}` in the caller.
  final Set<Capability> capabilities;

  SyncState({
    required this.rootIsolateToken,
    required this.securityContext,
    required this.deviceInfo,
    required this.alias,
    required this.port,
    required this.networkWhitelist,
    required this.networkBlacklist,
    required this.protocol,
    required this.multicastGroup,
    required this.discoveryTimeout,
    required this.serverRunning,
    required this.download,
    required this.capabilities,
  });

  @override
  String toString() {
    return 'SyncState(securityContext: <SecurityContext>, deviceInfo: $deviceInfo, alias: $alias, port: $port, networkWhitelist: $networkWhitelist, networkBlacklist: $networkBlacklist, protocol: $protocol, multicastGroup: $multicastGroup, discoveryTimeout: $discoveryTimeout, serverRunning: $serverRunning, download: $download, capabilities: $capabilities)';
  }
}

final syncProvider = ReduxProvider<SyncService, SyncState>((ref) {
  throw 'Not initialized';
});

class SyncService extends ReduxNotifier<SyncState> {
  final SyncState initial;

  SyncService({
    required this.initial,
  });

  @override
  SyncState init() => initial;
}

class UpdateSyncStateAction extends ReduxAction<SyncService, SyncState> {
  final SyncState newState;

  UpdateSyncStateAction(this.newState);

  @override
  SyncState reduce() {
    return newState;
  }
}
