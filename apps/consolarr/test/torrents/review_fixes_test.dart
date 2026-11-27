// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/application/torrent_view.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/digit_input.dart';
import 'package:consolarr/features/torrents/presentation/error_text.dart';
import 'package:consolarr/features/torrents/presentation/host_picker.dart';
import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:consolarr/features/torrents/presentation/speed_header.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_row.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

const _ar = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('ar'),
  brightness: Brightness.dark,
);

final _latinDigit = RegExp('[0-9]');
final _arabicIndicDigit = RegExp('[٠-٩]');

/// A string never mixes the two numeral systems.
void _expectOneNumeralSystem(String text) {
  expect(
    _latinDigit.hasMatch(text) && _arabicIndicDigit.hasMatch(text),
    isFalse,
    reason: 'mixed numerals in: $text',
  );
}

bool _anyLiveRegion(WidgetTester tester) {
  var live = false;
  void visit(SemanticsNode n) {
    final data = n.getSemanticsData();
    // The framework's own expansion tile announces "Collapsed"/"Expanded".
    if (data.flagsCollection.isLiveRegion &&
        data.label != 'Collapsed' &&
        data.label != 'Expanded') {
      live = true;
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  var root = tester.getSemantics(find.byType(Scaffold).first);
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return live;
}

Torrent _torrent({double ratio = 1.5, TorrentState? state}) => Torrent(
  hash: 'h',
  name: 'Example Torrent',
  state: state ?? TorrentState.downloading,
  progress: 0.42,
  size: 1024 * 1024 * 700,
  dlSpeed: 2 * 1024 * 1024,
  upSpeed: 64 * 1024,
  ratio: ratio,
  eta: const Duration(minutes: 42),
);

Future<String> _rowLabel(
  WidgetTester tester,
  Torrent t, {
  HarnessVariant variant = baseVariant,
}) async {
  applyVariantView(tester, variant);
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(
    harnessApp(variant, Scaffold(body: TorrentRow(torrent: t))),
  );
  await tester.pump();
  final label = tester.getSemantics(find.byType(ProgressFillRow)).label;
  handle.dispose();
  return label;
}

void main() {
  group('a11y 1: the row speaks speed and time left', () {
    testWidgets('en', (tester) async {
      final label = await _rowLabel(tester, _torrent());
      expect(label, contains('Example Torrent'));
      expect(label, contains('Down 2 MB/s'));
      expect(label, contains('Up 64 KB/s'));
      expect(label, contains('42m left'));
    });

    testWidgets('ar: one numeral system in the whole label', (tester) async {
      final label = await _rowLabel(tester, _torrent(), variant: _ar);
      _expectOneNumeralSystem(label);
      expect(label, isNot(contains('Down')), reason: 'localized');
    });
  });

  group('ratio -1 and -2', () {
    testWidgets('row details: dash and infinity, spoken in words', (
      tester,
    ) async {
      final unknown = await _rowLabel(tester, _torrent(ratio: -1));
      expect(unknown, contains('Ratio Unknown'));
      expect(unknown, isNot(contains('0.00')));
      final infinite = await _rowLabel(tester, _torrent(ratio: -2));
      expect(infinite, contains('Ratio Infinite'));
      await tester.pumpWidget(
        harnessApp(
          baseVariant,
          Scaffold(body: TorrentRow(torrent: _torrent(ratio: -1))),
        ),
      );
      expect(find.text('Ratio –'), findsOneWidget);
      await tester.pumpWidget(
        harnessApp(
          baseVariant,
          Scaffold(body: TorrentRow(torrent: _torrent(ratio: -2))),
        ),
      );
      expect(find.text('Ratio ∞'), findsOneWidget);
    });

    test('sorting: unknown first, infinite last', () {
      final ts = [
        _torrent(ratio: 2),
        _torrent(ratio: -2),
        _torrent(ratio: -1),
        _torrent(ratio: 0.5),
      ];
      final sorted = applyView(
        ts,
        const TorrentView(
          tab: TorrentTab.all,
          sort: TorrentSort.ratio,
          ascending: true,
        ),
      );
      expect(sorted.map((t) => t.ratio), [-1, 0.5, 2, -2]);
    });

    testWidgets('detail sheet shows the symbols', (tester) async {
      final c = FakeTorrentClient()
        ..detail = TorrentDetail(torrent: _torrent(ratio: -2));
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(
        sheetApp(baseVariant, const TorrentDetailSheet(hash: 'h'), client: c),
      );
      await tester.pumpAndSettle();
      expect(find.text('∞'), findsOneWidget);
    });
  });

  group('detail: no-seeds hint needs the totals', () {
    Future<void> pump(WidgetTester tester, TorrentDetail d) async {
      final c = FakeTorrentClient()..detail = d;
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(
        sheetApp(baseVariant, const TorrentDetailSheet(hash: 'h'), client: c),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('seeds 0 and total unknown: no hint', (tester) async {
      await pump(tester, TorrentDetail(torrent: _torrent(), seeds: 0));
      expect(find.textContaining('No seeds are connected'), findsNothing);
    });

    testWidgets('seeds 0 and total 0: hint', (tester) async {
      await pump(
        tester,
        TorrentDetail(torrent: _torrent(), seeds: 0, seedsTotal: 0),
      );
      expect(find.textContaining('No seeds are connected'), findsOneWidget);
    });
  });

  group('errors', () {
    testWidgets('Transmission 403 names the host whitelist', (tester) async {
      final c = FakeTorrentClient()
        ..failWith(
          const AppError(
            ErrorCategory.authFailed,
            debugDetail: transmissionHostNotAllowedDetail,
          ),
        );
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(screenApp(baseVariant, client: () async => c));
      await tester.pumpAndSettle();
      expect(find.textContaining('rpc-host-whitelist'), findsOneWidget);
    });

    test('a partial failure counts the torrents', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final partial = PartialActionFailure(
        category: ErrorCategory.serverError,
        failed: const ['a', 'b'],
        total: 5,
      );
      expect(
        torrentErrorReason(l10n, partial),
        startsWith('2 of 5 torrents could not be changed.'),
      );
      expect(
        torrentErrorReason(
          l10n,
          PartialActionFailure(
            category: ErrorCategory.serverError,
            failed: const ['a'],
            total: 3,
          ),
        ),
        startsWith('1 of 3 torrents could not be changed.'),
      );
    });
  });

  group('i18n 3: Arabic digits next to Arabic sizes', () {
    testWidgets('speed header count and speeds', (tester) async {
      applyVariantView(tester, _ar);
      await tester.pumpWidget(
        harnessApp(
          _ar,
          const Scaffold(
            body: SpeedHeader(
              history: [],
              torrentCount: 12,
              down: 2 * 1024 * 1024,
              up: 1024,
            ),
          ),
        ),
      );
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      _expectOneNumeralSystem(texts);
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(texts, contains(ar.plainInt(12)));
    });

    testWidgets('detail counts and durations', (tester) async {
      final c = FakeTorrentClient();
      applyVariantView(tester, _ar);
      await tester.pumpWidget(
        sheetApp(_ar, const TorrentDetailSheet(hash: 'h'), client: c),
      );
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      _expectOneNumeralSystem(texts);
    });

    testWidgets('host picker: isolated host:port, Arabic digits, no grouping', (
      tester,
    ) async {
      applyVariantView(tester, _ar);
      await tester.pumpWidget(
        harnessApp(
          _ar,
          Scaffold(
            body: DelugeHostPicker(
              hosts: const [
                DelugeHost(id: 'h1', host: 'daemon-a.example', port: 58846),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      );
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(
        find.text('\u2066daemon-a.example:${ar.plainInt(58846)}\u2069'),
        findsOneWidget,
      );
    });
  });

  group('a11y 4: speed-limit input', () {
    test('digit values of any script', () {
      expect(normalizeDigits('٥٠٠'), '500');
      expect(normalizeDigits('۱۲۳'), '123');
      expect(normalizeDigits('१२'), '12');
      expect(normalizeDigits('４２'), '42');
      expect(normalizeDigits('12a'), '12a');
      expect(decimalDigitValue('a'.codeUnitAt(0)), isNull);
    });

    test('the formatter drops everything but digits and stores ASCII', () {
      const f = AnyDigitsFormatter();
      final out = f.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '٥a٠ 0-',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(out.text, '500');
    });

    testWidgets('Arabic-Indic digits are accepted and applied', (tester) async {
      final c = FakeTorrentClient();
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(
        sheetApp(baseVariant, const SpeedLimitsSheet(), client: c),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom limit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '٥٠٠');
      await tester.tap(find.text('Apply limits'));
      await tester.pumpAndSettle();
      expect(c.lastLimits!.download, 500 * 1024);
    });

    testWidgets('after apply the fields show what the server stored', (
      tester,
    ) async {
      final c = FakeTorrentClient()..limitRounding = 1000;
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(
        sheetApp(baseVariant, const SpeedLimitsSheet(), client: c),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom limit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.tap(find.text('Apply limits'));
      await tester.pumpAndSettle();
      // 1 KB = 1024 B is stored as 2000 B and read back as 2 KB.
      expect(c.lastLimits!.download, 1024);
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);
      expect(find.text('Limits applied.'), findsOneWidget);
    });
  });

  group('add sheet', () {
    PickedTorrentFile file(int i) => PickedTorrentFile(
      name: 'f$i.torrent',
      length: () async => 20,
      readBytes: () async =>
          Uint8List.fromList('d4:infod4:name3:abcee'.codeUnits),
    );

    Future<FakeTorrentClient> pump(
      WidgetTester tester, {
      FakeTorrentClient? client,
      List<PickedTorrentFile> picks = const [],
    }) async {
      final c = client ?? FakeTorrentClient();
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(
        sheetApp(
          baseVariant,
          const AddTorrentSheet(),
          client: c,
          overrides: [
            torrentFilePickerProvider.overrideWithValue(() async => picks),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('a best-effort label failure is a warning, not an error', (
      tester,
    ) async {
      final c = await pump(
        tester,
        client: FakeTorrentClient()..labelWarning = true,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Example',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(c.addedLinks, hasLength(1));
      expect(find.text('Added to your client.'), findsOneWidget);
      expect(find.textContaining('label could not be applied'), findsOneWidget);
      expect(find.textContaining('Could not add'), findsNothing);
    });

    testWidgets('more files than the cap: the rest is reported', (
      tester,
    ) async {
      await pump(
        tester,
        picks: [for (var i = 0; i < maxPickedTorrentFiles + 3; i++) file(i)],
      );
      await tester.tap(find.text('Choose .torrent files'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 more files were ignored'), findsOneWidget);
      expect(
        find.textContaining('up to $maxPickedTorrentFiles files'),
        findsOneWidget,
      );
    });

    testWidgets('the confirmation is a live region only once typing paused', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      const magnet =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=';
      // Keystrokes in quick succession: nothing is announced.
      for (final name in ['E', 'Ex', 'Exa', 'Exam']) {
        await tester.enterText(find.byType(TextField).first, '$magnet$name');
        await tester.pump(const Duration(milliseconds: 100));
        expect(_anyLiveRegion(tester), isFalse, reason: name);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(_anyLiveRegion(tester), isTrue, reason: 'settled: announced once');
      handle.dispose();
    });
  });

  group('speed graph text alternative', () {
    test('trend and peaks', () {
      List<SpeedSample> series(List<int> downs) => [
        for (final d in downs) SpeedSample(down: d, up: 10),
      ];
      expect(
        speedTrend(series([100, 100, 100, 100, 100, 100])),
        SpeedTrend.steady,
      );
      expect(
        speedTrend(series([100, 100, 100, 100, 400, 500])),
        SpeedTrend.rising,
      );
      expect(
        speedTrend(series([500, 500, 500, 500, 50, 40])),
        SpeedTrend.falling,
      );
      expect(speedTrend(series([1, 2])), SpeedTrend.steady);
      expect(speedPeaks(series([5, 90, 7])), (down: 90, up: 10));
    });

    testWidgets('the spoken label has peaks, trend and the dashed hint', (
      tester,
    ) async {
      applyVariantView(tester, baseVariant);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        harnessApp(
          baseVariant,
          const Scaffold(
            body: SpeedHeader(
              history: [
                SpeedSample(down: 1024, up: 100),
                SpeedSample(down: 2048, up: 100),
                SpeedSample(down: 4096, up: 100),
                SpeedSample(down: 8192, up: 100),
              ],
              torrentCount: 3,
              down: 8192,
              up: 100,
            ),
          ),
        ),
      );
      await tester.pump();
      final label = tester.getSemantics(find.byType(SpeedHeader)).label;
      expect(label, contains('peak download 8 KB/s'));
      expect(label, contains('trend rising'));
      expect(label, contains('dashed'));
      handle.dispose();
    });
  });

  group('polling is silent', () {
    testWidgets('a poll tick announces nothing', (tester) async {
      final handle = tester.ensureSemantics();
      final c = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      applyVariantView(tester, baseVariant);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: () async => c,
          pollInterval: const Duration(seconds: 3),
        ),
      );
      await tester.pumpAndSettle();
      expect(_anyLiveRegion(tester), isFalse);
      final calls = c.listCalls;
      c.setTorrents([sampleTorrent(1, progress: 0.7)]);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(c.listCalls, greaterThan(calls), reason: 'the tick ran');
      expect(_anyLiveRegion(tester), isFalse, reason: 'and said nothing');
      handle.dispose();
    });
  });

  group('offline: text stays opaque and readable (AA)', () {
    for (final brightness in Brightness.values) {
      testWidgets('contrast, ${brightness.name}, scale 1', (tester) async {
        final v = HarnessVariant(
          size: const Size(412, 915),
          textScale: 1,
          locale: const Locale('en'),
          brightness: brightness,
        );
        applyVariantView(tester, v);
        final c = FakeTorrentClient(torrents: allStates())..failFromCall = 2;
        await tester.pumpWidget(screenApp(v, client: () async => c));
        await tester.pumpAndSettle();
        await ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
            .read(torrentListProvider.notifier)
            .refresh();
        await tester.pumpAndSettle();
        expect(find.byType(OfflineBanner), findsOneWidget);
        // No dimming wrapper around the rows.
        expect(find.byType(SliverOpacity), findsNothing);
        expect(
          find.ancestor(
            of: find.byType(TorrentRow).first,
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        await expectTextContrast(tester);
      });
    }
  });
}
