// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart' show MethodChannel, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:security/security.dart';

import 'support.dart';

Widget _app(SettingsHarness h) => ProviderScope(
  overrides: [
    ...h.overrides,
    databaseProvider.overrideWith((ref) {
      final db = AppDatabase.memory();
      ref.onDispose(db.close);
      return db;
    }),
    secretStoreProvider.overrideWithValue(InMemorySecretStore()),
  ],
  child: const ConsolarrApp(),
);

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(seconds: 1));
}

bool _semanticsContain(WidgetTester tester, String text) {
  final root = tester
      .binding
      .renderViews
      .first
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  var found = false;
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (d.label.contains(text) || d.hint.contains(text)) found = true;
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(root);
  return found;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('cold start', () {
    testWidgets('the first frame is an opaque cover; no content is built '
        'while the lock state is unresolved', (tester) async {
      final l10n = await _en();
      final h = SettingsHarness(stored: lockOn());
      await tester.pumpWidget(_app(h));
      // The very first frame: nothing of the app, nothing to read.
      expect(find.text(l10n.homeTitle), findsNothing);
      expect(find.text(l10n.homeEmptyHeading), findsNothing);
      await _unmount(tester);
    });

    testWidgets('with the lock on, the app starts locked and prompts once', (
      tester,
    ) async {
      final l10n = await _en();
      final h = SettingsHarness(stored: lockOn());
      h.auth.hold = Completer<DeviceAuthResult>();
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockScreenTitle), findsOneWidget);
      expect(find.text(l10n.homeEmptyHeading), findsNothing);
      expect(h.auth.reasons, [l10n.lockReasonUnlock]);
      h.auth.hold!.complete(DeviceAuthResult.success);
      await tester.pumpAndSettle();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
      expect(find.text(l10n.lockScreenTitle), findsNothing);
      await _unmount(tester);
    });

    testWidgets('with the lock off, content shows once settings resolve', (
      tester,
    ) async {
      final l10n = await _en();
      final h = SettingsHarness();
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
      expect(h.auth.reasons, isEmpty);
      await _unmount(tester);
    });
  });

  group('covers the whole app', () {
    testWidgets('a dialog and a sheet opened before backgrounding are hidden '
        'while locked, and the semantics tree has no content', (tester) async {
      final l10n = await _en();
      final h = SettingsHarness(stored: lockOn());
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle(); // locked, auto prompt succeeds (default)
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);

      final context = tester.element(find.text(l10n.homeEmptyHeading));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('dialog-canary')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('dialog-canary'), findsOneWidget);
      Navigator.of(tester.element(find.text('dialog-canary'))).pop();
      await tester.pumpAndSettle();
      unawaited(
        showGlassSheet<void>(
          context: context,
          title: 'sheet-canary',
          closeLabel: 'Close',
          builder: (_) => const Text('sheet-body-canary'),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('sheet-body-canary')),
          builder: (_) => const AlertDialog(content: Text('dialog-canary')),
        ),
      );
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(_semanticsContain(tester, 'dialog-canary'), isTrue);

      // Background and return: with "immediately" the app locks.
      h.auth.hold = Completer<DeviceAuthResult>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      h.clock.advance(const Duration(seconds: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(l10n.lockScreenTitle), findsOneWidget);
      for (final canary in [
        'dialog-canary',
        'sheet-body-canary',
        'sheet-canary',
        l10n.homeEmptyHeading,
      ]) {
        expect(find.text(canary), findsNothing, reason: canary);
        expect(_semanticsContain(tester, canary), isFalse, reason: canary);
      }
      expect(find.text(l10n.lockScreenTitle), findsOneWidget);

      // Unlock: the same dialog and sheet are still there (state kept).
      h.auth.hold!.complete(DeviceAuthResult.success);
      await tester.pumpAndSettle();
      expect(find.text('dialog-canary'), findsOneWidget);
      expect(find.text('sheet-body-canary'), findsOneWidget);
      semantics.dispose();
      Navigator.of(tester.element(find.text('dialog-canary'))).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('sheet-body-canary'))).pop();
      await tester.pumpAndSettle();
      await _unmount(tester);
    });

    testWidgets('tickers of the hidden content are disabled', (tester) async {
      final h = SettingsHarness(stored: lockOn());
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      h.auth.hold = Completer<DeviceAuthResult>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final modes = tester.widgetList<TickerMode>(
        find.byType(TickerMode, skipOffstage: false),
      );
      expect(modes.any((m) => !m.enabled), isTrue);
      h.auth.hold!.complete(DeviceAuthResult.success);
      await tester.pumpAndSettle();
      await _unmount(tester);
    });
  });

  group('lifecycle cover', () {
    testWidgets('inactive and paused cover the content when the lock is on', (
      tester,
    ) async {
      final l10n = await _en();
      final h = SettingsHarness(stored: lockOn());
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(l10n.homeEmptyHeading), findsNothing);
      // Back without having been paused: uncovered and still unlocked.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text(l10n.homeEmptyHeading), findsNothing);
      // Leave the process resumed so the tree can be torn down cleanly.
      h.auth.hold = Completer<DeviceAuthResult>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      h.auth.hold!.complete(DeviceAuthResult.success);
      await tester.pumpAndSettle();
      await _unmount(tester);
    });

    testWidgets('no cover without the lock', (tester) async {
      final l10n = await _en();
      final h = SettingsHarness();
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _unmount(tester);
    });

    testWidgets('a delay that has not elapsed does not lock on return', (
      tester,
    ) async {
      final l10n = await _en();
      final h = SettingsHarness(stored: lockOn(LockDelay.fiveMinutes));
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      h.clock.advance(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
      expect(find.text(l10n.lockScreenTitle), findsNothing);
      await _unmount(tester);
    });
  });

  group('secure window', () {
    testWidgets('on while the lock is on; off when neither lock nor '
        'screenshot blocking is', (tester) async {
      final h = SettingsHarness(stored: lockOn());
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(h.secure.isSecure, isTrue);
      await _unmount(tester);

      final off = SettingsHarness();
      await tester.pumpWidget(_app(off));
      await tester.pumpAndSettle();
      expect(off.secure.calls, isEmpty);
      await _unmount(tester);
    });

    testWidgets('block screenshots uses the same seam', (tester) async {
      final h = SettingsHarness(stored: {SettingsKeys.blockScreenshots: '1'});
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(h.secure.isSecure, isTrue);
      await _unmount(tester);
    });

    testWidgets('a screen asking for secure:false cannot drop the lock\'s '
        'request, and the lock cannot drop a screen\'s', (tester) async {
      final h = SettingsHarness(stored: lockOn());
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(h.secure.isSecure, isTrue);
      final editor = Object();
      await h.secure.setSecure(secure: true, owner: editor);
      await h.secure.setSecure(secure: false, owner: editor);
      expect(h.secure.isSecure, isTrue, reason: 'the lock still needs it');

      // The lock goes off while a revealed secret still needs the flag.
      await h.secure.setSecure(secure: true, owner: editor);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConsolarrApp)),
      );
      await container.read(settingsProvider.notifier).setLockEnabled(false);
      await container
          .read(settingsProvider.notifier)
          .setBlockScreenshots(false);
      await tester.pumpAndSettle();
      expect(h.secure.isSecure, isTrue, reason: 'the editor still needs it');
      await h.secure.setSecure(secure: false, owner: editor);
      expect(h.secure.isSecure, isFalse);
      await _unmount(tester);
    });

    test('the platform screen is reference counted and only real changes '
        'reach the channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('consolarr/secure_screen'),
            (call) async {
              calls.add((call.arguments as Map)['secure'] as bool);
              return null;
            },
          );
      final screen = PlatformSecureScreen();
      final a = Object();
      final b = Object();
      await screen.setSecure(secure: true, owner: a);
      await screen.setSecure(secure: true, owner: b);
      await screen.setSecure(secure: false, owner: a);
      expect(calls, [true], reason: 'b still needs it');
      await screen.setSecure(secure: false, owner: b);
      expect(calls, [true, false]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('consolarr/secure_screen'),
            null,
          );
    });
  });

  group('fail closed and hidden mount', () {
    testWidgets('the content is mounted hidden while the lock resolves, '
        'without focus', (tester) async {
      final h = SettingsHarness(stored: lockOn());
      h.auth.hold = Completer<DeviceAuthResult>();
      await tester.pumpWidget(_app(h));
      // First frame: the lock is still resolving.
      expect(find.byType(Navigator), findsNothing, reason: 'not visible');
      expect(
        find.byType(Navigator, skipOffstage: false),
        findsWidgets,
        reason: 'warm: built but hidden',
      );
      final excluded = tester
          .widgetList<ExcludeFocus>(
            find.byType(ExcludeFocus, skipOffstage: false),
          )
          .any((w) => w.excluding);
      expect(excluded, isTrue);
      await tester.pumpAndSettle();
      // Locked: still hidden.
      expect(find.byType(Navigator), findsNothing);
      await _unmount(tester);
    });

    testWidgets('an unreadable store shows no content, is secure, and can '
        'be retried', (tester) async {
      final l10n = await _en();
      final store = ThrowingSettingsStore(stored: lockOn(), failures: 2);
      final h = SettingsHarness(store: store);
      h.auth.hold = Completer<DeviceAuthResult>();
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockLoadFailedTitle), findsOneWidget);
      expect(find.text(l10n.homeEmptyHeading), findsNothing);
      expect(find.byType(Navigator), findsNothing);
      expect(h.secure.isSecure, isTrue);
      expect(h.auth.reasons, isEmpty);
      await tester.tap(find.text(l10n.lockLoadFailedRetry));
      await tester.pumpAndSettle();
      // The retry read succeeds: the lock (on) is shown, never the content.
      expect(find.text(l10n.lockScreenTitle), findsOneWidget);
      expect(find.text(l10n.lockLoadFailedTitle), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the platform never sees the secure flag drop while "try '
        'again" reloads', (tester) async {
      final l10n = await _en();
      final store = ThrowingSettingsStore(stored: lockOn(), failures: 2);
      final h = SettingsHarness(store: store);
      h.auth.hold = Completer<DeviceAuthResult>();
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(h.secure.calls, [true]);
      await tester.tap(find.text(l10n.lockLoadFailedRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockScreenTitle), findsOneWidget);
      expect(h.secure.calls, isNot(contains(false)));
      expect(h.secure.isSecure, isTrue);
      await _unmount(tester);
    });

    testWidgets('system back never pops the routes behind the lock; on the '
        'lock screen it leaves the app', (tester) async {
      final h = SettingsHarness(stored: lockOn());
      h.auth.hold = Completer<DeviceAuthResult>();
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(platformCalls, contains('SystemNavigator.pop'));
      h.auth.hold!.complete(DeviceAuthResult.success);
      await tester.pumpAndSettle();
      // Unlocked: back is the router's again.
      platformCalls.clear();
      await tester.binding.handlePopRoute();
      await _unmount(tester);
    });
  });

  group('lock screen states', () {
    testWidgets('failed attempt feedback, then cool-down with a countdown', (
      tester,
    ) async {
      final l10n = await _en();
      final h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
      );
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockFailedFeedback), findsOneWidget);
      for (var i = 0; i < lockMaxAttempts - 1; i++) {
        await tester.tap(find.text(l10n.lockUnlockButton));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('30'), findsWidgets);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      h.clock.advance(lockCoolDown + const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await _unmount(tester);
    });

    testWidgets('the cool-down is a static live region and is announced '
        'once when it ends, not every second', (tester) async {
      final l10n = await _en();
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final m = message as Map;
            if (m['type'] == 'announce') {
              announcements.add((m['data'] as Map)['message'] as String);
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
      final h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
      );
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      for (var i = 0; i < lockMaxAttempts - 1; i++) {
        await tester.tap(find.text(l10n.lockUnlockButton));
        await tester.pumpAndSettle();
      }
      expect(_semanticsContain(tester, l10n.lockCoolDownPaused), isTrue);
      expect(
        _semanticsContain(tester, l10n.lockCoolDown(30)),
        isFalse,
        reason: 'the ticking number is not in the semantics tree',
      );
      expect(find.text(l10n.lockCoolDown(30)), findsOneWidget);
      // Ten ticks: nothing is announced.
      for (var i = 0; i < 10; i++) {
        h.clock.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(announcements, isEmpty);
      expect(_semanticsContain(tester, l10n.lockCoolDownPaused), isTrue);
      h.clock.advance(const Duration(seconds: 21));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(announcements, [l10n.lockCoolDownOver]);
      handle.dispose();
      await _unmount(tester);
    });

    testWidgets('biometrics unavailable explains the fallback', (tester) async {
      final l10n = await _en();
      final h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(
          biometrics: false,
          results: [DeviceAuthResult.failed],
        ),
      );
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockBiometricsUnavailable), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('credential removed: explains and offers an explicit, '
        'confirmed turn-off', (tester) async {
      final l10n = await _en();
      final h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(
          supportResult: DeviceAuthSupport.noSecureLock,
        ),
      );
      await tester.pumpWidget(_app(h));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockRemovedTitle), findsOneWidget);
      expect(find.text(l10n.homeEmptyHeading), findsNothing);
      await tester.tap(find.text(l10n.lockTurnOffButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lockTurnOffConfirmBody), findsOneWidget);
      await tester.tap(find.text(l10n.lockTurnOffConfirm));
      await tester.pumpAndSettle();
      expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
      expect(h.store.values[SettingsKeys.lockEnabled], '0');
      await _unmount(tester);
    });
  });
}
