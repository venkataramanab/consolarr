// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:design_system/design_system.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/accessibility_screen.dart';
import 'package:consolarr/features/settings/presentation/connection_check_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_preview_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_screen.dart';
import 'package:consolarr/features/settings/presentation/language_screen.dart';
import 'package:consolarr/features/settings/presentation/lock_settings_screen.dart';
import 'package:consolarr/features/settings/presentation/privacy_screen.dart';
import 'package:consolarr/features/settings/presentation/settings_screen.dart';
import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';
import '../support/fake_hex.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A very tall phone, so nothing of a long list is off screen.
const _tall = HarnessVariant(
  size: Size(360, 2600),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  ScreenHarness h,
  Widget home, {
  HarnessVariant v = wide,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(h.screen(v, home));
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('hub', () {
    testWidgets('lists every group and no Notifications row', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness();
      applyVariantView(tester, _tall);
      await tester.pumpWidget(h.routed(_tall));
      await tester.pumpAndSettle();
      for (final text in [
        l10n.settingsSectionServers,
        l10n.settingsSectionDisplay,
        l10n.settingsSectionSecurity,
        l10n.settingsSectionPrivacy,
        l10n.settingsSectionLanguage,
        l10n.settingsSectionAccessibility,
        l10n.settingsSectionDiagnostics,
        l10n.settingsSectionAbout,
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.textContaining('Notification'), findsNothing);
    });

    testWidgets('rows open their child routes inside the shell', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness();
      applyVariantView(tester, wide);
      await tester.pumpWidget(h.routed(wide));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsPrivacyRow).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.privacyIntro), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsPrivacyRow), findsWidgets);
    });

    testWidgets('theme choice applies and persists', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const Scaffold(body: SettingsScreen()));
      expect(c.read(themeModeProvider), ThemeMode.dark);
      await tester.tap(find.text(l10n.settingsThemeTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsThemeLight));
      await tester.pumpAndSettle();
      expect(c.read(themeModeProvider), ThemeMode.light);
      expect(h.base.store.values[SettingsKeys.theme], 'light');
    });

    testWidgets('block screenshots is fixed on while the lock is on', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(stored: lockOn());
      await _pump(tester, h, const Scaffold(body: SettingsScreen()), v: _tall);
      final row = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text(l10n.settingsBlockScreenshotsTitle),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(row, isNotNull);
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) =>
            ScreenHarness().screen(v, const Scaffold(body: SettingsScreen())),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('app lock settings', () {
    testWidgets(
      'off, device has a secure lock: switch usable, delay disabled',
      (tester) async {
        final l10n = await _en();
        final h = ScreenHarness();
        await _pump(tester, h, const LockSettingsScreen());
        expect(find.text(l10n.lockSwitchTitle), findsOneWidget);
        expect(find.text(l10n.lockNoSecureLock), findsNothing);
        await tester.tap(find.text(l10n.lockSwitchTitle));
        await tester.pumpAndSettle();
        expect(h.base.store.values[SettingsKeys.lockEnabled], '1');
        expect(h.base.auth.reasons, [l10n.lockReasonEnable]);
      },
    );

    testWidgets('no secure lock method: explained and cannot be turned on', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(
        auth: FakeDeviceAuthenticator(
          supportResult: DeviceAuthSupport.noSecureLock,
        ),
      );
      await _pump(tester, h, const LockSettingsScreen());
      expect(find.text(l10n.lockNoSecureLock), findsOneWidget);
      await tester.tap(find.text(l10n.lockSwitchTitle), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.base.store.values[SettingsKeys.lockEnabled], isNull);
      expect(h.base.auth.reasons, isEmpty);
    });

    testWidgets('an unconfirmed enable keeps the lock off and says so', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
      );
      await _pump(tester, h, const LockSettingsScreen());
      await tester.tap(find.text(l10n.lockSwitchTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockEnableNotConfirmed), findsOneWidget);
      expect(h.base.store.values[SettingsKeys.lockEnabled], isNull);
    });

    testWidgets('on: the delay choices are offered', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness(stored: lockOn(LockDelay.fiveMinutes));
      await _pump(tester, h, const LockSettingsScreen());
      expect(find.text(l10n.lockDelayMinutes(5)), findsOneWidget);
      await tester.tap(find.text(l10n.lockDelayTitle));
      await tester.pumpAndSettle();
      for (final t in [
        l10n.lockDelayImmediately,
        l10n.lockDelayMinutes(1),
        l10n.lockDelayMinutes(15),
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text(l10n.lockDelayMinutes(15)));
      await tester.pumpAndSettle();
      expect(h.base.store.values[SettingsKeys.lockDelay], 'fifteenMinutes');
    });

    testWidgets('loading shows a skeleton, not a stale value', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness(supportPending: true);
      applyVariantView(tester, wide);
      await tester.pumpWidget(h.screen(wide, const LockSettingsScreen()));
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.lockSwitchTitle), findsNothing);
      expect(find.byType(SkeletonBox), findsWidgets);
    });

    testWidgets('accessible across the stress variants (off and on)', (
      tester,
    ) async {
      for (final stored in [null, lockOn()]) {
        await pumpMatrix(
          tester,
          (v) =>
              ScreenHarness(stored: stored)
                  .screen(v, const LockSettingsScreen()),
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      }
    });
  });

  group('privacy and consent', () {
    testWidgets('both switches off by default, explanation and payload shown', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const PrivacyScreen());
      expect(c.read(consentProvider), ConsentState.none);
      expect(find.text(l10n.privacyCrashWhat), findsOneWidget);
      expect(find.text(l10n.privacyAnalyticsWhat), findsOneWidget);
      expect(find.text(l10n.privacyEventScreenViewed), findsOneWidget);
      expect(find.text(l10n.privacyNoServiceNote), findsNothing);
    });

    testWidgets('toggling updates consent, persists and is withdrawn on off', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const PrivacyScreen());
      await tester.tap(find.text(l10n.privacyAnalyticsTitle).last);
      await tester.pumpAndSettle();
      expect(c.read(consentProvider).analytics, isTrue);
      expect(c.read(consentProvider).crashReports, isFalse);
      await tester.tap(find.text(l10n.privacyAnalyticsTitle).last);
      await tester.pumpAndSettle();
      expect(c.read(consentProvider).analytics, isFalse);
      expect(h.base.store.values[SettingsKeys.consentAnalytics], '0');
    });

    testWidgets('the build without a service says nothing is sent', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness(recordingSinks: false);
      await _pump(tester, h, const PrivacyScreen(), v: _tall);
      expect(find.text(l10n.privacyNoServiceNote), findsOneWidget);
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const PrivacyScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('language', () {
    testWidgets('endonyms, follow system, mirrors for Arabic', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const LanguageScreen());
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text(l10n.languageFollowSystem), findsOneWidget);
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(c.read(localeProvider), const Locale('ar'));
      expect(h.base.store.values[SettingsKeys.locale], 'ar');
      await tester.tap(find.text(l10n.languageFollowSystem));
      await tester.pumpAndSettle();
      expect(c.read(localeProvider), isNull);
    });

    testWidgets('each endonym is spoken in its own language', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, ScreenHarness(), const LanguageScreen());
      final locales = <String, Locale?>{};
      void visit(SemanticsNode n) {
        final d = n.getSemanticsData();
        if (d.label == 'العربية' || d.label == 'English') {
          locales[d.label] = d.locale;
        }
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      expect(locales['العربية'], const Locale('ar'));
      expect(locales['English'], const Locale('en'));
      handle.dispose();
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const LanguageScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('accessibility', () {
    testWidgets('the three options toggle and persist', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const AccessibilityScreen());
      await tester.tap(find.text(l10n.a11yMotionTitle));
      await tester.tap(find.text(l10n.a11yTargetsTitle));
      await tester.tap(find.text(l10n.a11yContrastTitle));
      await tester.pumpAndSettle();
      final s = c.read(settingsProvider);
      expect(s.motion.name, 'reduced');
      expect(s.largerTargets, isTrue);
      expect(s.highContrast, isTrue);
      expect(h.base.store.values[SettingsKeys.motion], 'reduced');
      expect(find.text(l10n.a11yFollowsSystem), findsOneWidget);
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const AccessibilityScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('diagnostics log', () {
    testWidgets('off, empty, capturing and filter-empty states', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness();
      final c = await _pump(tester, h, const DiagnosticsScreen());
      expect(find.text(l10n.diagOffTitle), findsOneWidget);

      await tester.tap(find.text(l10n.diagLogSwitch));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagEmptyTitle), findsOneWidget);

      final log = c.read(diagnosticsLogProvider);
      log.add(LogLevel.error, 'first problem');
      log.add(LogLevel.info, 'second note');
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagCapturing(2)), findsOneWidget);
      expect(find.textContaining('first problem'), findsOneWidget);
      expect(find.textContaining('second note'), findsOneWidget);
      expect(find.text(l10n.diagRedactionNotice), findsOneWidget);

      // Filter by level.
      await tester.tap(find.text(l10n.diagFilterLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagLevelWarning).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagFilterEmptyTitle), findsOneWidget);
      await tester.tap(find.text(l10n.diagFilterLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagLevelError).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('first problem'), findsOneWidget);
      expect(find.textContaining('second note'), findsNothing);
    });

    testWidgets('clear asks first, then empties', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness(stored: {SettingsKeys.diagnosticsEnabled: '1'});
      final c = await _pump(tester, h, const DiagnosticsScreen());
      c.read(diagnosticsLogProvider).add(LogLevel.error, 'kept for now');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagClear));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagClearConfirmBody), findsOneWidget);
      await tester.tap(find.text(l10n.settingsCancel));
      await tester.pumpAndSettle();
      expect(c.read(diagnosticsLogProvider).entries, hasLength(1));
      await tester.tap(find.text(l10n.diagClear));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagClearConfirm));
      await tester.pumpAndSettle();
      expect(c.read(diagnosticsLogProvider).entries, isEmpty);
      expect(find.text(l10n.diagEmptyTitle), findsOneWidget);
    });

    testWidgets('10,000 entries stay lazy and responsive', (tester) async {
      final h = ScreenHarness(stored: {SettingsKeys.diagnosticsEnabled: '1'});
      final c = await _pump(tester, h, const DiagnosticsScreen());
      final log = c.read(diagnosticsLogProvider);
      // The ring buffer caps the log; the list builds only what is visible.
      for (var i = 0; i < 10000; i++) {
        log.add(LogLevel.info, 'entry $i');
      }
      expect(log.entries.length, lessThanOrEqualTo(log.capacity));
      await tester.pumpAndSettle();
      expect(find.textContaining('entry '), findsAtLeastNWidgets(1));
      expect(
        find.textContaining('entry ').evaluate().length,
        lessThan(60),
        reason: 'only the visible rows are built',
      );
    });

    testWidgets('accessible across the stress variants (off and capturing)', (
      tester,
    ) async {
      for (final stored in [
        null,
        {SettingsKeys.diagnosticsEnabled: '1'},
      ]) {
        await pumpMatrix(
          tester,
          (v) =>
              ScreenHarness(stored: stored)
                  .screen(v, const DiagnosticsScreen()),
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      }
    });
  });

  group('diagnostics preview and sharing', () {
    Future<(ScreenHarness, ProviderContainer)> open(
      WidgetTester tester, {
      List<String> lines = const [],
    }) async {
      final h = ScreenHarness(
        stored: {SettingsKeys.diagnosticsEnabled: '1'},
        servers: [entry('a', name: 'Fake Server Name')],
      );
      final c = await _pump(tester, h, const DiagnosticsPreviewScreen());
      for (final l in lines) {
        c.read(diagnosticsLogProvider).add(LogLevel.error, l);
      }
      c.invalidate(diagnosticsBundleProvider);
      await tester.pumpAndSettle();
      return (h, c);
    }

    testWidgets('shows every section before anything can be shared', (
      tester,
    ) async {
      final l10n = await _en();
      final (h, _) = await open(tester);
      expect(find.text(l10n.diagPreviewIntro), findsOneWidget);
      for (final title in [
        'App',
        'Platform',
        'Locale',
        'Error categories',
        'Log',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.textContaining('Android API 34'), findsOneWidget);
      expect(h.base.actions.shared, isEmpty);
      expect(h.base.actions.opened, isEmpty);
    });

    testWidgets('canary scrub: nothing sensitive in the preview, the shared '
        'file or the issue address', (tester) async {
      final l10n = await _en();
      final (h, c) = await open(
        tester,
        lines: [
          'GET https://admin:hunter2@nas.private.example:8989/api?apikey=abcd1234canarytoken',
          'server Fake Server Name at sonarr.example failed',
          'connect 192.0.2.77 refused',
          'loading "Fake Show Title S01E01" failed',
          'magnet:?xt=urn:btih:${fakeHex(40)}&dn=Fake',
          '/storage/emulated/0/Download/Fake Movie 2020.mkv',
        ],
      );
      const canaries = [
        'hunter2',
        'nas.private.example',
        'abcd1234canarytoken',
        'Fake Server Name',
        'sonarr.example',
        '192.0.2.77',
        'Fake Show Title',
        'magnet:?xt',
        'Fake Movie',
        '/storage/emulated',
      ];
      final preview = c.read(diagnosticsBundleProvider).requireValue.text;
      for (final canary in canaries) {
        expect(preview, isNot(contains(canary)), reason: canary);
      }

      await tester.scrollUntilVisible(
        find.text(l10n.diagShareFile),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.diagShareFile));
      await tester.pumpAndSettle();
      final shared = h.base.actions.shared.single;
      expect(shared, preview, reason: 'preview equals the shared bytes');
      for (final canary in canaries) {
        expect(shared, isNot(contains(canary)), reason: canary);
      }

      await tester.tap(find.text(l10n.diagOpenGithub));
      await tester.pumpAndSettle();
      final url = h.base.actions.opened.single;
      expect(url.scheme, 'https');
      expect(url.host, 'github.com');
      expect(
        url.toString().length,
        lessThanOrEqualTo(GithubIssueLink.maxUrlLength),
      );
      for (final canary in canaries) {
        expect(Uri.decodeFull(url.toString()), isNot(contains(canary)));
      }
    });

    testWidgets('the address carries a short summary and a note to attach '
        'the file, never the log', (tester) async {
      final l10n = await _en();
      final lines = [
        for (var i = 0; i < 400; i++) 'line $i of a long running problem',
      ];
      final (h, c) = await open(tester, lines: lines);
      await tester.scrollUntilVisible(
        find.text(l10n.diagOpenGithub),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.diagOpenGithub));
      await tester.pumpAndSettle();
      final url = h.base.actions.opened.single;
      expect(url.scheme, 'https');
      expect(url.host, 'github.com');
      expect(
        url.toString().length,
        lessThanOrEqualTo(GithubIssueLink.maxUrlLength),
      );
      final body = url.queryParameters['body']!;
      expect(body, contains(l10n.diagAttachNote));
      expect(body, contains('Android API 34'));
      expect(body, isNot(contains('line 399')));
      expect(body, isNot(contains('long running problem')));
      expect(body.length, lessThan(1000));
      // The shared file is complete.
      await tester.tap(find.text(l10n.diagShareFile));
      await tester.pumpAndSettle();
      expect(
        h.base.actions.shared.single,
        c.read(diagnosticsBundleProvider).requireValue.text,
      );
    });

    testWidgets('a browser that cannot open is reported', (tester) async {
      final l10n = await _en();
      final (h, _) = await open(tester);
      h.base.actions.openResult = false;
      await tester.scrollUntilVisible(
        find.text(l10n.diagOpenGithub),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.diagOpenGithub));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagOpenFailed), findsOneWidget);
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const DiagnosticsPreviewScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('connection check screen', () {
    testWidgets('no servers: guidance', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness();
      await _pump(tester, h, const ConnectionCheckScreen());
      expect(find.text(l10n.checkNoServers), findsOneWidget);
    });

    testWidgets('choose a server, run, every step passes', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness(servers: [entry('a', name: 'Example A')]);
      h.ui.tester.outcomes
        ..clear()
        ..add(const ConnectionTestSuccess(version: '4.0.9', majorVersion: 4));
      await _pump(tester, h, const ConnectionCheckScreen());
      await tester.tap(find.text(l10n.checkChooseServer).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.checkRun));
      await tester.pumpAndSettle();
      expect(find.text(l10n.checkAllPassed), findsOneWidget);
      expect(find.text(l10n.checkServerVersion('4.0.9')), findsOneWidget);
      expect(find.text(l10n.checkStatePass), findsNWidgets(5));
    });

    testWidgets('a failing step names the cause and the fix', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness(servers: [entry('a', name: 'Example A')]);
      h.ui.tester.outcomes
        ..clear()
        ..add(const ConnectionTestFailure(AppError(ErrorCategory.authFailed)));
      await _pump(tester, h, const ConnectionCheckScreen());
      await tester.tap(find.text(l10n.checkChooseServer).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.checkRun));
      await tester.pumpAndSettle();
      expect(find.text(l10n.checkStateFail), findsOneWidget);
      // The default test server is a Sonarr: only its API key works.
      expect(
        find.text(l10n.connErrorArrAuthFailedMessage(l10n.serverKindSonarr)),
        findsOneWidget,
      );
      expect(
        find.text(l10n.connErrorArrAuthFailedHint(l10n.serverKindSonarr)),
        findsOneWidget,
      );
      expect(find.text(l10n.checkStateSkipped), findsOneWidget);
      expect(
        find.text(l10n.checkSummaryFailed(l10n.checkStepAuth)),
        findsOneWidget,
      );
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) =>
            ScreenHarness(servers: [entry('a', name: 'Example A')])
                .screen(v, const ConnectionCheckScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('about', () {
    testWidgets('version, licences, source link and privacy statement', (
      tester,
    ) async {
      final l10n = await _en();
      final h = ScreenHarness();
      await _pump(tester, h, const AboutScreen());
      expect(find.text(l10n.aboutVersionValue('0.1.1', '2')), findsOneWidget);
      expect(find.text(l10n.aboutLicensesRow), findsOneWidget);
      expect(find.text(l10n.aboutPrivacyBody), findsOneWidget);
      await tester.tap(find.text(l10n.aboutSourceRow));
      await tester.pumpAndSettle();
      expect(h.base.actions.opened.single.toString(), startsWith('https://'));
    });

    testWidgets('the licences page opens', (tester) async {
      final l10n = await _en();
      final h = ScreenHarness();
      await _pump(tester, h, const AboutScreen());
      await tester.tap(find.text(l10n.aboutLicensesRow));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('accessible across the stress variants', (tester) async {
      await pumpMatrix(
        tester,
        (v) => ScreenHarness().screen(v, const AboutScreen()),
        variants: stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });
}
