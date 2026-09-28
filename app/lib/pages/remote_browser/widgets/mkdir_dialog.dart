import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// T-012: shows a dialog to create a new folder.
///
/// Returns the folder name or null if cancelled.
Future<String?> showMkdirDialog(BuildContext context) {
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(t.fsUpload.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t.fsUpload.newFolderHint,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(t.general.confirm),
          ),
        ],
      );
    },
  );
}
