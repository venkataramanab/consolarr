// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// A scriptable [TorrentClient]. Results can be swapped between polls.
class FakeTorrentClient implements TorrentClient {
  FakeTorrentClient({
    List<Torrent> torrents = const [],
    TransferInfo? transfer = const TransferInfo(
      dlSpeed: 1536,
      upSpeed: 512,
      dlTotal: 0,
      upTotal: 0,
    ),
  }) : _torrents = Result.ok(torrents),
       _transfer = transfer == null
           ? const Result.err(AppError(ErrorCategory.serverError))
           : Result.ok(transfer);

  Result<List<Torrent>> _torrents;
  Result<TransferInfo> _transfer;
  int listCalls = 0;
  Completer<void>? gate;

  /// From this (1-based) call on, `listTorrents` fails with a timeout.
  int? failFromCall;

  void setTorrents(List<Torrent> t) => _torrents = Result.ok(t);
  void failTorrents(ErrorCategory c) => _torrents = Result.err(AppError(c));
  void setTransfer(TransferInfo t) => _transfer = Result.ok(t);
  void failTransfer() =>
      _transfer = const Result.err(AppError(ErrorCategory.serverError));

  @override
  ServiceKind get kind => ServiceKind.qbittorrent;

  @override
  Future<Result<String>> fetchVersion() async => const Result.ok('v4.6.3');

  @override
  Future<Result<List<Torrent>>> listTorrents() async {
    listCalls++;
    await gate?.future;
    final from = failFromCall;
    if (from != null && listCalls >= from) {
      return const Result.err(AppError(ErrorCategory.timeout));
    }
    return _torrents;
  }

  @override
  Future<Result<TransferInfo>> transferInfo() async => _transfer;
}

Torrent sampleTorrent(
  int i, {
  TorrentState state = TorrentState.downloading,
  double progress = 0.42,
  String? name,
}) => Torrent(
  hash: 'hash$i',
  name: name ?? 'Example Torrent $i',
  state: state,
  progress: progress,
  size: 1024 * 1024 * 700 * (i + 1),
  dlSpeed: state == TorrentState.downloading ? 2 * 1024 * 1024 : 0,
  upSpeed: state == TorrentState.seeding ? 64 * 1024 : 0,
  ratio: 0.5 + i,
  eta: state == TorrentState.downloading ? const Duration(minutes: 42) : null,
);

/// One torrent in every state.
List<Torrent> allStates() => [
  for (final (i, s) in TorrentState.values.indexed)
    sampleTorrent(
      i,
      state: s,
      progress: s == TorrentState.finished || s == TorrentState.seeding
          ? 1
          : 0.1 * (i + 1),
    ),
];

final fixedNow = DateTime.utc(2026, 1, 1, 12);

/// A screen under the harness with reduced motion (so `pumpAndSettle`
/// completes) and the given client.
Widget screenApp(
  HarnessVariant variant, {
  required Future<TorrentClient?> Function() client,
  Duration pollInterval = const Duration(days: 1),
  bool reduceMotion = true,
  VoidCallback? onAddServer,
  VoidCallback? onSpeedHeaderTap,
  bool tickerEnabled = true,
}) {
  return ProviderScope(
    overrides: [
      torrentClientProvider.overrideWith((ref) => client()),
      torrentPollIntervalProvider.overrideWithValue(pollInterval),
      clockProvider.overrideWithValue(() => fixedNow),
    ],
    child: harnessApp(
      variant,
      Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: reduceMotion),
            child: TickerMode(
              enabled: tickerEnabled,
              child: Scaffold(
                extendBody: true,
                body: TorrentListScreen(
                  onAddServer: onAddServer,
                  onSpeedHeaderTap: onSpeedHeaderTap,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

const baseVariant = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

/// The reduced matrix used by state tests: small and large phone, both
/// extremes of text scale, all locales, dark only (light is covered by
/// component tests and goldens).
List<HarnessVariant> stateMatrix() => harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  brightnesses: const [Brightness.dark],
);

/// Pumps [client] on every [stateMatrix] variant, failing on overflow and
/// running the accessibility guidelines for scale 2.0 in ar and en_XA.
Future<void> expectStateSurvivesMatrix(
  WidgetTester tester,
  Future<TorrentClient?> Function() client, {
  Future<void> Function(HarnessVariant)? verify,
}) async {
  await pumpMatrix(
    tester,
    (v) => screenApp(v, client: client),
    variants: stateMatrix(),
    verify: (v) async {
      if (v.textScale == 2 && v.locale.languageCode != 'en' ||
          v.textScale == 2 && v.locale.countryCode == 'XA') {
        await expectAccessible(tester);
      }
      await verify?.call(v);
    },
  );
}
