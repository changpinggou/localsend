import 'dart:io' show File, Platform;

import 'package:gal/gal.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

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
///
/// [filename] is the title the asset gets in the gallery. Without it,
/// `gal` keeps the file's basename — for downloaded files that is a
/// cache name like `fs-<session>-IMG_0001.JPG`, which would litter the
/// library with mangled titles (same class of bug as T-027 §10.2, one
/// level up). Only images honour it (`gal` has no name parameter for
/// videos).
Future<bool> saveFileToGallery(String localPath, {required bool isImage, String? filename}) async {
  _logger.info('saveFileToGallery called: path=$localPath, isImage=$isImage, filename=$filename');

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
      if (filename != null) {
        // Save the bytes under the real title — `putImage(path)` would
        // inherit the cache basename as the asset's originalFilename.
        final bytes = await File(localPath).readAsBytes();
        await Gal.putImageBytes(bytes, name: filename);
      } else {
        await Gal.putImage(localPath);
      }
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

/// Returns `true` when the photo library already contains an asset with
/// [filename] as its title and a file size of exactly [sizeBytes] bytes.
///
/// Same matching rule as the photo-sync diff (T-027 §10.1: same name +
/// same size → duplicate). Best effort: returns `false` when the
/// platform has no gallery or photo access is denied, so callers fall
/// back to the plain save flow.
///
/// The scan mirrors [PhotoSyncService]'s local scan: albums overlap on
/// iOS ("Recents" contains everything), so assets are deduped by id.
/// Titles are cheap metadata; the file is only opened for title matches
/// (an `originFile` can trigger an iCloud download otherwise).
Future<bool> isFileInGallery({required String filename, required int sizeBytes}) async {
  if (!checkPlatformWithGallery()) {
    return false;
  }

  try {
    final granted = await PhotoManager.requestPermissionExtend();
    if (!granted.isAuth) {
      _logger.info('isFileInGallery: photo permission not granted, skipping dedupe check');
      return false;
    }

    final seenAssetIds = <String>{};
    const pageSize = 300;

    final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
    for (final path in paths) {
      int page = 0;
      while (true) {
        final List<AssetEntity> assets;
        try {
          assets = await path.getAssetListPaged(page: page, size: pageSize);
        } catch (e) {
          _logger.warning('isFileInGallery: failed to page album "${path.name}": $e');
          break;
        }
        if (assets.isEmpty) break;

        for (final asset in assets) {
          if (!seenAssetIds.add(asset.id)) continue;
          // Cheap check first: only touch the file (potentially an iCloud
          // download) when the title already matches.
          if (await asset.titleAsync != filename) continue;
          try {
            final file = await asset.originFile;
            if (file != null && await file.length() == sizeBytes) {
              _logger.info('isFileInGallery: found duplicate "$filename" ($sizeBytes B) as asset ${asset.id}');
              return true;
            }
          } catch (e) {
            _logger.warning('isFileInGallery: failed to read asset ${asset.id}: $e');
          }
        }
        page++;
      }
    }

    _logger.info('isFileInGallery: no duplicate "$filename" ($sizeBytes B) in ${paths.length} album(s)');
    return false;
  } catch (e, st) {
    // Best effort — the save flow must not break because the dedupe
    // check failed (e.g. plugin channel error).
    _logger.warning('isFileInGallery: check failed: $e', null, st);
    return false;
  }
}
