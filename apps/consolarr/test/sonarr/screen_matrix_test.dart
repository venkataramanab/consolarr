// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/sonarr/application/calendar_providers.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_body.dart';
import 'package:consolarr/features/sonarr/presentation/detail/edit_series_sheet.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_body.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../arr_common/grid_accessibility.dart';
import 'detail_harness.dart';
import 'fakes.dart';
import 'release_harness.dart';
import 'support.dart';
import 'tab_harness.dart';

/// The full stress matrix (320x568 and 412x915, en / en_XA / ar, text scale
/// 1.0 and 2.0, dark: 12 variants) for every state of the screens below. A
/// fresh API per variant; any overflow or framework exception fails with the
/// variant's label, then labels, tap targets and contrast are checked.
Future<void> _everyVariant(
  WidgetTester tester, {
  required Widget Function(HarnessVariant v, ScriptedSonarrApi api) build,
  ScriptedSonarrApi Function()? api,
  Future<void> Function(WidgetTester tester, HarnessVariant v)? act,
  Future<void> Function(WidgetTester tester, HarnessVariant v)? check,
  // A running spinner never settles: pump a fixed time instead.
  bool settleAfterAct = true,
}) async {
  for (final v in tabStress) {
    final scripted = (api ?? ScriptedSonarrApi.new)();
    applyVariantView(tester, v);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      KeyedSubtree(key: ValueKey(v.label), child: build(v, scripted)),
    );
    await tester.pumpAndSettle();
    if (act != null) {
      await act(tester, v);
      if (settleAfterAct) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    expectNoFrameworkExceptions(tester, context: v.label);
    if (check != null) await check(tester, v);
    try {
      await expectAccessible(tester);
    } on TestFailure catch (e) {
      fail('${v.label}: ${e.message}');
    }
  }
}

AppLocalizations _l10nOf(HarnessVariant v) => lookupAppLocalizations(v.locale);

SonarrEpisode _missing(int id) => SonarrEpisode(
  id: id,
  seriesId: id,
  seasonNumber: 1,
  episodeNumber: id,
  title: 'Example Episode $id ${'Long ' * 6}',
  airDateUtc: DateTime.utc(2026, 4, 20, 12),
  monitored: true,
  series: fakeSeries(id, title: 'Example Show ${'Long ' * 6}$id'),
);

ScriptedSonarrApi _wantedApi() => ScriptedSonarrApi()
  ..wantedResult = Result.ok(
    ArrPage(records: [_missing(1), _missing(2)], pageSize: 50, totalRecords: 2),
  );

Widget _wanted(HarnessVariant v, ScriptedSonarrApi api) => tabApp(
  v,
  api: api,
  body: (context, padding) => WantedBody(
    padding: padding,
    onManualSearch: (context, episode, title) {},
  ),
);

Widget _calendar(HarnessVariant v, ScriptedSonarrApi api) => tabApp(
  v,
  api: api,
  body: (context, padding) => CalendarBody(padding: padding),
);

class _MonthView extends CalendarViewNotifier {
  @override
  CalendarView build() => CalendarView(
    mode: CalendarMode.month,
    anchor: DateTime(2026, 5, 1),
    includeUnmonitored: false,
    selectedDay: DateTime(2026, 5, 3),
  );
}

/// Opens the removal dialog around [onConfirm].
class _RemovalHost extends StatelessWidget {
  const _RemovalHost(this.onConfirm);

