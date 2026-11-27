// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/presentation/detail/series_detail_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';

/// Records the links that were opened.
class FakeLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

/// Artwork that records the images it hands out (a 1x1 transparent PNG).
class MemoryArtwork extends DetailArtwork {
  MemoryArtwork() : super(dio: Dio(), api: ScriptedSonarrApi());

  static final _png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider? poster(SonarrSeries series) => MemoryImage(_png);

  @override
  ImageProvider? backdrop(SonarrSeries series) => MemoryImage(_png);
}

/// The detail screen of [seriesId] inside the harness app with the Sonarr
/// providers faked at the API.
Widget detailApp(
  HarnessVariant variant, {
  required ScriptedSonarrApi api,
  int seriesId = 1,
  FakeLauncher? launcher,
  DetailArtwork? artwork,
  MemoryPayloadCache? cache,
  DateTime? now,
}) {
  return ProviderScope(
    overrides: [
      ...sonarrTestOverrides(api, cache: cache, now: now),
      searchPollDelaysProvider.overrideWithValue(const [
        Duration.zero,
        Duration.zero,
      ]),
      detailArtworkProvider.overrideWithValue(artwork),
      externalLinkLauncherProvider.overrideWithValue(
        launcher ?? FakeLauncher(),
      ),
    ],
    child: harnessApp(
      variant,
      ConsolarrEffectsScope(
        reduceMotion: true,
        child: SeriesDetailScreen(seriesId: seriesId),
      ),
    ),
  );
}

/// An API with a detail, a few episodes and profiles/tags.
ScriptedSonarrApi detailApi({
  int episodes = 4,
  bool monitored = true,
  String? overview = 'An example overview.',
}) {
  return ScriptedSonarrApi()
    ..detailResult = Result.ok(
      fakeDetail(1, monitored: monitored, overview: overview),
    )
    ..episodesResult = Result.ok([
      for (var i = 1; i <= episodes; i++)
        fakeEpisode(
          i,
          season: i <= 2 ? 1 : 2,
          number: i <= 2 ? i : i - 2,
          hasFile: i == 1,
          airs: i == 4 ? DateTime.utc(2027, 1, 1) : DateTime.utc(2026, 4, i),
        ),
    ])
    ..profilesResult = const Result.ok([
      ArrQualityProfile(id: 1, name: 'HD-1080p'),
      ArrQualityProfile(id: 2, name: 'Any'),
    ])
    ..tagsResult = const Result.ok([ArrTag(id: 5, label: 'kids')]);
}
