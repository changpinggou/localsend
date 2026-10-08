import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('FsThumbnail');

/// In-memory LRU cache for remote thumbnails.
///
/// Key: `"${fingerprint}:${path}:${w}x${h}"` — includes dimensions because
/// the server resizes lossily; a 64×64 entry cannot serve a 256×256 request.
/// Value: raw PNG bytes returned by the server (the `image` 0.25 crate's
/// WebP encoder is broken, so the server sends PNG).
///
/// Capacity is soft-capped at [maxEntries]; on overflow the oldest entry
/// (head of the LinkedHashMap) is evicted. Each thumbnail is ~20-30 KB
/// at 256×256, so 200 entries ≈ 4-6 MB — acceptable for a browsing session.
class FsThumbnailCache {
  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap();
  final int maxEntries;

  FsThumbnailCache({this.maxEntries = 200});

  Uint8List? get(String key) => _map[key];

  void put(String key, Uint8List value) {
    // Re-insert to move to tail (MRU position) for LRU semantics.
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();
}

/// Provider that fetches remote thumbnails with an LRU cache.
///
/// Follows the same direct-FRB pattern as `fs_mutation_provider.dart`:
/// creates a pinned HTTPS client per call, calls `client.fsThumbnail()`,
/// and returns raw PNG bytes. No dedicated isolate — thumbnails are
/// small (< 256×256) and fast (~50-200ms on LAN).
final fsThumbnailProvider = NotifierProvider<FsThumbnailService, FsThumbnailState>((ref) {
  return FsThumbnailService();
});

class FsThumbnailState {
  final FsThumbnailCache cache;

  /// Tracks in-flight requests to avoid duplicate fetches for the same key.
  final Map<String, Future<Uint8List?>> pendingRequests = {};

  FsThumbnailState({required this.cache});
}

class FsThumbnailService extends Notifier<FsThumbnailState> {
  static const _thumbDim = 128;

  @override
  FsThumbnailState init() => FsThumbnailState(cache: FsThumbnailCache());

  /// Fetches a thumbnail for a remote file.
  ///
  /// [device] is the target device (provides IP/port/fingerprint).
  /// [fullPath] is the remote path relative to the mount-point root.
  /// Returns `null` if the request fails (caller should fall back to an icon).
  ///
  /// Identical concurrent requests are deduplicated via [pendingRequests].
  Future<Uint8List?> fetchThumbnail({
    required Device device,
    required String fullPath,
    int width = _thumbDim,
    int height = _thumbDim,
  }) async {
    final cacheKey = '${device.fingerprint}:$fullPath:${width}x$height';

    // Cache hit.
    final cached = state.cache.get(cacheKey);
    if (cached != null) {
      return cached;
    }

    // Deduplicate in-flight requests.
    final pending = state.pendingRequests[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _doFetch(
      device: device,
      fullPath: fullPath,
      width: width,
      height: height,
      cacheKey: cacheKey,
    );
    state.pendingRequests[cacheKey] = future;
    try {
      final result = await future;
      return result;
    } finally {
      unawaited(state.pendingRequests.remove(cacheKey));
    }
  }

  Future<Uint8List?> _doFetch({
    required Device device,
    required String fullPath,
    required int width,
    required int height,
    required String cacheKey,
  }) async {
    try {
      final securityContext = ref.read(securityProvider);
      final client = rust_http.createClient(
        privateKey: securityContext.privateKey,
        cert: securityContext.certificate,
        version: rust_http.LsHttpClientVersion.v2,
        expectedFingerprint: device.fingerprint,
        timeoutMs: 10000,
      );

      final ip = device.ip;
      if (ip == null) {
        _logger.warning('fs_thumbnail: device has no IP: ${device.fingerprint}');
        return null;
      }

      final protocol = device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;

      _logger.fine(
        'fs_thumbnail: fetching $fullPath ${width}x$height from $ip:${device.port}',
      );

      final bytes = await client.fsThumbnail(
        protocol: protocol,
        ip: ip,
        port: device.port,
        path: fullPath,
        width: width,
        height: height,
      );

      state.cache.put(cacheKey, bytes);
      _logger.fine(
        'fs_thumbnail: cached ${bytes.length} bytes for $fullPath',
      );
      return bytes;
    } catch (e) {
      _logger.warning('fs_thumbnail: failed for $fullPath: $e');
      return null;
    }
  }

  /// Clears the entire cache (e.g. when switching devices).
  void clearCache() {
    state.cache.clear();
    state.pendingRequests.clear();
  }
}
