import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// T-009: minimal full-screen image preview. Used for the "Preview"
/// action in the remote file browser. Loads a single image from
/// disk, scales it with [InteractiveViewer] for pinch-zoom / pan.
///
/// P5 (`T-023`) replaces this with a gallery-style horizontal pager
/// + shared-element transitions; the surface here is intentionally
/// minimal so P1 can ship the read+save path.
class ImagePreviewPage extends StatelessWidget {
  final String localPath;
  final String? title;

  const ImagePreviewPage({
    required this.localPath,
    this.title,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? t.fsDownload.preview),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4.0,
          child: Image.file(
            File(localPath),
            errorBuilder: (context, error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.fsDownload.previewLoading,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
