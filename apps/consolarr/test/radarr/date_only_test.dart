// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/domain/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendarDayOf (date-only values sent as midnight UTC)', () {
    test('keeps the UTC date for a UTC value', () {
      final d = calendarDayOf(DateTime.utc(2026, 5, 1));
      expect((d.year, d.month, d.day), (2026, 5, 1));
      expect(d.isUtc, isFalse);
    });

    test('is the same for the same instant in any zone', () {
      final instant = DateTime.utc(2026, 5, 1);
      // The instant as the device holds it after `.toLocal()`.
      final local = DateTime.fromMillisecondsSinceEpoch(
        instant.millisecondsSinceEpoch,
      );
      expect(calendarDayOf(local), calendarDayOf(instant));
    });

    test('toLocal() west of UTC would be a day early; the helper is not', () {
      final instant = DateTime.utc(2026, 5, 1);
      // What `.toLocal()` gives at UTC-8 (simulated): the previous day.
      final shifted = instant.subtract(const Duration(hours: 8));
      expect(shifted.day, 30);
      final d = calendarDayOf(instant);
      expect(d.day, 1);
      expect(d.month, 5);
    });

    test('same day for every UTC time of day', () {
      expect(calendarDayOf(DateTime.utc(2026, 5, 1, 23, 59)).day, 1);
      expect(calendarDayOf(DateTime.utc(2026, 12, 31)).month, 12);
    });
  });
}
