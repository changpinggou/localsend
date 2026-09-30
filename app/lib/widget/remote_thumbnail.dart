import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:localsend_app/provider/network/fs/fs_thumbnail_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Renders a thumbnail for a remote file by fetching
/// `GET /api/localsend/v2/fs/thumbnail` through the FRB client.
///
/// Lifecycle:
///   1. `initState` → triggers fetch via [FsThumbnailService.fetchThumbnail]
///   2. Loading    → shows [placeholder] (the fallback icon)
///   3. Success    → `Image.memory(pngBytes, fit: BoxFit.cover)`
///   4. Error      → keeps [placeholder] (no error UI; thumbnails are
///                     decorative, not critical)
///
/// The provider's internal cache deduplicates repeat requests, so the
/// same `(device, path, size)` triple never fetches twice.
class RemoteThumbnail extends StatefulWidget {
  /// The remote device whose filesystem we're browsing.
  final Device device;

  /// Remote path relative to the mount-point root (e.g. `photos/IMG_001.jpg`).
  final String fullPath;

  /// Thumbnail width in logical pixels.
  final double width;

  /// Thumbnail height in logical pixels.
  final double height;

  /// Widget shown while loading or on error. Typically an `Icon` matching
  /// the file type.
  final Widget placeholder;

  const RemoteThumbnail({
    required this.device,
    required this.fullPath,
    required this.width,
    required this.height,
    required this.placeholder,
    super.key,
  });

  @override
  State<RemoteThumbnail> createState() => _RemoteThumbnailState();
}

class _RemoteThumbnailState extends State<RemoteThumbnail> with Refena {
  Uint8List? _bytes;
  bool _loading = false;
  bool _fetchStarted = false;

  /// `ref` (from the Refena mixin) depends on an InheritedWidget, which is
  /// not available during [initState]. We kick the first fetch here instead.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_fetchStarted) {
      _fetchStarted = true;
      _fetch();
    }
  }

  @override
  void didUpdateWidget(covariant RemoteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullPath != widget.fullPath ||
        oldWidget.device.fingerprint != widget.device.fingerprint) {
      _bytes = null;
      _loading = false;
      _fetchStarted = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() => _loading = true);

    final bytes = await ref.notifier(fsThumbnailProvider).fetchThumbnail(
      device: widget.device,
      fullPath: widget.fullPath,
      width: widget.width.round(),
      height: widget.height.round(),
    );

    if (mounted && bytes != null) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _bytes!,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => widget.placeholder,
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: widget.placeholder,
    );
  }
}
