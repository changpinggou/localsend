import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';

/// T-008: list-vs-grid toggle shown in the AppBar. Persisted in
/// [FsListState.viewMode] so the user's preference survives page
/// rebuilds within the same session (it is not persisted across app
/// restarts in P1 — that's a P5 polish).
class FsViewModeToggle extends StatelessWidget {
  final FsViewMode current;
  final ValueChanged<FsViewMode> onChanged;

  const FsViewModeToggle({
    required this.current,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isList = current == FsViewMode.list;
    return Tooltip(
      message: isList ? t.remoteBrowser.viewGrid : t.remoteBrowser.viewList,
      child: IconButton(
        icon: Icon(isList ? Icons.grid_view : Icons.view_list),
        onPressed: () => onChanged(isList ? FsViewMode.grid : FsViewMode.list),
      ),
    );
  }
}
