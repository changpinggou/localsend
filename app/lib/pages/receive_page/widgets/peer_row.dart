import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_isolates/model/capability.dart';
import 'package:localsend_isolates/model/device.dart';

/// A device row in the "nearby devices" list.
///
/// On top of [DeviceListTile] (device icon, name, badges, info button), it adds
/// a "browse drive" button that is only shown when the device's capabilities
/// include [Capability.fs]. Tapping the row still triggers the default
/// [onTap] (send to that device).
class PeerRow extends StatelessWidget {
  final Device device;
  final bool isFavorite;
  final String? nameOverride;
  final String? info;
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onDetailsTap;

  /// Called when the user taps the "browse drive" icon. Only invoked when the
  /// device advertises [Capability.fs]; the button is hidden otherwise.
  final VoidCallback? onBrowseDriveTap;

  const PeerRow({
    required this.device,
    this.isFavorite = false,
    this.nameOverride,
    this.info,
    this.progress,
    this.onTap,
    this.onDetailsTap,
    this.onBrowseDriveTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final showBrowseDrive = device.capabilities.contains(Capability.fs);

    return DeviceListTile(
      device: device,
      isFavorite: isFavorite,
      nameOverride: nameOverride,
      info: info,
      progress: progress,
      onTap: onTap,
      onDetailsTap: onDetailsTap,
      // Show the browse-drive icon to the left of the existing info icon.
      // When [DeviceListTile.onDetailsTap] is null its trailing is null, so we
      // provide our own Row of trailing buttons here.
      trailingOverride: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBrowseDrive)
            Tooltip(
              message: t.sendTab.browseDriveTooltip,
              child: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: onBrowseDriveTap,
              ),
            ),
          if (onDetailsTap != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: onDetailsTap,
            ),
        ],
      ),
    );
  }
}
