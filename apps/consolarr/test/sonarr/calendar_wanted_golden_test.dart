// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/calendar_providers.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_tab.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_body.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'support.dart';
import 'tab_harness.dart';

SonarrEpisode _ep(int id, int day, {bool file = false, String? finale}) =>
    SonarrEpisode(
      id: id,
      seriesId: id,
      seasonNumber: 1,
      episodeNumber: id == 1 ? 1 : 3,
      title: 'Example Episode $id',
      airDateUtc: DateTime.utc(2026, 5, day, 20),
      hasFile: file,
      finaleType: finale,
      monitored: true,
      series: fakeSeries(id),
    );

class _MonthView extends CalendarViewNotifier {
  @override
  CalendarView build() => CalendarView(
    mode: CalendarMode.month,
    anchor: DateTime(2026, 5),
    includeUnmonitored: false,
    selectedDay: DateTime(2026, 5, 3),
  );
}

void main() {
  const dark = HarnessVariant(
    size: Size(360, 800),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.dark,
  );
  const arLight = HarnessVariant(
    size: Size(360, 800),
    textScale: 1,
    locale: Locale('ar'),
    brightness: Brightness.light,
  );

  final calendar = ScriptedSonarrApi()
    ..calendarResult = Result.ok([
      _ep(1, 1),
      _ep(2, 3, file: true),
      _ep(3, 3, finale: 'season'),
      _ep(4, 6),
    ]);

  testWidgets('golden: calendar list (en, dark)', (tester) async {
    applyVariantView(tester, dark);
    await tester.pumpWidget(
      tabApp(
        dark,
        api: calendar,
        body: (context, padding) => calendarTab.body(context, padding),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_calendar_list_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: calendar month (ar, light, RTL)', (tester) async {
    applyVariantView(tester, arLight);
    await tester.pumpWidget(
      tabApp(
        arLight,
        api: calendar,
        extra: [calendarViewProvider.overrideWith(_MonthView.new)],
        body: (context, padding) => calendarTab.body(context, padding),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_calendar_month_ar_light_360x800.png'),
    );
  });

  testWidgets('golden: missing list expanded (en, dark)', (tester) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(
        ArrPage(
          records: [_ep(1, 1), _ep(2, 3), _ep(3, 4)],
          pageSize: 50,
          totalRecords: 3,
        ),
      );
    applyVariantView(tester, dark);
    await tester.pumpWidget(
      tabApp(
        dark,
        api: api,
        body: (context, padding) => WantedBody(
          padding: padding,
          onManualSearch: (context, episode, title) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Show 1'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_wanted_en_dark_360x800.png'),
    );
  });
}
