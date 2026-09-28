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
Future<List<String>?> pickMediaForUpload(BuildContext context) async {
  try {
    // Let wechat_assets_picker handle permission internally.
    // It will trigger the native iOS permission dialog on first use.
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
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

    // If permission was denied, show a dialog to guide user to settings
    if (context.mounted && e.toString().contains('permission')) {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('Photo library access is required. Please enable it in Settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
    }

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
