// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/edit_sheet.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

bool _en(HarnessVariant v) => v.locale == const Locale('en');

class _Api extends FakeRadarrApi {
  _Api({super.moviesResult})
    : super(
        profiles: const [
          ArrQualityProfile(id: 1, name: 'HD-1080p'),
          ArrQualityProfile(id: 2, name: 'Ultra-HD'),
        ],
      );

  bool tagsFail = false;

  @override
  Future<Result<List<ArrTag>>> tags() async => tagsFail
      ? const Result.err(AppError(ErrorCategory.timeout))
      : const Result.ok([
          ArrTag(id: 1, label: 'kids'),
          ArrTag(id: 2, label: 'hd'),
        ]);
}

RadarrMovie _movie({
  MinimumAvailability min = MinimumAvailability.released,
  List<int> tags = const [1],
}) => RadarrMovie(
  id: 7,
  title: 'Example Movie',
  sortTitle: 'example movie',
  year: 2024,
  monitored: true,
  qualityProfileId: 1,
  minimumAvailability: min,
  tags: tags,
);

Future<void> _open(
  WidgetTester tester,
  _Api api,
  RadarrMovie movie, {
  List<HarnessVariant>? variants,
  Future<void> Function(HarnessVariant)? verify,
}) => pumpMatrix(
  tester,
  (v) => radarrApp(
    v,
    api,
    Consumer(
      builder: (context, ref, _) {
        ref.watch(movieDetailProvider(7));
        return Center(
          child: FilledButton(
            onPressed: () => showEditSheet(context, movie),
            child: const Text('open'),
          ),
        );
      },
    ),
  ),
  variants: variants ?? phone,
  verify: verify == null
      ? null
      : (v) async {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await verify(v);
        },
);

Finder get _save => find.widgetWithText(FilledButton, 'Save');

void main() {
  group('edit sheet (RAD-09)', () {
    testWidgets('opens as a glass sheet and never offers the path', (
      tester,
    ) async {
      final api = _Api(moviesResult: Result.ok([_movie()]));
      await _open(tester, api, _movie());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.text('Edit movie'), findsOneWidget);
      expect(find.textContaining('Root folder'), findsNothing);
    });

    testWidgets('sends only the changed fields', (tester) async {
      final api = _Api(moviesResult: Result.ok([_movie()]));
      await _open(tester, api, _movie());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(
        api.calls.single,
        'update 7 monitored=false profile=null '
        'min=null tags=null',
      );
      expect(find.text('Edit movie'), findsNothing);
    });

    testWidgets('tags are sent as the full sorted set when they change', (
      tester,
    ) async {
      final api = _Api(moviesResult: Result.ok([_movie()]));
      await _open(tester, api, _movie());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'hd'));
      await tester.tap(find.widgetWithText(FilterChip, 'hd'));
      await tester.pump();
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(api.calls.single, contains('tags=[1, 2]'));
      expect(api.calls.single, contains('monitored=null'));
    });

    testWidgets('nothing changed: Save is off and nothing is sent', (
      tester,
    ) async {
      final api = _Api(moviesResult: Result.ok([_movie()]));
      await _open(tester, api, _movie());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_save);
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      await tester.tap(_save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      // Changing and changing back is "nothing changed" again.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    });

    testWidgets('an unknown availability is kept: not shown as released, not '
        'sent', (tester) async {
      final unknown = _movie(min: MinimumAvailability.unknown);
      final api = _Api(moviesResult: Result.ok([unknown]));
      await _open(tester, api, unknown);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final picker = tester
          .widget<DropdownButtonFormField<MinimumAvailability>>(
            find.byType(DropdownButtonFormField<MinimumAvailability>),
          );
      expect(picker.initialValue, isNull);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(api.calls.single, contains('min=null'));
    });

    testWidgets('tba is a real value: kept when unchanged, sendable when '
        'chosen', (tester) async {
      final tba = _movie(min: MinimumAvailability.tba);
      final api = _Api(moviesResult: Result.ok([tba]));
      await _open(tester, api, tba);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final picker = tester
          .widget<DropdownButtonFormField<MinimumAvailability>>(
            find.byType(DropdownButtonFormField<MinimumAvailability>),
          );
      expect(picker.initialValue, MinimumAvailability.tba);
      // Unchanged tba: nothing to save.
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    });

    testWidgets('choosing tba from another value sends tba', (tester) async {
      final released = _movie();
      final api2 = _Api(moviesResult: Result.ok([released]));
      await _open(tester, api2, released);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownButtonFormField<MinimumAvailability>),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is DropdownMenuItem<MinimumAvailability> &&
                  w.value == MinimumAvailability.tba,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(api2.calls.single, contains('min=tba'));
    });

    testWidgets('failing tags show an error with retry, not an empty list', (
      tester,
    ) async {
      final api = _Api(moviesResult: Result.ok([_movie()]))..tagsFail = true;
      await _open(tester, api, _movie());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the options"), findsOneWidget);
      expect(_save, findsNothing);
      api.tagsFail = false;
      await tester.tap(find.text('Try again').last);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the options"), findsNothing);
      expect(_save, findsOneWidget);
    });

    testWidgets('failure keeps the sheet and says why', (tester) async {
      final api = _Api(moviesResult: Result.ok([_movie()]))
        ..updateResult = const Result.err(AppError(ErrorCategory.serverError));
      await _open(
        tester,
        api,
        _movie(),
        variants: [...phone, ...stress],
        verify: (v) async {
          await tester.tap(find.byType(Switch));
          await tester.pump();
          await tester.ensureVisible(find.byType(FilledButton).last);
          await tester.tap(find.byType(FilledButton).last);
          await tester.pumpAndSettle();
          if (_en(v)) {
            expect(find.textContaining('Could not save'), findsOneWidget);
          }
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('the sheet is accessible at the stress sizes', (tester) async {
      final api = _Api(moviesResult: Result.ok([_movie()]));
      await _open(
        tester,
        api,
        _movie(),
        variants: [...phone, ...stress],
        verify: (v) => expectAccessible(tester),
      );
    });
  });
}
