// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:test_harness/test_harness.dart';

import 'support.dart';

/// The smallest phone, the two locales that stress layout and scale 2.0.
final stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

/// A normal phone in English.
final phone = harnessMatrix(
  sizes: const [Size(360, 800)],
  textScales: const [1],
  locales: const [Locale('en')],
  brightnesses: const [Brightness.dark],
);

/// [child] inside the harness app with the fake Radarr [api] behind the real
/// providers (so state transitions are the real notifiers').
Widget radarrApp(
  HarnessVariant variant,
  FakeRadarrApi api,
  Widget child, {
  List<Override> extra = const [],
  MemoryPayloadCache? cache,
  MemoryPrefs? prefs,
  bool reduceMotion = true,
  bool includeContext = true,
  ArtworkSource? artwork,
  MovieRunner? movieRunner,
  DateTime Function()? clock,
}) {
  return ProviderScope(
    overrides: [
      ...radarrOverrides(
        api,
        cache: cache,
        prefs: prefs,
        includeContext: includeContext,
        movieRunner: movieRunner,
        clock: clock,
      ),
      artworkSourceProvider.overrideWithValue(artwork),
      ...extra,
    ],
    child: harnessApp(
      variant,
      ConsolarrEffectsScope(
        reduceMotion: reduceMotion,
        child: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(bottom: 88)),
              child: Scaffold(
                backgroundColor: context.roles.page,
                body: Material(type: MaterialType.transparency, child: child),
              ),
            );
          },
        ),
      ),
    ),
  );
}
