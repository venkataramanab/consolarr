// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/fake_adapter.dart';

class _Sonarr with EmptyArrLists implements SonarrApi {
  @override
  Future<Result<List<SonarrSeries>>> series() async => const Result.ok([]);
  @override
  Uri? artworkUri(SonarrSeries series, SonarrImageType type) => null;
  @override
  ServiceKind get kind => ServiceKind.sonarr;
  @override
  Future<Result<ArrSystemStatus>> systemStatus() async =>
      const Result.ok(ArrSystemStatus(version: '4.0.0.0'));
}

void main() {
  test('SonarrApi and RadarrApi share the ArrApi surface', () async {
    final ArrApi sonarr = _Sonarr();
    final ArrApi radarr = RadarrClient(
      dio: dioWith(FakeAdapter.fixed('{"version":"2.0.0.0"}')),
    );
    expect(sonarr.kind, ServiceKind.sonarr);
    expect((await sonarr.systemStatus()).valueOrNull?.version, '4.0.0.0');
    expect(radarr.kind, ServiceKind.radarr);
    expect(
      (await radarr.systemStatus()).errorOrNull?.category,
      ErrorCategory.unsupportedVersion,
    );
  });
}
