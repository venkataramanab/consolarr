// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/observability.dart';
import 'package:test/test.dart';

void main() {
  test('counts fall into 0 / 1 / 2 / 3-5 / 6+', () {
    final expected = {
      -3: CountBucketParam.zero,
      0: CountBucketParam.zero,
      1: CountBucketParam.one,
      2: CountBucketParam.two,
      3: CountBucketParam.threeToFive,
      5: CountBucketParam.threeToFive,
      6: CountBucketParam.sixPlus,
      4000: CountBucketParam.sixPlus,
    };
    expected.forEach(
      (n, bucket) => expect(countBucket(n), bucket, reason: '$n'),
    );
  });

  test('labels are the bucket text, never the exact count', () {
    expect([0, 1, 2, 3, 5, 6, 99].map(countBucketLabel), [
      '0',
      '1',
      '2',
      '3-5',
      '3-5',
      '6+',
      '6+',
    ]);
  });

  test('major versions are a closed set; unknown is omitted', () {
    expect(majorVersionParam(null), isNull);
    expect(majorVersionParam(0), isNull);
    expect(majorVersionParam(4), MajorVersionParam.v4);
    expect(majorVersionParam(6), MajorVersionParam.v6);
    expect(majorVersionParam(7), MajorVersionParam.v7OrLater);
    expect(majorVersionParam(2026), MajorVersionParam.v7OrLater);
  });

  test('bucketed events carry the bucket code, not the count', () {
    expect(
      PollCycleFinishedEvent(
        servers: countBucket(4),
        failed: countBucket(0),
        changes: countBucket(17),
      ).parameters,
      {'servers': 'three_to_five', 'failed': 'zero', 'changes': 'six_plus'},
    );
    expect(
      DashboardRefreshedEvent(
        trigger: DashboardTriggerParam.pull,
        servers: countBucket(1),
        failed: countBucket(2),
      ).parameters,
      {'trigger': 'pull', 'servers': 'one', 'failed': 'two'},
    );
  });

  test('the diagnostics line shows a bucket, not the exact server count', () {
    String line(int n) => DiagnosticsServiceEntry(
      kind: ServiceKindParam.sonarr,
      servers: n,
      health: ServiceHealthBucket.notChecked,
    ).line;
    expect(line(4), startsWith('sonarr: servers=3-5,'));
    expect(line(9), startsWith('sonarr: servers=6+,'));
    expect(line(2), startsWith('sonarr: servers=2,'));
    expect(line(4), isNot(contains('servers=4')));
  });
}
