import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:localsend_app/provider/network/fs/fs_thumbnail_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('RemoteThumbnail');

/// Renders a thumbnail for a remote file by fetching
/// `GET /api/localsend/v2/fs/thumbnail` through the FRB client.
///
/// The fetch starts as soon as the widget mounts. Laziness comes from the
/// list / grid bodies, which use `ListView.builder` / `GridView.builder`
/// and therefore only build entries near the viewport. (An earlier
/// revision triggered the fetch from a `VisibilityDetector` callback
/// instead — that detector keeps its last visibility per key in static
/// state which survives unmounts, so after an in-place refresh, e.g.
/// deleting an entry, the remounted rows with identical geometry
/// suppressed the initial "visible" callback and no thumbnail ever
/// loaded until the page was left and re-entered.)
///
/// Lifecycle:
///   1. `didChangeDependencies` → triggers fetch via [FsThumbnailService.fetchThumbnail]
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
    _maybeFetch();
  }

  @override
  void didUpdateWidget(covariant RemoteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullPath != widget.fullPath || oldWidget.device.fingerprint != widget.device.fingerprint) {
      _bytes = null;
      _loading = false;
      _fetchStarted = false;
      _maybeFetch();
    }
  }

  void _maybeFetch() {
    if (_fetchStarted) return;
    _fetchStarted = true;
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    if (_loading) return;
    // Not part of the rendered output, so no setState needed to flip it.
    _loading = true;
    final fullPath = widget.fullPath;

    final bytes = await ref
        .notifier(fsThumbnailProvider)
        .fetchThumbnail(
          device: widget.device,
          fullPath: fullPath,
          width: widget.width.round(),
          height: widget.height.round(),
        );

    // Never apply the bytes of a path the widget has moved away from
    // while the request was in flight. Also reset [_loading] on failure
    // so a later trigger (e.g. the row being rebuilt for another entry)
    // can retry.
    if (!mounted || widget.fullPath != fullPath) return;
    setState(() {
      if (bytes != null) {
        _bytes = bytes;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _bytes!,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // A 200 with undecodable bytes used to degrade to the
            // placeholder in silence — log it so decode-garbage cases
            // are distinguishable from a failed request.
            _logger.warning('Image.memory failed for ${widget.fullPath}', error);
            return widget.placeholder;
          },
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
