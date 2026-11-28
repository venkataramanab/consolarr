// SPDX-License-Identifier: GPL-3.0-or-later

// Run by `zones_test.dart` as a child process with TZ set (see
// `test/support/zone_runner.dart`). Plain Dart: no Flutter, no test package;
// a failed check throws, which makes the exit code non-zero.

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/features/radarr/domain/dates.dart';
import 'package:consolarr/features/radarr/domain/wanted.dart';

void check(bool ok, String what) {
  if (!ok) throw StateError('FAILED: $what');
}

RadarrMovie movie(
  int id, {
  DateTime? inCinemas,
  DateTime? digital,
  MinimumAvailability min = MinimumAvailability.released,
}) => RadarrMovie(
  id: id,
  title: 'Example $id',
  sortTitle: 'example $id',
  year: 2026,
  monitored: true,
  hasFile: false,
  sizeOnDisk: 0,
  inCinemas: inCinemas,
  digitalRelease: digital,
  qualityProfileId: 1,
  minimumAvailability: min,
  tags: const [],
  genres: const [],
  added: DateTime.utc(2026),
  images: const [],
);

void main(List<String> args) {
  final expectedHours = int.parse(args.single);
  // The zone must really be applied, or these checks would test UTC.
  final january = DateTime(2026, 1, 1).timeZoneOffset;
  check(
    january == Duration(hours: expectedHours),
    'the process runs at UTC${expectedHours >= 0 ? '+' : ''}$expectedHours, '
    'not $january (is the zone database installed?)',
  );

  // Release dates are date-only values at midnight UTC.
  final jun9 = DateTime.utc(2026, 6, 9);
  final jun10 = DateTime.utc(2026, 6, 10);
  final jun11 = DateTime.utc(2026, 6, 11);

  // The user's local midnight starting 10 June, as an instant, and the second
  // before it: the two moments the rule must flip between.
  final midnight = DateTime(2026, 6, 10).toUtc();
  final justBefore = midnight.subtract(const Duration(seconds: 1));

  // --- localDateOf: the user's calendar date, as a date value --------------
  check(localDateOf(justBefore) == jun9, 'a second before local midnight: 9th');
  check(localDateOf(midnight) == jun10, 'at local midnight: 10th');
  check(localDateOf(midnight).isUtc, 'a date value is marked UTC');

  // --- the day a release date names does not move with the zone ------------
  for (final d in [jun9, jun10, jun11]) {
    check(releaseDateOf(d) == d, 'release date $d names its own day');
    check(releaseDateOf(d.toLocal()) == d, 'also after toLocal()');
  }

  // --- before / arrived, across local midnight ------------------------------
  check(!isReleaseDayBefore(jun9, justBefore), '9th is today at 23:59:59');
  check(
    isReleaseDayBefore(jun9, midnight),
    '9th is behind at 00:00:00 on 10th',
  );
  check(!isReleaseDayBefore(jun10, midnight), '10th is today on the 10th');
  check(!isReleaseDayBefore(jun10, justBefore), '10th is ahead on the 9th');
  check(!hasReleaseDayArrived(jun10, justBefore), '10th has not arrived yet');
  check(
    hasReleaseDayArrived(jun10, midnight),
    '10th arrives at local midnight',
  );
  check(hasReleaseDayArrived(jun9, midnight), '9th has arrived');

  // --- availability follows the same rule -----------------------------------
  final cinema10 = movie(1, inCinemas: jun10);
  check(
    availabilityOf(cinema10, justBefore) == Availability.comingSoon,
    'a 10th release is coming soon on the evening of the 9th',
  );
  check(
    availabilityOf(cinema10, midnight) == Availability.inCinemas,
    'and in cinemas from local midnight',
  );

  // --- Upcoming list: ahead is decided on the local date --------------------
  List<int> upcoming(DateTime now) => [
    for (final m in wantedMovies(
      [
        movie(1, inCinemas: jun9, digital: jun11),
        movie(2, inCinemas: jun10),
        movie(3, inCinemas: jun9),
      ],
      WantedScope.upcoming,
      now,
    ))
      m.id,
  ];
  // Evening of the 9th: 9th and later are all ahead, soonest first, ties by
  // title. Movie 3 (only the 9th) still counts.
  check(
    upcoming(justBefore).join(',') == '1,3,2',
    'the evening of the 9th: ${upcoming(justBefore)}',
  );
  // From local midnight the 9th is behind: movie 3 has nothing ahead (last),
  // movie 1 is keyed by its digital date, the 11th.
  check(
    upcoming(midnight).join(',') == '2,1,3',
    'after local midnight: ${upcoming(midnight)}',
  );
}
