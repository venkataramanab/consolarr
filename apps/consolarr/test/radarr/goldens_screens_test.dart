// SPDX-License-Identifier: GPL-3.0-or-later

// Goldens for the sheets and tabs not covered by goldens_test.dart, plus the
// stress variant (ar, text scale 2.0, 320 wide). Regenerate with
// `flutter test --update-goldens test/radarr/goldens_screens_test.dart`.

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/features/radarr/presentation/edit_sheet.dart';
import 'package:consolarr/features/radarr/presentation/missing_page.dart';
import 'package:consolarr/features/radarr/presentation/queue_page.dart';
import 'package:consolarr/features/radarr/presentation/release_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

const _pad = EdgeInsets.fromLTRB(16, 16, 16, 88);

HarnessVariant _v(String lang, Brightness b) => HarnessVariant(
  size: const Size(360, 800),
  textScale: 1,
  locale: Locale(lang),
  brightness: b,
);

final _stressVariant = HarnessVariant(
  size: const Size(320, 568),
  textScale: 2,
  locale: const Locale('ar'),
  brightness: Brightness.light,
);

FakeRadarrApi _api() {
  return FakeRadarrApi(
      moviesResult: Result.ok([
        fakeMovie(7, title: 'Example Movie With A Rather Long Title'),
        fakeMovie(8, hasFile: false, digital: DateTime.utc(2026, 4)),
        fakeMovie(9, hasFile: false, inCinemas: DateTime.utc(2027)),
      ]),
    )
    ..calendarResult = Result.ok([
      fakeMovie(8, digital: DateTime.utc(2026, 5, 3), hasFile: false),
      fakeMovie(9, inCinemas: DateTime.utc(2026, 5, 20), hasFile: false),
    ])
    ..rootFoldersResult = const [ArrRootFolder(id: 1, path: '/movies')]
    ..queueResult = Result.ok([
      fakeQueueItem(1, movieId: 7, state: ArrQueueState.downloading),
    ])
    ..releasesResult = Result.ok([
      fakeRelease('a'),
      fakeRelease(
        'b',
        title: 'Example.Movie.2024.720p.CAM',
        approved: false,
        rejections: ['Quality is not wanted'],
      ),
    ]);
}

Widget _opener(void Function(BuildContext context) open) => Consumer(
  builder: (context, ref, _) {
    ref.watch(movieDetailProvider(7));
    return Center(
      child: FilledButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    );
  },
);

Future<void> _golden(
  WidgetTester tester,
  HarnessVariant v,
  Widget child,
  String file, {
  Future<void> Function()? after,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(radarrApp(v, _api(), child));
  await tester.pumpAndSettle();
  if (after != null) {
    await after();
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file'),
  );
}

void main() {
  final en = _v('en', Brightness.dark);

  Future<void> tapOpen(WidgetTester tester) => tester.tap(find.text('open'));

  testWidgets('golden: edit sheet', (tester) async {
    await _golden(
      tester,
      en,
      _opener((c) => showEditSheet(c, fakeMovie(7))),
      'radarr_edit_sheet_en_dark_360x800.png',
      after: () => tapOpen(tester),
    );
  });

  testWidgets('golden: release sheet', (tester) async {
    await _golden(
      tester,
      en,
      const ReleaseSheetBody(movieId: 7),
      'radarr_release_sheet_en_dark_360x800.png',
    );
  });

  testWidgets('golden: add flow', (tester) async {
    await _golden(
      tester,
      en,
      const AddMovieScreen(),
      'radarr_add_en_dark_360x800.png',
    );
  });

  testWidgets('golden: calendar', (tester) async {
    await _golden(
      tester,
      en,
      const CalendarPage(padding: _pad),
      'radarr_calendar_en_dark_360x800.png',
    );
  });

  testWidgets('golden: missing tab', (tester) async {
    await _golden(
      tester,
      en,
      const MissingPage(padding: _pad),
      'radarr_missing_en_dark_360x800.png',
    );
  });

  testWidgets('golden: removal dialog', (tester) async {
    await _golden(
      tester,
      en,
      const QueuePage(padding: _pad, active: false),
      'radarr_removal_dialog_en_dark_360x800.png',
      after: () => tester.tap(find.byIcon(Icons.delete_outline).first),
    );
  });

  testWidgets('golden: stress, ar x 2.0 x 320 (queue)', (tester) async {
    await _golden(
      tester,
      _stressVariant,
      const QueuePage(padding: _pad, active: false),
      'radarr_queue_ar_light_320x568_x2.png',
    );
  });

  testWidgets('golden: stress, ar x 2.0 x 320 (calendar)', (tester) async {
    await _golden(
      tester,
      _stressVariant,
      const CalendarPage(padding: _pad),
      'radarr_calendar_ar_light_320x568_x2.png',
    );
  });
}
