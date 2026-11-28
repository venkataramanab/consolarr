// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/connection_check.dart';
import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/connection_check_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_preview_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_screen.dart';
import 'package:consolarr/features/settings/presentation/lock_settings_screen.dart';
import 'package:consolarr/features/settings/presentation/privacy_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

class _ThrowingTester extends FakeTester {
  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials creds,
  ) async => throw StateError('probe exploded');
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  ScreenHarness h,
  Widget home, {
  HarnessVariant v = wide,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: harnessApp(
        v,
        ConsolarrEffectsScope(reduceMotion: true, child: home),
      ),
    ),
  );
  final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  group('diagnostics preview states', () {
    testWidgets('loading shows a skeleton and no bundle', (tester) async {
      final l10n = await _en();
      final never = StreamController<List<ServerEntry>>();
      addTearDown(never.close);
      final h = ScreenHarness(
        stored: {SettingsKeys.diagnosticsEnabled: '1'},
        servers: [entry('a', name: 'Fake Server Name')],
        serversStream: () => never.stream,
      );
      applyVariantView(tester, wide);
      await tester.pumpWidget(h.screen(wide, const DiagnosticsPreviewScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text(l10n.diagPreviewIntro), findsNothing);
      expect(find.text(l10n.diagShareFile), findsNothing);
    });

    testWidgets('an unreadable server list fails the bundle: error state with '
        'distinct headline, message, hint and retry; nothing unscrubbed', (
      tester,
    ) async {
      final l10n = await _en();
      var failing = true;
      final h = ScreenHarness(
        stored: {SettingsKeys.diagnosticsEnabled: '1'},
        serversStream: () => failing
            ? Stream<List<ServerEntry>>.error(StateError('db'))
            : Stream.value([entry('a', name: 'Fake Server Name')]),
      );
      final c = await _pump(tester, h, const DiagnosticsPreviewScreen());
      expect(find.text(l10n.diagLoadFailedTitle), findsOneWidget);
      expect(find.text(l10n.diagLoadFailed), findsOneWidget);
      expect(find.text(l10n.diagLoadFailedHint), findsOneWidget);
      expect(find.text(l10n.settingsRetry), findsOneWidget);
      expect(find.text(l10n.diagPreviewTitle), findsOneWidget); // app bar only
      final texts = {
        l10n.diagLoadFailedTitle,
        l10n.diagLoadFailed,
        l10n.diagLoadFailedHint,
        l10n.settingsRetry,
      };
      expect(texts, hasLength(4), reason: 'four different strings');
      expect(find.text(l10n.diagShareFile), findsNothing);
      expect(find.text(l10n.diagOpenGithub), findsNothing);

      failing = false;
      c.invalidate(serversProvider);
      await tester.tap(find.text(l10n.settingsRetry));
      await tester.pumpAndSettle();
      // The services control above pushes the buttons below the first screen.
      expect(
        find.text(l10n.diagShareFile, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('the bundle waits for the server list, so known names are '
        'scrubbed', (tester) async {
      final late = Completer<List<ServerEntry>>();
      final h = ScreenHarness(
        stored: {SettingsKeys.diagnosticsEnabled: '1'},
        servers: [entry('a', name: 'Quiet Cabin Server')],
        serversStream: () async* {
          yield await late.future;
        },
      );
      final c = await _pump(tester, h, const SizedBox());
      c.read(diagnosticsLogProvider).add(LogLevel.error, 'Quiet Cabin Server');
      final sub = c.listen(diagnosticsBundleProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.pump(const Duration(milliseconds: 20));
      expect(c.read(diagnosticsBundleProvider).isLoading, isTrue);
      late.complete([entry('a', name: 'Quiet Cabin Server')]);
      await tester.pumpAndSettle();
      final text = c.read(diagnosticsBundleProvider).requireValue.text;
      expect(text, isNot(contains('Quiet Cabin Server')));
    });

    testWidgets('accessible error and loading states', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness(
          stored: {SettingsKeys.diagnosticsEnabled: '1'},
          serversStream: () =>
              Stream<List<ServerEntry>>.error(StateError('db')),
        ).screen(v, const DiagnosticsPreviewScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('connection check states', () {
    testWidgets('mid-run: steps are pending/running and the button is off', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(servers: [entry('a', name: 'Example A')]);
      h.ui.tester.gate = Completer<void>();
      await _pump(tester, h, const ConnectionCheckScreen());
      await tester.tap(find.text(l10n.checkRun));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(l10n.checkRun),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text(l10n.checkAllPassed), findsNothing);
      h.ui.tester.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text(l10n.checkAllPassed), findsOneWidget);
    });

    testWidgets('an unexpected error ends the run with a message, not '
        '"running" forever', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness(
        servers: [entry('a', name: 'Example A')],
        healthTester: _ThrowingTester(),
      );
      final c = await _pump(tester, h, const ConnectionCheckScreen());
      await tester.tap(find.text(l10n.checkRun));
      await tester.pumpAndSettle();
      expect(c.read(connectionCheckProvider).running, isFalse);
      expect(c.read(connectionCheckProvider).failed, isTrue);
      expect(find.text(l10n.checkRunFailed), findsOneWidget);
      // It can be run again.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('an unreadable server list: distinct error strings', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(
        uiServers: AsyncError<List<ServerEntry>>(
          StateError('x'),
          StackTrace.empty,
        ),
      );
      await _pump(tester, h, const ConnectionCheckScreen());
      for (final t in [
        l10n.checkLoadFailedTitle,
        l10n.checkLoadFailed,
        l10n.checkLoadFailedHint,
        l10n.settingsRetry,
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('no servers is accessible across the stress variants', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const ConnectionCheckScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('privacy with consent on', () {
    testWidgets('both switches on show their state and are accessible', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(
        stored: {
          SettingsKeys.consentCrashReports: '1',
          SettingsKeys.consentAnalytics: '1',
        },
      );
      final c = await _pump(tester, h, const PrivacyScreen());
      expect(c.read(consentProvider).crashReports, isTrue);
      expect(c.read(consentProvider).analytics, isTrue);
      expect(find.text(l10n.privacyAnalyticsTitle), findsWidgets);
      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect(switches.where((s) => s.value), hasLength(2));
    });

    testWidgets('accessible with consent on across the stress variants', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness(
          stored: {
            SettingsKeys.consentCrashReports: '1',
            SettingsKeys.consentAnalytics: '1',
          },
        ).screen(v, const PrivacyScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('lock settings off', () {
    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const LockSettingsScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('diagnostics announcements', () {
    testWidgets('the running count is not a live region; on, off and cleared '
        'are announced once each', (tester) async {
      final l10n = await _en();
      final said = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final m = message as Map;
            if (m['type'] == 'announce') {
              said.add((m['data'] as Map)['message'] as String);
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      final handle = tester.ensureSemantics();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const DiagnosticsScreen());
      await tester.tap(find.text(l10n.diagLogSwitch));
      await tester.pumpAndSettle();
      expect(said, [l10n.diagAnnounceOn]);

      final log = c.read(diagnosticsLogProvider);
      for (var i = 0; i < 5; i++) {
        log.add(LogLevel.error, 'line $i');
        await tester.pump();
      }
      expect(said, [l10n.diagAnnounceOn], reason: 'new lines say nothing');
      final node = tester.getSemantics(find.text(l10n.diagCapturing(5)));
      var live = false;
      void check(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isLiveRegion) live = true;
      }

      check(node);
      node.visitChildren((n) {
        check(n);
        return true;
      });
      var up = node.parent;
      while (up != null) {
        check(up);
        up = up.parent;
      }
      expect(live, isFalse);

      await tester.tap(find.text(l10n.diagClear));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagClearConfirm));
      await tester.pumpAndSettle();
      expect(said.last, l10n.diagAnnounceCleared);

      await tester.tap(find.text(l10n.diagLogSwitch));
      await tester.pumpAndSettle();
      expect(said.last, l10n.diagAnnounceOff);
      expect(said, hasLength(3));
      handle.dispose();
    });
  });
}
