// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:consolarr/features/torrents/presentation/remove_dialog.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

/// The full harness matrix: 2 sizes x 2 text scales x 3 locales x 2 themes.
final _variants = harnessMatrix(sizes: const [Size(320, 568), Size(412, 915)]);

String get _magnet => 'magnet:?xt=urn:btih:${'b' * 40}&dn=Example+Linux+ISO';

/// Mounts a button that opens the sheet or dialog for real, taps it, and runs
/// the overflow and accessibility checks with the overlay showing.
Future<void> _matrix(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) show, {
  FakeTorrentClient? client,
  Future<void> Function()? arrange,
}) async {
  final c = client ?? FakeTorrentClient();
  var checked = 0;
  await pumpMatrix(
    tester,
    (v) => sheetApp(
      v,
      Center(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => show(context),
            child: const Text('open'),
          ),
        ),
      ),
      client: c,
    ),
    variants: _variants,
    verify: (v) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await arrange?.call();
      expectNoFrameworkExceptions(tester, context: v.label);
      await expectAccessible(tester);
      checked++;
    },
  );
  expect(checked, _variants.length);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pumpAndSettle();
}

void main() {
  group('add sheet', () {
    testWidgets('empty form', (tester) async {
      await _matrix(tester, showAddTorrentSheet);
    });

    testWidgets('filled form with a parsed link', (tester) async {
      await _matrix(
        tester,
        showAddTorrentSheet,
        arrange: () => _type(tester, _magnet),
      );
    });

    testWidgets('validation error', (tester) async {
      await _matrix(
        tester,
        showAddTorrentSheet,
        arrange: () => _type(tester, 'ftp://files.example/a'),
      );
    });
  });

  group('detail sheet', () {
    Future<void> detail(WidgetTester tester, TorrentState state) => _matrix(
      tester,
      (c) => showTorrentDetailSheet(c, 'hash1'),
      client: FakeTorrentClient()
        ..detail = TorrentDetail(
          torrent: sampleTorrent(1, state: state),
          savePath: '/downloads/example',
          seeds: 3,
          seedsTotal: 10,
          peers: 2,
          peersTotal: 7,
          availability: 1.5,
          downloaded: 1024 * 1024 * 300,
          uploaded: 1024 * 1024 * 50,
        ),
    );

    testWidgets('running torrent', (tester) async {
      await detail(tester, TorrentState.downloading);
    });

    testWidgets('paused torrent', (tester) async {
      await detail(tester, TorrentState.paused);
    });
  });

  group('speed limits sheet', () {
    testWidgets('loaded', (tester) async {
      await _matrix(
        tester,
        showSpeedLimitsSheet,
        client: FakeTorrentClient()
          ..limits = const SpeedLimitsState(
            download: 2 * 1024 * 1024,
            upload: 512 * 1024,
            alternativeActive: false,
          ),
      );
    });

    testWidgets('failed load', (tester) async {
      await _matrix(
        tester,
        showSpeedLimitsSheet,
        client: FakeTorrentClient()
          ..limitsError = const AppError(ErrorCategory.serverError),
      );
    });
  });

  group('remove confirmation', () {
    final name = 'Example Torrent ${'x' * 60}';

    testWidgets('keep the files', (tester) async {
      await _matrix(tester, (c) => showRemoveDialog(c, name));
    });

    testWidgets('also delete the files', (tester) async {
      await _matrix(
        tester,
        (c) => showRemoveDialog(c, name),
        arrange: () async {
          // The long pseudo-locale label makes the tile taller than the
          // dialog's scroll area: bring the box itself into view.
          await tester.ensureVisible(find.byType(Checkbox));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue,
          );
        },
      );
    });
  });
}
