import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_page/widgets/peer_row.dart';
import 'package:localsend_isolates/model/capability.dart';
import 'package:localsend_isolates/model/device.dart';

/// Wraps the [PeerRow] in a minimal [MaterialApp] so its [Tooltip] and
/// [IconButton] widgets have a directionality + media query.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

Device _device({Set<Capability> capabilities = Capability.defaultSet}) {
  return Device(
    signalingId: null,
    ip: '192.168.1.42',
    version: '2.3',
    port: 53317,
    https: true,
    fingerprint: 'fp-1',
    alias: 'Test Peer',
    deviceModel: 'Pixel 7',
    deviceType: DeviceType.mobile,
    download: false,
    capabilities: capabilities,
    channels: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Slang needs a locale to be picked; en is the default in tests.
  LocaleSettings.useDeviceLocaleSync();

  group('PeerRow capability gating', () {
    testWidgets('peer_row_shows_browse_when_fs', (tester) async {
      final device = _device(capabilities: {Capability.send, Capability.receive, Capability.fs});

      await tester.pumpWidget(
        _wrap(
          PeerRow(
            device: device,
            onBrowseDriveTap: () {},
          ),
        ),
      );

      // The folder_open icon marks the browse-drive button.
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('peer_row_hides_browse_when_no_fs', (tester) async {
      // defaultSet is {send, receive} - no fs.
      final device = _device();

      await tester.pumpWidget(
        _wrap(
          PeerRow(
            device: device,
            onBrowseDriveTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.folder_open), findsNothing);
    });

    testWidgets('peer_row_hides_browse_when_capabilities_empty', (tester) async {
      // v2.2 peers: capabilities field is missing/empty.
      final device = _device(capabilities: const {});

      await tester.pumpWidget(
        _wrap(
          PeerRow(
            device: device,
            onBrowseDriveTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.folder_open), findsNothing);
    });

    testWidgets('peer_row_tap_browse_invokes_callback', (tester) async {
      final device = _device(capabilities: {Capability.send, Capability.receive, Capability.fs});
      var taps = 0;

      await tester.pumpWidget(
        _wrap(
          PeerRow(
            device: device,
            onBrowseDriveTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('peer_row_includes_tooltip_with_i18n', (tester) async {
      final device = _device(capabilities: {Capability.send, Capability.receive, Capability.fs});

      await tester.pumpWidget(
        _wrap(
          PeerRow(
            device: device,
            onBrowseDriveTap: () {},
          ),
        ),
      );

      // Tooltip is rendered as a child of the IconButton. Verifying the
      // localized string is present keeps the i18n wiring honest.
      expect(find.byTooltip(t.sendTab.browseDriveTooltip), findsOneWidget);
    });

    testWidgets('peer_row_passes_onTap_through_to_device_list_tile', (tester) async {
      final device = _device();
      var taps = 0;

      await tester.pumpWidget(
        _wrap(
          PeerRow(
            device: device,
            onTap: () => taps++,
          ),
        ),
      );

      // Tapping the title triggers onTap.
      await tester.tap(find.text('Test Peer'));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
