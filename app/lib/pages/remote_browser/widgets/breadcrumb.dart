import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// T-008: breadcrumb path navigation for the remote filesystem browser.
///
/// Renders the current [path] as a clickable chain of segments separated by
/// `/`. The first segment is always the roots entry (drives). Tapping any
/// segment calls [onNavigate] with the cumulative path up to that segment,
/// so the parent can issue a fresh `enterPath(...)` against the isolate.
///
/// Long paths are not truncated at the widget level — instead the segments
/// are wrapped in a horizontally scrollable [SingleChildScrollView] so the
/// user can scrub to the leftmost / rightmost segment.
class FsBreadcrumb extends StatelessWidget {
  /// Path relative to the device root, slash-separated. `""` means the
  /// roots level.
  final String path;

  /// Called with the path of the segment the user tapped. `""` means the
  /// user tapped the root segment (back to drives).
  final ValueChanged<String> onNavigate;

  const FsBreadcrumb({
    required this.path,
    required this.onNavigate,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The root segment is always shown, then one per non-empty segment.
    final trailing = <_Segment>[];
    if (path.isNotEmpty) {
      final parts = path.split('/').where((p) => p.isNotEmpty).toList();
      var cumulative = '';
      for (final part in parts) {
        cumulative = cumulative.isEmpty ? part : '$cumulative/$part';
        trailing.add(_Segment(label: part, path: cumulative));
      }
    }
    final segments = <_Segment>[
      _Segment(label: t.remoteBrowser.breadcrumbRoot, path: ''),
      ...trailing,
    ];

    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              _Crumb(
                label: segments[i].label,
                isLast: i == segments.length - 1,
                onTap: () => onNavigate(segments[i].path),
              ),
              if (i < segments.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment {
  final String label;
  final String path;
  const _Segment({required this.label, required this.path});
}

class _Crumb extends StatelessWidget {
  final String label;
  final bool isLast;
  final VoidCallback onTap;

  const _Crumb({
    required this.label,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: isLast ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isLast ? theme.colorScheme.onSurface : theme.colorScheme.primary,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
