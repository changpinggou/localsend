// T-008: widget tests for the read-only remote file browser page widgets.
//
// We test the leaf widgets directly rather than [RemoteBrowserPage] because
// the page wires up refena + the isolate layer, which is heavy to stand up
// in `flutter_test`. The full e2e path is covered by integration tests
// in `test/integration/fs_browse_test.dart` (added in T-008 follow-up).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/remote_browser/widgets/breadcrumb.dart';
import 'package:localsend_app/pages/remote_browser/widgets/empty_state.dart';
import 'package:localsend_app/pages/remote_browser/widgets/sort_menu.dart';
import 'package:localsend_app/pages/remote_browser/widgets/view_mode_toggle.dart';
import 'package:localsend_app/provider/network/fs/fs_list_provider.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocaleSync();

  group('FsBreadcrumb', () {
    testWidgets('renders only the root chip when path is empty', (tester) async {
      await tester.pumpWidget(_wrap(FsBreadcrumb(path: '', onNavigate: (_) {})));
      expect(find.text(t.remoteBrowser.breadcrumbRoot), findsOneWidget);
    });

    testWidgets('renders segments joined by /, in order', (tester) async {
      await tester.pumpWidget(
        _wrap(FsBreadcrumb(path: 'Photos/2026/IMG', onNavigate: (_) {})),
      );
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('IMG'), findsOneWidget);
      expect(find.text(t.remoteBrowser.breadcrumbRoot), findsOneWidget);
    });

    testWidgets('tapping a non-last segment invokes onNavigate with its cumulative path', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        _wrap(FsBreadcrumb(path: 'Photos/2026/IMG', onNavigate: (p) => tapped = p)),
      );
      await tester.tap(find.text('2026'));
      await tester.pump();
      expect(tapped, 'Photos/2026');
    });

    testWidgets('tapping the root segment invokes onNavigate with ""', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        _wrap(FsBreadcrumb(path: 'Photos', onNavigate: (p) => tapped = p)),
      );
      await tester.tap(find.text(t.remoteBrowser.breadcrumbRoot));
      await tester.pump();
      expect(tapped, '');
    });
  });

  group('FsEmptyState', () {
    testWidgets('renders the roots message when isRoots is true', (tester) async {
      await tester.pumpWidget(_wrap(const FsEmptyState(isRoots: true)));
      expect(find.text(t.remoteBrowser.roots), findsOneWidget);
    });

    testWidgets('renders the empty folder message when isRoots is false', (tester) async {
      await tester.pumpWidget(_wrap(const FsEmptyState(isRoots: false)));
      expect(find.text(t.remoteBrowser.emptyFolder), findsOneWidget);
    });

    testWidgets('does NOT render a retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(_wrap(const FsEmptyState(isRoots: true)));
      expect(find.text(t.remoteBrowser.retry), findsNothing);
    });

    testWidgets('renders a retry button when onRetry is provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(FsEmptyState(isRoots: true, onRetry: () => tapped = true)),
      );
      await tester.tap(find.text(t.remoteBrowser.retry));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('FsErrorState', () {
    testWidgets('renders the generic message when none provided', (tester) async {
      await tester.pumpWidget(_wrap(FsErrorState(onRetry: () {}, message: null)));
      expect(find.text(t.remoteBrowser.errorTitle), findsOneWidget);
      expect(find.text(t.remoteBrowser.errorGeneric), findsOneWidget);
    });

    testWidgets('renders the provided message verbatim', (tester) async {
      await tester.pumpWidget(_wrap(FsErrorState(onRetry: () {}, message: 'boom')));
      expect(find.text('boom'), findsOneWidget);
    });
  });

  group('FsLoadingSkeleton', () {
    testWidgets('renders the requested number of rows', (tester) async {
      await tester.pumpWidget(_wrap(const FsLoadingSkeleton(rows: 5)));
      // Each row renders two Containers (icon + bar). Pump once and check
      // they all exist by counting the bar Containers.
      expect(find.byType(Container), findsNWidgets(5 * 2));
    });
  });

  group('FsSortMenu', () {
    testWidgets('renders the sort icon', (tester) async {
      await tester.pumpWidget(
        _wrap(FsSortMenu(current: FsSort.nameAsc, onChanged: (_) {})),
      );
      expect(find.byType(PopupMenuButton<FsSort>), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsOneWidget);
    });
  });

  group('FsViewModeToggle', () {
    testWidgets('toggling from list to grid fires the change with grid', (tester) async {
      FsViewMode? picked;
      await tester.pumpWidget(
        _wrap(FsViewModeToggle(current: FsViewMode.list, onChanged: (m) => picked = m)),
      );
      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pump();
      expect(picked, FsViewMode.grid);
    });

    testWidgets('toggling from grid to list fires the change with list', (tester) async {
      FsViewMode? picked;
      await tester.pumpWidget(
        _wrap(FsViewModeToggle(current: FsViewMode.grid, onChanged: (m) => picked = m)),
      );
      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pump();
      expect(picked, FsViewMode.list);
    });
  });
}
