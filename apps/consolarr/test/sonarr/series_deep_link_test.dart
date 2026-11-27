// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'tab_harness.dart';

void main() {
  test('only plain positive 32-bit ids are accepted', () {
    expect(parseSeriesId('7'), 7);
    expect(parseSeriesId('2147483647'), 2147483647);
    for (final bad in [
      null,
      '',
      'abc',
      '-1',
      '0',
      '007',
      '+5',
      ' 5',
      '5 ',
      '1.5',
      '0x10',
      '2147483648',
      '99999999999999999999',
    ]) {
      expect(parseSeriesId(bad), isNull, reason: '$bad');
    }
  });

  for (final bad in ['abc', '-1', '0', '99999999999999999999']) {
    testWidgets('/sonarr/series/$bad shows not found with no request', (
      tester,
    ) async {
      final api = ScriptedSonarrApi();
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        initialLocation: '/sonarr/series/$bad',
        routes: [
          GoRoute(
            path: sonarrRoute,
            builder: (context, state) => const Scaffold(),
            routes: sonarrChildRoutes,
          ),
        ],
      );
      addTearDown(router.dispose);
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(
        ProviderScope(
          overrides: sonarrTestOverrides(api),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This series no longer exists'), findsOneWidget);
      expect(api.calls, isEmpty);
    });
  }
}
