// SPDX-License-Identifier: GPL-3.0-or-later

// One numeral system per locale. `ar` keeps the locale default of the pinned
// intl data (Western digits there; Arabic-Indic for `ar_EG`). Counts, sizes,
// dates and plain ids must all use that same system, never a mix.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:l10n/l10n.dart';

final _western = RegExp('[0-9]');
final _arabicIndic = RegExp('[٠-٩۰-۹]');

/// Which numeral systems appear in [text].
Set<String> numeralSystems(String text) => {
  if (_western.hasMatch(text)) 'western',
  if (_arabicIndic.hasMatch(text)) 'arabic-indic',
};

void main() {
  late AppLocalizations ar;
  late String expectedSystem;
  setUpAll(() async {
    await initializeDateFormatting('ar');
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expectedSystem = numeralSystems(NumberFormat.decimalPattern('ar').format(7))
        .single;
  });

  test('numeralSystems tells the systems apart', () {
    expect(numeralSystems('12'), {'western'});
    expect(numeralSystems('١٢'), {'arabic-indic'});
    expect(numeralSystems('1 ٢'), {'western', 'arabic-indic'});
    expect(numeralSystems('none'), isEmpty);
  });

  test('counts, sizes, plain ints and dates share the locale numerals', () {
    final samples = <String>[
      ar.torCount(12),
      ar.torUnitMB(1.5),
      ar.plainInt(1080),
      ar.radarrResolution(ar.plainInt(1080)),
      ar.sonarrDetailAirDate(DateTime(2026, 3, 4)),
      ar.sonarrSeasonCount(3),
      ar.sonarrEpisodesShort(5, 12),
      ar.onboardingStepOf(2, 4),
      ar.radarrSeeders(1234),
      ar.sonarrAgeDays(3),
    ];
    for (final text in samples) {
      expect(
        numeralSystems(text).difference({expectedSystem}),
        isEmpty,
        reason: '"$text" mixes numeral systems',
      );
    }
    // The samples really do contain digits (the check is not vacuous).
    expect(samples.where((s) => numeralSystems(s).isNotEmpty).length, 10);
  });
}
