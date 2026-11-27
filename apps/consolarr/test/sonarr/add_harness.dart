// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:consolarr/features/sonarr/application/add_series.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:consolarr/features/sonarr/presentation/add/add_series_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'release_harness.dart';

SonarrLookupResult fakeLookup(int i, {bool inLibrary = false}) =>
    SonarrLookupResult.fromJson({
      if (inLibrary) 'id': i,
      'title': 'Example Show $i',
      'sortTitle': 'example show $i',
      'tvdbId': 1000 + i,
      'year': 2010 + i,
      'network': 'Example Network',
      'status': 'continuing',
      'images': [
        {
          'coverType': 'poster',
          'url': 'https://artwork.example/$i.jpg',
          'remoteUrl': 'https://artwork.example/$i.jpg',
        },
      ],
      'seasons': [
        {'seasonNumber': 1, 'monitored': true},
      ],
    });

/// A scripted API with one profile, one root folder and one tag.
ScriptedSonarrApi addApi({
  List<SonarrLookupResult> results = const [],
  bool usable = true,
}) => ScriptedSonarrApi()
  ..lookupResult = Result.ok(results)
  ..profilesResult = Result.ok(
    usable ? const [ArrQualityProfile(id: 4, name: 'HD-1080p')] : const [],
  )
  ..foldersResult = Result.ok(
    usable
        ? const [
            ArrRootFolder(id: 1, path: '/media/tv'),
            ArrRootFolder(id: 2, path: '/media/anime'),
          ]
        : const [],
  )
  ..tagsResult = const Result.ok([ArrTag(id: 1, label: 'kids')])
  ..addResult = Result.ok(fakeDetail(1));

/// How many times the library was refreshed.
class RefreshCounter {
  int count = 0;
}

/// The add screen inside the harness app.
Widget addApp(
  HarnessVariant variant,
  ScriptedSonarrApi api, {
  String? initialTerm,
  RefreshCounter? refreshes,
  SonarrPrefsStore? prefs,
  List<Override> extra = const [],
}) => ProviderScope(
  overrides: [
    ...sonarrTestOverrides(api, prefs: prefs),
    libraryRefreshProvider.overrideWithValue(() async {
      refreshes?.count++;
    }),
    ...extra,
  ],
  child: harnessApp(
    variant,
    ConsolarrEffectsScope(
      reduceMotion: true,
      child: AddSeriesScreen(initialTerm: initialTerm),
    ),
  ),
);

/// English add screen at [enVariant], with [term] typed in and settled.
Future<void> pumpAdd(
  WidgetTester tester,
  ScriptedSonarrApi api, {
  String? term,
  RefreshCounter? refreshes,
}) async {
  applyVariantView(tester, enVariant);
  await tester.pumpWidget(addApp(enVariant, api, refreshes: refreshes));
  await tester.pumpAndSettle();
  if (term != null) {
    await tester.enterText(find.byType(TextField), term);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }
}