  final Future<AppError?> Function(ArrQueueRemovalChoice) onConfirm;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showArrQueueRemovalDialog(
          context: context,
          itemLabel: 'Example Show 1',
          serviceName: 'Sonarr',
          kind: ServiceKind.sonarr,
          onConfirm: onConfirm,
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _reveal(WidgetTester tester, Finder finder, {Finder? within}) =>
    tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: within ?? find.byType(Scaffold),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  group('queue removal dialog', () {
    testWidgets('consequences', (tester) async {
      await _everyVariant(
        tester,
        build: (v, _) => harnessApp(v, _RemovalHost((_) async => null)),
        act: (tester, v) async {
          await tester.tap(find.text('open'));
        },
      );
    });

    testWidgets('removing', (tester) async {
      final gates = <Completer<AppError?>>[];
      await _everyVariant(
        tester,
        build: (v, _) => harnessApp(
          v,
          _RemovalHost((_) {
            final gate = Completer<AppError?>();
            gates.add(gate);
            return gate.future;
          }),
        ),
        act: (tester, v) async {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          await tester.pump();
        },
        settleAfterAct: false,
      );
    });

    testWidgets('failure with retry', (tester) async {
      await _everyVariant(
        tester,
        build: (v, _) => harnessApp(
          v,
          _RemovalHost((_) async => const AppError(ErrorCategory.timeout)),
        ),
        act: (tester, v) async {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
        },
      );
    });
  });

  group('edit series sheet', () {
    Future<void> open(WidgetTester tester, HarnessVariant v) async {
      await tester.tap(find.byIcon(Icons.edit_outlined));
    }

    testWidgets('idle', (tester) async {
      await _everyVariant(
        tester,
        api: detailApi,
        build: (v, api) => detailApp(v, api: api),
        act: open,
      );
    });

    testWidgets('saving', (tester) async {
      await _everyVariant(
        tester,
        api: () {
          final gate = Completer<void>();
          return detailApi()
            ..updateResult = Result.ok(fakeDetail(1))
            ..hook = (n) => n == 'updateSeries' ? gate.future : Future.value();
        },
        build: (v, api) => detailApp(v, api: api),
        act: (tester, v) async {
          await open(tester, v);
          await tester.pumpAndSettle();
          final save = find.text(_l10nOf(v).sonarrDetailEditSave);
          await _reveal(tester, save, within: find.byType(EditSeriesForm));
          await tester.tap(save);
          await tester.pump();
        },
        settleAfterAct: false,
      );
    });

    testWidgets('save failed', (tester) async {
      await _everyVariant(
        tester,
        api: () => detailApi()
          ..updateResult = const Result.err(
            AppError(ErrorCategory.serverError),
          ),
        build: (v, api) => detailApp(v, api: api),
        act: (tester, v) async {
          await open(tester, v);
          await tester.pumpAndSettle();
          final save = find.text(_l10nOf(v).sonarrDetailEditSave);
          await _reveal(tester, save, within: find.byType(EditSeriesForm));
          await tester.tap(save);
        },
      );
    });

    testWidgets('profiles failed to load', (tester) async {
      await _everyVariant(
        tester,
        api: () => detailApi()
          ..profilesResult = const Result.err(AppError(ErrorCategory.timeout)),
        build: (v, api) => detailApp(v, api: api),
        act: open,
      );
    });
  });

  group('wanted', () {
    testWidgets('data, a group expanded', (tester) async {
      await _everyVariant(
        tester,
        api: _wantedApi,
        build: _wanted,
        act: (tester, v) async {
          await tester.tap(find.textContaining('Example Show').first);
        },
      );
    });

    testWidgets('error', (tester) async {
      await _everyVariant(
        tester,
        api: () => ScriptedSonarrApi()
          ..wantedResult = const Result.err(
            AppError(ErrorCategory.networkUnreachable),
          ),
        build: _wanted,
      );
    });

    testWidgets('search all: confirm dialog', (tester) async {
      await _everyVariant(
        tester,
        api: _wantedApi,
        build: _wanted,
        act: (tester, v) async {
          await tester.tap(find.text(_l10nOf(v).sonarrWantedSearchAll));
        },
      );
    });

    testWidgets('search all: found, nothing new, failed', (tester) async {
      for (final outcome in ['found', 'nothing', 'failed']) {
        await _everyVariant(
          tester,
          api: () {
            final api = _wantedApi();
            switch (outcome) {
              case 'found':
                api.queueSequence = [
                  const Result.ok([]),
                  Result.ok([fakeQueueItem(1)]),
                ];
              case 'failed':
                api.startResult = const Result.err(
                  AppError(ErrorCategory.serverError),
                );
              default:
            }
            return api;
          },
          build: _wanted,
          act: (tester, v) async {
            final l10n = _l10nOf(v);
            await tester.tap(find.text(l10n.sonarrWantedSearchAll));
            await tester.pumpAndSettle();
            await tester.tap(find.text(l10n.sonarrWantedSearchAllConfirm));
          },
          check: (tester, v) async {
            final l10n = _l10nOf(v);
            expect(
              find.text(switch (outcome) {
                'found' => l10n.sonarrWantedSearchAllDone,
                'nothing' => l10n.sonarrWantedSearchAllNothing,
                _ => l10n.sonarrWantedSearchAllFailed,
              }),
              findsOneWidget,
              reason: '$outcome ${v.label}',
            );
          },
        );
      }
    });
  });

  group('calendar', () {
    testWidgets('empty range', (tester) async {
      await _everyVariant(
        tester,
        build: _calendar,
        check: (tester, v) async => expect(
          find.text(_l10nOf(v).sonarrCalendarEmptyRangeHeadline),
          findsOneWidget,
        ),
      );
    });

    testWidgets('error', (tester) async {
      await _everyVariant(
        tester,
        api: () => ScriptedSonarrApi()
          ..calendarResult = const Result.err(
            AppError(ErrorCategory.authFailed),
          ),
        build: _calendar,
        check: (tester, v) async => expect(
          find.text(_l10nOf(v).sonarrCalendarErrorTitle),
          findsOneWidget,
        ),
      );
    });

    testWidgets('month view (grid, selected day)', (tester) async {
      for (final v in tabStress) {
        final api = ScriptedSonarrApi()
          ..calendarResult = Result.ok([
            SonarrEpisode(
              id: 1,
              seriesId: 1,
              seasonNumber: 1,
              episodeNumber: 1,
              title: 'Example Episode 1',
              airDateUtc: DateTime.utc(2026, 5, 3, 12),
              series: fakeSeries(1),
            ),
          ]);
        applyVariantView(tester, v);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          tabApp(
            v,
            api: api,
            extra: [calendarViewProvider.overrideWith(_MonthView.new)],
            body: (context, padding) => CalendarBody(padding: padding),
          ),
        );
        await tester.pumpAndSettle();
        expectNoFrameworkExceptions(tester, context: v.label);
        expect(find.byType(SingleChildScrollView), findsNothing);
        await expectGridAccessible(tester, v);
      }
    });
  });

