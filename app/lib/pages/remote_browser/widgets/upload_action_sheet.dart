import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// T-012: shows a bottom sheet with upload options:
/// - From Photos (gallery picker)
/// - From Files (file picker)
/// - New Folder (mkdir dialog)
///
/// Returns the selected action or null if cancelled.
Future<FsUploadAction?> showUploadActionSheet(BuildContext context) {
  return showModalBottomSheet<FsUploadAction>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(t.fsUpload.fromPhotos),
              onTap: () => Navigator.pop(context, FsUploadAction.fromPhotos),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(t.fsUpload.fromFiles),
              onTap: () => Navigator.pop(context, FsUploadAction.fromFiles),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: Text(t.fsUpload.newFolder),
              onTap: () => Navigator.pop(context, FsUploadAction.newFolder),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// T-012: upload action types.
enum FsUploadAction {
  fromPhotos,
  fromFiles,
  newFolder,
}
