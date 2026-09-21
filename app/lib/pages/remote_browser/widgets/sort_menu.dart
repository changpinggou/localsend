import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';

/// T-008: sort menu (`PopupMenuButton`) shown in the page's AppBar.
/// Selecting an entry dispatches the new sort to the service, which
/// re-fetches the current path with the new sort parameter.
class FsSortMenu extends StatelessWidget {
  final FsSort current;
  final ValueChanged<FsSort> onChanged;

  const FsSortMenu({
    required this.current,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FsSort>(
      tooltip: t.remoteBrowser.sortBy,
      icon: const Icon(Icons.sort),
      onSelected: onChanged,
      itemBuilder: (context) => [
        _item(FsSort.nameAsc, t.remoteBrowser.sortNameAsc),
        _item(FsSort.nameDesc, t.remoteBrowser.sortNameDesc),
        _item(FsSort.sizeAsc, t.remoteBrowser.sortSizeAsc),
        _item(FsSort.sizeDesc, t.remoteBrowser.sortSizeDesc),
        _item(FsSort.mtimeDesc, t.remoteBrowser.sortMtimeDesc),
      ],
    );
  }

  PopupMenuItem<FsSort> _item(FsSort value, String label) {
    return PopupMenuItem<FsSort>(
      value: value,
      child: Row(
        children: [
          if (current == value) const Icon(Icons.check, size: 16) else const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
