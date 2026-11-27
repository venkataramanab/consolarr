// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/presentation/remove_dialog.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_row.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

/// The stress variants (smallest phone, scale 2.0, ar and en_XA) plus the
/// common phone at scale 1.0 in en, light theme.
final _coverage = [
  ...stressVariants,
  const HarnessVariant(
    size: Size(412, 915),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.light,
  ),
];

/// The accessibility guidelines for a full-screen state: tap targets, labels
/// and text contrast. On the 320x568 stress variants at scale 2.0 the content
/// scrolls and the contrast guideline samples pixels of clipped-away content
/// (false failures), so contrast runs at 412x915 only.
Future<void> _a11y(WidgetTester tester, HarnessVariant v) async {
  if (v.size.width >= 400) {
    await expectAccessible(tester);
  } else {
    await expectTapTargets(tester);
    await expectLabeledTapTargets(tester);
  }
}

/// For dialogs and glass sheets: tap targets and labels. Flutter's contrast
/// guideline reads pixels behind a blurred translucent sheet or inside a
/// scrolled dialog and fails text that is plainly readable (checked on the
/// rendered images); the design system tests the sheet contents' contrast on
/// their own (`new_components_matrix_test.dart`).
Future<void> _overlayA11y(WidgetTester tester) async {
  await expectTapTargets(tester);
  await expectLabeledTapTargets(tester);
}

/// Pumps [screen], runs [open], and checks overflow plus the accessibility
/// guidelines (tap targets, labels, contrast) on every [_coverage] variant.
Future<void> _matrix(
  WidgetTester tester,
  FakeTorrentClient client,
  Widget Function(BuildContext) screen, {
  required Future<void> Function() open,
}) async {
  await pumpMatrix(
    tester,
    (v) => sheetApp(v, Builder(builder: screen), client: client),
    variants: _coverage,
    verify: (v) async {
      await open();
      await tester.pumpAndSettle();
      expectNoFrameworkExceptions(tester, context: v.label);
      await _overlayA11y(tester);
    },
  );
}

Widget _opener(Future<Object?> Function(BuildContext) show) => Center(
  child: Builder(
    builder: (context) =>
        FilledButton(onPressed: () => show(context), child: const Text('open')),
  ),
);

void main() {
  testWidgets('remove dialog', (tester) async {
    await _matrix(
      tester,
      FakeTorrentClient(),
      (_) => _opener((c) => showRemoveDialog(c, 'Example Torrent ${'x' * 60}')),
      open: () => tester.tap(find.text('open')),
    );
  });

  testWidgets('pause-all and resume-all confirms', (tester) async {
    for (final pause in [true, false]) {
      await _matrix(
        tester,
        FakeTorrentClient(),
        (_) => _opener((c) {
          final l10n = c.l10n;
          return confirmDialog(
            c,
            title: pause ? l10n.torPauseAllTitle : l10n.torResumeAllTitle,
            body: pause ? l10n.torPauseAllBody(12) : l10n.torResumeAllBody(12),
            confirmLabel: pause
                ? l10n.torPauseAllConfirm
                : l10n.torResumeAllConfirm,
          );
        }),
        open: () => tester.tap(find.text('open')),
      );
    }
  });

  group('the list screen overlays', () {
    // Menu order: search, sort, pause all, resume all, refresh interval.
    const sort = 1;
    const pauseAll = 2;
    const resumeAll = 3;
    const interval = 4;

    Future<void> overlay(WidgetTester tester, int menuIndex) async {
      await pumpMatrix(
        tester,
        (v) => screenApp(
          v,
          client: () async => FakeTorrentClient(torrents: allStates()),
        ),
        variants: _coverage,
        verify: (v) async {
          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate((w) => w is PopupMenuItem).at(menuIndex),
          );
          await tester.pumpAndSettle();
          expectNoFrameworkExceptions(tester, context: v.label);
          await _overlayA11y(tester);
        },
      );
    }

    testWidgets('sort sheet', (tester) => overlay(tester, sort));
    testWidgets('poll dialog', (tester) => overlay(tester, interval));
    testWidgets('pause-all confirm', (tester) => overlay(tester, pauseAll));
    testWidgets('resume-all confirm', (tester) => overlay(tester, resumeAll));
  });

  group('detail and limits sheets: loading and error', () {
    testWidgets('detail: loading', (tester) async {
      final c = FakeTorrentClient();
      await pumpMatrix(
        tester,
        (v) => sheetApp(
          v,
          const TorrentDetailSheet(hash: 'hash1'),
          client: c,
          clientGate: _never(),
        ),
        variants: _coverage,
        verify: (v) => _a11y(tester, v),
      );
    });

    testWidgets('detail: error', (tester) async {
      final c = FakeTorrentClient()
        ..detailError = const AppError(ErrorCategory.timeout);
      await pumpMatrix(
        tester,
        (v) => sheetApp(v, const TorrentDetailSheet(hash: 'hash1'), client: c),
        variants: _coverage,
        verify: (v) => _a11y(tester, v),
      );
    });

    testWidgets('limits: loading', (tester) async {
      await pumpMatrix(
        tester,
        (v) => sheetApp(
          v,
          const SpeedLimitsSheet(),
          client: FakeTorrentClient(),
          clientGate: _never(),
        ),
        variants: _coverage,
        verify: (v) => _a11y(tester, v),
      );
    });

    testWidgets('limits: error', (tester) async {
      final c = FakeTorrentClient()
        ..limitsError = const AppError(ErrorCategory.serverError);
      await pumpMatrix(
        tester,
        (v) => sheetApp(v, const SpeedLimitsSheet(), client: c),
        variants: _coverage,
        verify: (v) => _a11y(tester, v),
      );
    });
  });

  testWidgets('a row is reachable from a long press (row menu)', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => screenApp(
        v,
        client: () async => FakeTorrentClient(torrents: allStates()),
      ),
      variants: _coverage,
      verify: (v) async {
        await tester.ensureVisible(find.byType(TorrentRow).first);
        await tester.longPress(find.byType(TorrentRow).first);
        await tester.pumpAndSettle();
        expectNoFrameworkExceptions(tester, context: v.label);
        await _overlayA11y(tester);
      },
    );
  });
}

Completer<TorrentClient?> _never() => Completer<TorrentClient?>();
