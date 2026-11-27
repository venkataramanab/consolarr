// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final now = DateTime.utc(2026, 5, 1, 12);

  group('searchable by minimum availability (I7)', () {
    test('announced, tba and unknown: searchable at once, with no date', () {
      for (final min in [
        MinimumAvailability.announced,
        MinimumAvailability.tba,
        MinimumAvailability.unknown,
      ]) {
        expect(
          isReleasedForSearch(fakeMovie(1, min: min), now),
          isTrue,
          reason: min.name,
        );
        expect(
          isReleasedForSearch(
            fakeMovie(1, min: min, inCinemas: DateTime.utc(2027)),
            now,
          ),
          isTrue,
          reason: '${min.name} with a future date',
        );
      }
    });

    test('inCinemas and released still wait for their dates', () {
      final future = DateTime.utc(2027);
      expect(
        isReleasedForSearch(
          fakeMovie(1, min: MinimumAvailability.inCinemas, inCinemas: future),
          now,
        ),
        isFalse,
      );
      expect(
        isReleasedForSearch(
          fakeMovie(
            1,
            min: MinimumAvailability.inCinemas,
            inCinemas: DateTime.utc(2026),
          ),
          now,
        ),
        isTrue,
      );
      expect(
        isReleasedForSearch(
          fakeMovie(1, min: MinimumAvailability.released, digital: future),
          now,
        ),
        isFalse,
      );
    });
  });
}
