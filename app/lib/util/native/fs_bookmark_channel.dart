import 'dart:convert' show base64Decode;
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _logger = Logger('FsBookmarkChannel');

/// A folder picked on macOS together with its security-scoped bookmark.
class FsFolderPick {
  final String path;

  /// Base64-encoded security-scoped bookmark data.
  ///
  /// Persisting this and restoring it via [FsBookmarkChannel.startAccess] is
  /// what keeps the folder readable after an app restart while the App
  /// Sandbox is enabled (the raw NSOpenPanel grant is session-only).
  final String? bookmark;

  const FsFolderPick({required this.path, this.bookmark});
}

/// Platform channel for macOS-specific filesystem operations.
class FsBookmarkChannel {
  static const MethodChannel _channel = MethodChannel('localsend/fs_bookmark');

  /// Opens a folder picker dialog on macOS.
  ///
  /// Returns the selected folder path with its security-scoped bookmark, or
  /// null if the user cancelled.
  /// On non-macOS platforms, returns null immediately.
  static Future<FsFolderPick?> pickFolder() async {
    if (!Platform.isMacOS) {
      _logger.warning('Folder picker is only supported on macOS');
      return null;
    }

    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('pickFolder');
      final path = result?['path'] as String?;
      if (path == null) {
        return null;
      }
      final pick = FsFolderPick(path: path, bookmark: result?['bookmark'] as String?);
      _logger.info('Folder picker result: ${pick.path}');
      return pick;
    } on PlatformException catch (e, st) {
      _logger.warning('Failed to pick folder', e, st);
      return null;
    }
  }

  /// Restores security-scoped access from a persisted bookmark (base64).
  ///
  /// Resolves the bookmark and calls startAccessingSecurityScopedResource,
  /// which keeps the folder readable for the rest of the app lifetime.
  /// Returns the resolved path, or null if the bookmark is invalid
  /// (e.g. the folder was moved or deleted).
  static Future<String?> startAccess(String bookmarkBase64) async {
    if (!Platform.isMacOS) {
      return null;
    }

    final List<int> bookmarkData;
    try {
      bookmarkData = base64Decode(bookmarkBase64);
    } on FormatException catch (e) {
      _logger.warning('Invalid bookmark data: $e');
      return null;
    }

    return resolveBookmark(bookmarkData);
  }

  /// Resolves a security-scoped bookmark to a path.
  ///
  /// Returns the resolved path, or null if the bookmark is invalid or
  /// access is denied.
  static Future<String?> resolveBookmark(List<int> bookmarkData) async {
    if (!Platform.isMacOS) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<String>('resolveBookmark', {
        'bookmark': bookmarkData,
      });
      return result;
    } on PlatformException catch (e, st) {
      _logger.warning('Failed to resolve bookmark', e, st);
      return null;
    }
  }
}
