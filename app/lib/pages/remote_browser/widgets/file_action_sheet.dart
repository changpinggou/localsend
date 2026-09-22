import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/fs/fs_download_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/save_to_files.dart';
import 'package:localsend_app/util/save_to_gallery.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;

/// T-009: outcome of the file action sheet.
enum FsFileAction {
  saveToGallery,
  saveToFiles,
  preview,
}

/// T-009: bottom sheet shown when the user taps a non-folder entry
/// in the remote file browser.
///
/// The sheet is data-only — it does NOT actually run the download.
/// The page wires each option to the appropriate provider call:
/// `Save to Photos` → `fsDownload.downloadToCache` then `saveCachedToGallery`
/// `Save to Files`  → `fsDownload.downloadToCache` then `saveCachedToFiles`
/// `Preview`       → `fsDownload.downloadToCache` then push ImagePreviewPage
///
/// We split the action sheet from the download logic so the same
/// `downloadToCache` can be reused by long-press context menus (T-016)
/// and the share-extension "save to LocalU fs" path (T-013).
Future<FsFileAction?> showFileActionSheet(
  BuildContext context, {
  required rust.FsEntry entry,
}) {
  final isImage = _looksLikeImage(entry.name);
  return showModalBottomSheet<FsFileAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Wrap(
          children: [
            if (isImage && checkPlatformWithGallery())
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: Text(t.fsDownload.saveToGallery),
                onTap: () => Navigator.of(sheetContext).pop(FsFileAction.saveToGallery),
              ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.fsDownload.saveToFiles),
              onTap: () => Navigator.of(sheetContext).pop(FsFileAction.saveToFiles),
            ),
            if (isImage)
              ListTile(
                leading: const Icon(Icons.preview_outlined),
                title: Text(t.fsDownload.preview),
                onTap: () => Navigator.of(sheetContext).pop(FsFileAction.preview),
              ),
          ],
        ),
      );
    },
  );
}

/// Performs the actual download + post-download action. Lives next
/// to the sheet so the action sheet can stay declarative.
Future<FsFileActionResult> performFileAction({
  required FsDownloadService downloadService,
  required Device device,
  required rust.FsEntry entry,
  required String fullPath,
  required FsFileAction action,
}) async {
  final cachedPath = await downloadService.downloadToCache(
    device: device,
    entry: entry,
    fullPath: fullPath,
  );
  if (cachedPath == null) {
    return FsFileActionResult(action: action, savedPath: null, failed: true);
  }

  switch (action) {
    case FsFileAction.saveToGallery:
      final ok = await saveFileToGallery(cachedPath, isImage: true);
      return FsFileActionResult(action: action, savedPath: cachedPath, failed: !ok);
    case FsFileAction.saveToFiles:
      final dest = await saveFileToDownloads(localPath: cachedPath, filename: entry.name);
      return FsFileActionResult(action: action, savedPath: dest, failed: dest == null);
    case FsFileAction.preview:
      return FsFileActionResult(action: action, savedPath: cachedPath, failed: false);
  }
}

class FsFileActionResult {
  final FsFileAction action;
  final String? savedPath;
  final bool failed;
  const FsFileActionResult({required this.action, required this.savedPath, required this.failed});
}

bool _looksLikeImage(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.heic');
}
