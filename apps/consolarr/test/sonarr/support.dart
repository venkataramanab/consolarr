// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test_harness/test_harness.dart';

/// A fake Sonarr API with scripted answers.
class FakeSonarrApi implements SonarrApi {
  FakeSonarrApi({
    this.seriesResult = const Result.ok([]),
    this.statusResult = const Result.ok(ArrSystemStatus(version: '4.0.1.0')),
  });

  Result<List<SonarrSeries>> seriesResult;
  Result<ArrSystemStatus> statusResult;
  int seriesCalls = 0;
  int statusCalls = 0;

  @override
  ServiceKind get kind => ServiceKind.sonarr;

  @override
  Future<Result<List<SonarrSeries>>> series() async {
    seriesCalls++;
    return seriesResult;
  }

  @override
  Future<Result<ArrSystemStatus>> systemStatus() async {
    statusCalls++;
    return statusResult;
  }

  @override
  Uri? artworkUri(SonarrSeries series, SonarrImageType type) => null;
}

/// Fake series with plain, fictional data.
SonarrSeries fakeSeries(
  int i, {
  String? title,
  SeriesStatus status = SeriesStatus.continuing,
  bool monitored = true,
  int files = 8,
  int total = 10,
  DateTime? nextAiring,
}) => SonarrSeries(
  id: i,
  title: title ?? 'Example Show $i',
  sortTitle: (title ?? 'Example Show $i').toLowerCase(),
  year: 2000 + i % 25,
  status: status,
  monitored: monitored,
  network: 'Example Network',
  nextAiring: nextAiring,
  images: [
    SonarrImage(
      type: SonarrImageType.poster,
      url: '/MediaCover/$i/poster.jpg?lastWrite=1',
    ),
  ],
  statistics: SeriesStatistics(
    seasonCount: 2,
    episodeFileCount: files,
    episodeCount: total,
    totalEpisodeCount: total,
    sizeOnDisk: 3 * 1024 * 1024 * 1024,
    percentOfEpisodes: files * 100 / total,
  ),
);

List<SonarrSeries> fakeSeriesList(int n) => [
  for (var i = 1; i <= n; i++) fakeSeries(i),
];

String seriesJson(List<SonarrSeries> list) =>
    jsonEncode([for (final s in list) s.toJson()]);

ServerProfile fakeProfile() => ServerProfile.parse(
  id: 'srv1',
  name: 'Example',
  kind: ServiceKind.sonarr,
  address: 'https://sonarr.example',
).valueOrNull!;

/// A connection whose Dio answers with [adapter].
ServerConnection fakeConnection(HttpClientAdapter adapter) {
  final profile = fakeProfile();
  final dio = Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
    ..httpClientAdapter = adapter;
  return ServerConnection(profile: profile, dio: dio);
}

HttpClientAdapter jsonAdapter(String body) => StubAdapter.json(body);
