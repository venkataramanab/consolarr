// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

void main() {
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('Arabic plural categories: zero, one, two, few, many, other', () {
    // zero (0), one (1), two (2), few (3-10), many (11-99), other (100).
    expect(ar.sonarrSeasonCount(0), 'لا مواسم');
    expect(ar.sonarrSeasonCount(1), 'موسم واحد');
    expect(ar.sonarrSeasonCount(2), 'موسمان');
    expect(ar.sonarrSeasonCount(5), contains('مواسم'));
    expect(ar.sonarrSeasonCount(11), contains('موسمًا'));
    expect(ar.sonarrSeasonCount(100), isNot(contains('موسمًا')));
    expect(ar.sonarrReleaseSeeders(0), 'لا مصادر');
    expect(ar.arrCommonQueueWarningCount(0), 'لا رسائل');
    expect(ar.sonarrReleaseAgeDays(11), contains('يومًا'));
    expect(ar.sonarrReleaseAgeDays(100), isNot(contains('يومًا')));
  });

  test('zero and many forms exist for ages, progress and filters', () {
    expect(ar.sonarrAgeMinutes(0), 'الآن');
    expect(ar.sonarrAgeHours(0), contains('أقل من ساعة'));
    expect(ar.sonarrAgeDays(0), 'اليوم');
    expect(ar.sonarrReleaseAgeMinutes(0), contains('أقل من دقيقة'));
    expect(ar.sonarrReleaseAgeHours(0), contains('أقل من ساعة'));
    expect(ar.sonarrReleaseAgeDays(0), contains('أقل من يوم'));
    expect(ar.sonarrEpisodesProgress(0, 0), '0/0 حلقة');
    expect(ar.sonarrLibraryFilterChipSemantics(11), contains('مرشحًا'));
    expect(ar.sonarrLibraryFilterChipSemantics(100), isNot(contains('مرشحًا')));
    expect(ar.sonarrLibraryFilterChip(11), contains('11'));
    expect(ar.sonarrReleaseFilters(11), contains('11'));
  });

  test('the episode codes are Arabic, not Latin letters', () {
    expect(ar.sonarrQueueEpisodeCode(1, 2), isNot(matches('[A-Za-z]')));
    expect(ar.sonarrCalendarEpisodeCode(1, 2), isNot(matches('[A-Za-z]')));
  });
}
