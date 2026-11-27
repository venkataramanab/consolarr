// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';

/// A Sonarr tab body (calendar, missing) inside the harness app with the real
/// providers on top of [api]. Motion is reduced so skeletons settle.
Widget tabApp(
  HarnessVariant variant, {
  required SonarrApi api,
  required Widget Function(BuildContext context, EdgeInsets padding) body,
  List<Override> extra = const [],
  MemoryPayloadCache? cache,
  DateTime? now,
}) {
  return ProviderScope(
    overrides: [
      ...sonarrTestOverrides(api, cache: cache, now: now),
      artworkSourceProvider.overrideWithValue(null),
      searchPollDelaysProvider.overrideWithValue(const [Duration.zero]),
      ...extra,
    ],
    child: harnessApp(
      variant,
      ConsolarrEffectsScope(
        reduceMotion: true,
        child: Scaffold(
          body: Builder(
            builder: (context) =>
                body(context, const EdgeInsets.fromLTRB(16, 72, 16, 88)),
          ),
        ),
      ),
    ),
  );
}

/// Stress variants: smallest phone and a large one, both text scales, all
/// locales, dark theme.
final tabStress = harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  brightnesses: const [Brightness.dark],
);

/// The harshest single variant.
final tabWorst = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
  brightnesses: const [Brightness.dark],
);

HarnessVariant get plainVariant => harnessMatrix(
  sizes: const [Size(412, 915)],
  textScales: const [1],
  locales: const [Locale('en')],
  brightnesses: const [Brightness.dark],
).single;
