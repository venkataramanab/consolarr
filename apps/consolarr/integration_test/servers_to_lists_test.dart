// SPDX-License-Identifier: GPL-3.0-or-later

// Nightly emulator test against real Sonarr and qBittorrent containers (see
// tools/integration). Adds both servers through the app's own repository,
// opens both lists, then runs one toxiproxy latency + drop scenario.

import 'dart:convert';
import 'dart:io';

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

const _host = String.fromEnvironment('IT_HOST');
const _sonarrPort = String.fromEnvironment('IT_SONARR_PORT');
const _qbitPort = String.fromEnvironment('IT_QBIT_PORT');
const _toxiSonarrPort = String.fromEnvironment('IT_TOXI_SONARR_PORT');
const _toxiApi = String.fromEnvironment('IT_TOXI_API');
const _sonarrKey = String.fromEnvironment('IT_SONARR_API_KEY');
const _qbitUser = String.fromEnvironment('IT_QBIT_USERNAME');
const _qbitPassword = String.fromEnvironment('IT_QBIT_PASSWORD');

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _toxiRequest(String method, String path, [Object? body]) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$_toxiApi$path'));
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    await response.drain<void>();
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adds both servers and shows both lists, then survives a '
      'latency + connection-drop scenario', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ConsolarrApp(),
      ),
    );
    await tester.pumpAndSettle();

    final repo = container.read(serverRepositoryProvider);
    final sonarr = await repo.save(
      const ServerDraft(
        name: 'Example Sonarr',
        kind: ServiceKind.sonarr,
        address: 'http://$_host:$_sonarrPort',
        allowCleartext: true,
        credentials: ServerCredentials(apiKey: _sonarrKey),
      ),
    );
    expect(sonarr.isOk, isTrue);
    final qbit = await repo.save(
      const ServerDraft(
        name: 'Example qBittorrent',
        kind: ServiceKind.qbittorrent,
        address: 'http://$_host:$_qbitPort',
        authMode: AuthMode.basic,
        allowCleartext: true,
        credentials: ServerCredentials(
          username: _qbitUser,
          password: _qbitPassword,
        ),
      ),
    );
    expect(qbit.isOk, isTrue);
    await tester.pumpAndSettle();

    // Series library.
    await tester.tap(find.text(l10n.navSonarr));
    await _pumpUntil(tester, find.byType(PosterCard));
    expect(find.byType(PosterCard), findsWidgets);

    // Torrent list.
    await tester.tap(find.text(l10n.navTorrents));
    await _pumpUntil(tester, find.byType(ProgressFillRow));
    expect(find.byType(ProgressFillRow), findsWidgets);

    // Fault scenario through toxiproxy: latency, then a dropped connection.
    final proxied = await repo.save(
      const ServerDraft(
        name: 'Example Sonarr via proxy',
        kind: ServiceKind.sonarr,
        address: 'http://$_host:$_toxiSonarrPort',
        allowCleartext: true,
        credentials: ServerCredentials(apiKey: _sonarrKey),
      ),
    );
    await repo.setActive(ServiceKind.sonarr, proxied.valueOrNull!.profile.id);
    await _toxiRequest('POST', '/proxies/sonarr/toxics', {
      'name': 'latency',
      'type': 'latency',
      'attributes': {'latency': 800},
    });
    await tester.tap(find.text(l10n.navSonarr));
    await _pumpUntil(tester, find.byType(PosterCard));

    await _toxiRequest('POST', '/proxies/sonarr/toxics', {
      'name': 'drop',
      'type': 'limit_data',
      'attributes': {'bytes': 0},
    });
    // Pull to refresh while the connection drops: the cached list stays and
    // the offline banner appears.
    await tester.fling(
      find.byType(PosterCard).first,
      const Offset(0, 400),
      800,
    );
    await _pumpUntil(tester, find.byType(OfflineBanner));
    expect(find.byType(PosterCard), findsWidgets);

    await _toxiRequest('DELETE', '/proxies/sonarr/toxics/drop');
    await _toxiRequest('DELETE', '/proxies/sonarr/toxics/latency');
  });
}
