// SPDX-License-Identifier: GPL-3.0-or-later

// The full harness matrix (3 sizes x 2 text scales x en / en_XA / ar x dark /
// light = 36 variants) with `expectAccessible` (tap targets, labels and text
// contrast, i.e. `meetsGuideline` for the three Android guidelines) once per
// screen state. The interaction tests elsewhere run on a smaller subset
// (`phone` and `stress` in harness.dart).

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/features/radarr/presentation/edit_sheet.dart';
import 'package:consolarr/features/radarr/presentation/missing_page.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:consolarr/features/radarr/presentation/queue_page.dart';
import 'package:consolarr/features/radarr/presentation/release_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

final _all = harnessMatrix();
const _pad = EdgeInsets.fromLTRB(16, 16, 16, 88);

FakeRadarrApi _api() {
  final movies = [
    fakeMovie(7, title: 'Example Movie With A Rather Long Title'),
    fakeMovie(8, hasFile: false, digital: DateTime.utc(2026, 4)),
    fakeMovie(9, hasFile: false, inCinemas: DateTime.utc(2027)),
  ];
  return FakeRadarrApi(moviesResult: Result.ok(movies))
    ..calendarResult = Result.ok([
      fakeMovie(8, digital: DateTime.utc(2026, 5, 3), hasFile: false),
      fakeMovie(9, inCinemas: DateTime.utc(2026, 5, 20), hasFile: false),
    ])
    ..rootFoldersResult = const [ArrRootFolder(id: 1, path: '/movies')]
    ..queueResult = Result.ok([
      fakeQueueItem(1, movieId: 7, state: ArrQueueState.downloading),
      fakeQueueItem(2, movieId: 8, state: ArrQueueState.importFailed),
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
    // Keep the detail provider alive, as the real screen does.
    ref.watch(movieDetailProvider(7));
    return Center(
      child: FilledButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    );
  },
);

void main() {
  testWidgets('matrix: movie detail', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const MovieDetailScreen(movieId: 7)),
      variants: _all,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('matrix: edit sheet', (tester) async {
    await pumpMatrix(
      tester,
      (v) =>
          radarrApp(v, _api(), _opener((c) => showEditSheet(c, fakeMovie(7)))),
      variants: _all,
      verify: (v) async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('matrix: queue and its removal dialog', (tester) async {
    await pumpMatrix(
      tester,
      (v) =>
          radarrApp(v, _api(), const QueuePage(padding: _pad, active: false)),
      variants: _all,
      verify: (v) async {
        await expectAccessible(tester);
        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('matrix: release sheet', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const ReleaseSheetBody(movieId: 7)),
      variants: _all,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('matrix: add flow', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const AddMovieScreen()),
      variants: _all,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('matrix: missing', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const MissingPage(padding: _pad)),
      variants: _all,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('matrix: calendar', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const CalendarPage(padding: _pad)),
      variants: _all,
      verify: (v) => expectAccessible(tester),
    );
  });
}
