import 'dart:io' show Platform;
import 'package:gal/gal.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

final _logger = Logger('SaveToGallery');

/// T-009: save an image or video already on disk into the platform
/// photo gallery.
///
/// Returns `true` on success, `false` otherwise. Failure modes:
///   * the platform has no gallery (desktop / web) → `false`;
///   * the user denied permission → `false`;
///   * the file is missing or unreadable → `false` (with a logged
///     reason — see [Gal.putImage] / [Gal.putVideo]).
///
/// On iOS / Android, the file is added to the user's camera roll
/// via the platform-native API. We don't surface a SwiftUI / Activity
/// picker — `gal` is the only file-format-handling dependency the
/// project already declared, and adding a custom intent would re-
/// duplicate that work.
Future<bool> saveFileToGallery(String localPath, {required bool isImage}) async {
  _logger.info('saveFileToGallery called: path=$localPath, isImage=$isImage');

  if (!checkPlatformWithGallery()) {
    _logger.info('Platform does not support gallery');
    return false;
  }

  try {
    // On iOS, use gal's built-in permission request
    if (Platform.isIOS || Platform.isMacOS) {
      _logger.info('iOS/macOS: using Gal.hasAccess to check permission');
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      _logger.info('Gal.hasAccess result: $hasAccess');

      if (!hasAccess) {
        _logger.info('Requesting access via Gal.requestAccess');
        final granted = await Gal.requestAccess(toAlbum: false);
        _logger.info('Gal.requestAccess result: $granted');
        if (!granted) {
          _logger.warning('User denied photo access');
          return false;
        }
      }
    } else {
      // On Android, use permission_handler
      final status = await Permission.photos.status;
      _logger.info('Android: Current photo permission status: $status');

      if (status.isPermanentlyDenied) {
        _logger.warning('Photo permission permanently denied, opening app settings');
        await openAppSettings();
        final newStatus = await Permission.photos.status;
        _logger.info('Permission status after settings: $newStatus');
        if (!newStatus.isGranted) {
          _logger.warning('User still denied permission after visiting settings');
          return false;
        }
      } else if (!status.isGranted) {
        _logger.info('Requesting photo access via Gal.requestAccess');
        final granted = await Gal.requestAccess(toAlbum: false);
        _logger.info('Gal.requestAccess result: $granted');
        if (!granted) {
          _logger.warning('User denied photo access via Gal.requestAccess');
          return false;
        }
      } else {
        _logger.info('Photo permission already granted');
      }
    }

    _logger.info('Saving ${isImage ? "image" : "video"} to gallery: $localPath');
    if (isImage) {
      await Gal.putImage(localPath);
    } else {
      await Gal.putVideo(localPath);
    }
    _logger.info('File saved to gallery successfully');
    return true;
  } catch (e, st) {
    _logger.warning('Failed to save file to gallery: $e', null, st);
    return false;
  }
}
