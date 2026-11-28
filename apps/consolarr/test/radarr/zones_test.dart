// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import '../support/zone_runner.dart';

/// Release dates are date-only (midnight UTC); "today" is the user's local
/// calendar date. The extremes are where a UTC-day or an instant comparison
/// goes wrong, so the rule is run with the process really set to those zones.
void main() {
  for (final (zone, hours) in const [
    ('Pacific/Kiritimati', 14),
    ('Etc/GMT+12', -12),
    ('UTC', 0),
    ('America/Los_Angeles', -8),
  ]) {
    test('release dates against the local date at UTC${hours >= 0 ? '+' : ''}'
        '$hours ($zone)', () async {
      await runUnderZone(
        zone: zone,
        expectedHours: hours,
        script: 'test/radarr/zones/zone_checks.dart',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
