import 'package:flutter/services.dart';

/// Platform channel for managing macOS security-scoped bookmarks.
///
/// Security-scoped bookmarks allow sandboxed apps to access files/directories
/// outside the sandbox with user permission. This is the official Apple
/// recommended approach for sandboxed apps that need persistent access to
/// user-selected resources.
class FsBookmarkChannel {
  static const MethodChannel _channel = MethodChannel('localsend/fs_bookmark');

  /// Opens a folder picker dialog and returns the bookmark data for the
  /// selected folder. Returns null if the user cancelled.
  ///
  /// The bookmark data can be persisted and used to regain access to the
  /// folder across app launches.
  static Future<Uint8List?> pickFolder() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('pickFolder');
      return result;
    } on PlatformException catch (e) {
      return null;
    }
  }

  /// Resolves a bookmark data to a path. Returns null if the bookmark is
  /// invalid or access is denied.
  ///
  /// This will automatically start and stop security-scoped access.
  static Future<String?> resolveBookmark(Uint8List bookmarkData) async {
    try {
      final result = await _channel.invokeMethod<String>('resolveBookmark', {
        'bookmark': bookmarkData,
      });
      return result;
    } on PlatformException catch (e) {
      return null;
    }
  }

  /// Checks if bookmark data is still valid (the resource still exists and
  /// we still have access).
  static Future<bool> isBookmarkValid(Uint8List bookmarkData) async {
    try {
      final result = await _channel.invokeMethod<bool>('isBookmarkValid', {
        'bookmark': bookmarkData,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      return false;
    }
  }

  /// Stops security-scoped access for a bookmark. Should be called when
  /// done using the resolved path.
  static Future<void> stopAccessing(Uint8List bookmarkData) async {
    try {
      await _channel.invokeMethod('stopAccessing', {
        'bookmark': bookmarkData,
      });
    } on PlatformException catch (e) {
      // Ignore
    }
  }
}
