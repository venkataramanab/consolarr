// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/host_picker.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

class _HostClient extends FakeTorrentClient implements DaemonHostSelection {
  _HostClient() : super(kind: ServiceKind.deluge);

  final List<String> selected = [];

  @override
  Future<Result<List<DelugeHost>>> hosts() async => const Result.ok([]);

  @override
  Future<Result<void>> selectHost(String id) async {
    selected.add(id);
    // Once connected the list loads.
    setTorrents([sampleTorrent(1)]);
    return const Result.ok(null);
  }
}

const _hosts = [
  DelugeHost(id: 'h1', host: 'daemon-a.example', port: 58846),
  DelugeHost(id: 'h2', host: '<b>not markup</b> daemon-b.example', port: 58847),
];

void main() {
  testWidgets('several daemons: a picker; choosing one connects and loads', (
    tester,
  ) async {
    final c = _HostClient()..failWith(const DelugeHostRequired(_hosts));
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(screenApp(baseVariant, client: () async => c));
    await tester.pumpAndSettle();
    expect(find.byType(DelugeHostPicker), findsOneWidget);
    expect(find.text('Choose a Deluge daemon'), findsOneWidget);
    expect(find.text('daemon-a.example:58846'), findsOneWidget);
    // Server text is plain text, never markup.
    expect(
      find.text('<b>not markup</b> daemon-b.example:58847'),
      findsOneWidget,
    );
    await tester.tap(find.text('daemon-a.example:58846'));
    await tester.pumpAndSettle();
    expect(c.selected, ['h1']);
    expect(find.byType(DelugeHostPicker), findsNothing);
    expect(find.text('Example Torrent 1'), findsOneWidget);
  });

  testWidgets('the picker survives the stress matrix', (tester) async {
    final c = _HostClient()..failWith(const DelugeHostRequired(_hosts));
    await expectStateSurvivesMatrix(tester, () async => c);
  });
}
