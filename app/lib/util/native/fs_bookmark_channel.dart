import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _logger = Logger('FsBookmarkChannel');

/// Platform channel for macOS-specific filesystem operations.
class FsBookmarkChannel {
  static const MethodChannel _channel = MethodChannel('localsend/fs_bookmark');

  /// Opens a folder picker dialog on macOS.
  ///
  /// Returns the selected folder path, or null if the user cancelled.
  /// On non-macOS platforms, returns null immediately.
  static Future<String?> pickFolder() async {
    if (!Platform.isMacOS) {
      _logger.warning('Folder picker is only supported on macOS');
      return null;
    }

    try {
      final result = await _channel.invokeMethod<String>('pickFolder');
      _logger.info('Folder picker result: $result');
      return result;
    } on PlatformException catch (e, st) {
      _logger.warning('Failed to pick folder', e, st);
      return null;
    }
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
