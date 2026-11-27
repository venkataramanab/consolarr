// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

class _Sonarr implements SonarrApi {
  @override
  ServiceKind get kind => ServiceKind.sonarr;
  @override
  Future<Result<ArrSystemStatus>> systemStatus() async =>
      const Result.ok(ArrSystemStatus(version: '4.0.0.0'));
}

class _Radarr implements RadarrApi {
  @override
  ServiceKind get kind => ServiceKind.radarr;
  @override
  Future<Result<ArrSystemStatus>> systemStatus() async =>
      const Result.err(AppError(ErrorCategory.unsupportedVersion));
}

void main() {
  test('SonarrApi and RadarrApi share the ArrApi surface', () async {
    final ArrApi sonarr = _Sonarr();
    final ArrApi radarr = _Radarr();
    expect(sonarr.kind, ServiceKind.sonarr);
    expect((await sonarr.systemStatus()).valueOrNull?.version, '4.0.0.0');
    expect(radarr.kind, ServiceKind.radarr);
    expect(
      (await radarr.systemStatus()).errorOrNull?.category,
      ErrorCategory.unsupportedVersion,
    );
  });
}