  group('release sheet', () {
    ScriptedSonarrApi withReleases({List<String> rejections = const []}) =>
        ScriptedSonarrApi()
          ..releasesResult = Result.ok([
            fakeRelease(1, rejections: rejections),
            fakeRelease(2),
          ]);

    testWidgets('searching', (tester) async {
      await _everyVariant(
        tester,
        api: () {
          final gate = Completer<void>();
          return ScriptedSonarrApi()
            ..hook = (n) => n == 'releases' ? gate.future : Future.value();
        },
        build: releaseApp,
        act: (tester, v) async {},
      );
    });

    testWidgets('results', (tester) async {
      await _everyVariant(tester, api: withReleases, build: releaseApp);
    });

    testWidgets('filters that hide everything', (tester) async {
      await _everyVariant(
        tester,
        api: withReleases,
        build: releaseApp,
        act: (tester, v) async {
          final l10n = _l10nOf(v);
          await tester.tap(find.text(l10n.sonarrReleaseFilters(0)).first);
        },
      );
    });

    for (final state in ['grabbing', 'grabbed', 'failed', 'maybeSent']) {
      testWidgets('download $state', (tester) async {
        await _everyVariant(
          tester,
          api: () {
            final api = withReleases();
            switch (state) {
              case 'grabbing':
                final gate = Completer<void>();
                api.hook = (n) =>
                    n == 'grabRelease' ? gate.future : Future.value();
              case 'failed':
                api.grabResult = const Result.err(
                  AppError(ErrorCategory.serverError),
                );
              case 'maybeSent':
                api.grabResult = const Result.err(
                  AppError(ErrorCategory.timeout),
                );
              default:
            }
            return api;
          },
          build: releaseApp,
          act: (tester, v) async {
            final download = find.text(_l10nOf(v).sonarrReleaseDownload);
            await _reveal(tester, download.first);
            await tester.tap(download.first);
            await tester.pump();
          },
        );
      });
    }

    testWidgets('rejected release: confirm dialog', (tester) async {
      await _everyVariant(
        tester,
        api: () => withReleases(rejections: ['Not an upgrade']),
        build: releaseApp,
        act: (tester, v) async {
          final download = find.text(_l10nOf(v).sonarrReleaseDownload);
          await _reveal(tester, download.first);
          await tester.tap(download.first);
        },
      );
    });

    testWidgets('maybe sent: send again? dialog', (tester) async {
      await _everyVariant(
        tester,
        api: () =>
            withReleases()
              ..grabResult = const Result.err(AppError(ErrorCategory.timeout)),
        build: releaseApp,
        act: (tester, v) async {
          final l10n = _l10nOf(v);
          final download = find.text(l10n.sonarrReleaseDownload);
          await _reveal(tester, download.first);
          await tester.tap(download.first);
          await tester.pumpAndSettle();
          final again = find.text(l10n.sonarrReleaseDownloadAgain);
          await _reveal(tester, again.first);
          await tester.tap(again.first);
        },
        check: (tester, v) async => expect(
          find.text(_l10nOf(v).sonarrReleaseResendMessage),
          findsOneWidget,
        ),
      );
    });
  });
}
