import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/util/ui/asset_picker_translated_text_delegate.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

final _logger = Logger('PickForUpload');

/// T-012: picks media files (photos/videos) from gallery.
///
/// Returns a list of file paths or null if cancelled.
/// On iOS, requests photo library permission first.
/// On Android, requests storage permission first.
Future<List<String>?> pickMediaForUpload(BuildContext context) async {
  try {
    // Request permission
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        _logger.warning('Photo library permission denied');
        return null;
      }
    } else if (Platform.isAndroid) {
      final status = await Permission.photos.request();
      if (!status.isGranted && !status.isLimited) {
        _logger.warning('Storage permission denied');
        return null;
      }
    }

    // Pick assets
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: 100,
        requestType: RequestType.common,
        textDelegate: TranslatedAssetPickerTextDelegate(),
      ),
    );

    if (assets == null || assets.isEmpty) {
      return null;
    }

    // Convert assets to file paths
    final paths = <String>[];
    for (final asset in assets) {
      try {
        final file = await asset.file;
        if (file != null && await file.exists()) {
          paths.add(file.path);
        }
      } catch (e) {
        _logger.warning('Failed to get file for asset: $e');
      }
    }

    return paths.isEmpty ? null : paths;
  } catch (e) {
    _logger.severe('Failed to pick media: $e');
    return null;
  }
}

/// T-012: picks files from file system.
///
/// Returns a list of file paths or null if cancelled.
Future<List<String>?> pickFilesForUpload() async {
  try {
    final result = await openFiles();

    if (result.isEmpty) {
      return null;
    }

    // Convert XFile to paths
    final paths = result.map((f) => f.path).toList();

    return paths.isEmpty ? null : paths;
  } catch (e) {
    _logger.severe('Failed to pick files: $e');
    return null;
  }
}
