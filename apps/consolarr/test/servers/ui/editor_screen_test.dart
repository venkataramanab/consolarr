// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/application/error_messages.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/server_editor_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

Future<void> _pump(
  WidgetTester tester,
  UiHarness h, {
  Widget screen = const ServerEditorScreen(),
  HarnessVariant variant = _v,
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(h.app(variant, screen));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Taps "Test connection" and lets the sheet (if any) open. The sheet is
/// shown while the progress spinner still spins, so `pumpAndSettle` cannot be
/// used until the sheet is dismissed.
Future<void> _tapTest(WidgetTester tester) async {
  final f = find.text('Test connection');
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _fillValid(WidgetTester tester) async {
  await tester.enterText(_field('Display name'), 'Example Sonarr');
  await tester.enterText(_field('Address'), 'https://sonarr.example');
  await tester.pumpAndSettle();
}

ConnectionTestFailure _fail(AppError e) => ConnectionTestFailure(e);

void main() {
  group('form', () {
    testWidgets('pristine: no errors, service picker offers both kinds', (
      tester,
    ) async {
      await _pump(tester, UiHarness());
      expect(find.text('Add server'), findsOneWidget);
      expect(find.text('Sonarr'), findsOneWidget);
      expect(find.text('qBittorrent'), findsOneWidget);
      expect(find.text('Enter a name for this server.'), findsNothing);
    });

    testWidgets(
      'save with an empty form shows inline errors and saves nothing',
      (tester) async {
        final h = UiHarness();
        await _pump(tester, h);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Enter a name for this server.'), findsOneWidget);
        expect(find.text('Enter the server address.'), findsOneWidget);
        expect(h.repo.saved, isEmpty);
      },
    );

    testWidgets('credentials and query strings in the address are explained', (
      tester,
    ) async {
      await _pump(tester, UiHarness());
      await tester.enterText(
        _field('Address'),
        'https://user:pw@sonarr.example',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("Don't put a username"), findsOneWidget);
      await tester.enterText(
        _field('Address'),
        'https://sonarr.example/?apikey=x',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Remove everything after'), findsOneWidget);
      await tester.enterText(_field('Address'), 'sonarr');
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a full address'), findsOneWidget);
    });

    testWidgets('a valid form saves a draft with typed secrets', (
      tester,
    ) async {
      final h = UiHarness();
      await _pump(tester, h);
      await _fillValid(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(SecretTextField),
          matching: find.byType(EditableText),
        ),
        'test-key-0000',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final d = h.repo.saved.single;
      expect(d.name, 'Example Sonarr');
      expect(d.credentials.apiKey, 'test-key-0000');
      expect(d.id, isNotNull);
      expect(h.repo.entries, hasLength(1));
    });

    testWidgets('cleartext opt-in shows the risk and starts off', (
      tester,
    ) async {
      final h = UiHarness();
      await _pump(tester, h);
      await tester.enterText(_field('Address'), 'http://192.0.2.10:8989');
      await tester.pumpAndSettle();
      expect(find.textContaining('uses http'), findsOneWidget);
      await _tap(tester, find.byType(Switch));
      expect(find.textContaining('without encryption'), findsOneWidget);
      await tester.enterText(_field('Display name'), 'Example');
      await _tap(tester, find.text('Save'));
      expect(h.repo.saved.single.allowCleartext, isTrue);
    });

    testWidgets('custom headers: add, fill, remove', (tester) async {
      final h = UiHarness();
      await _pump(tester, h);
      await _fillValid(tester);
      await _tap(tester, find.text('Add header'));
      await tester.enterText(_field('Header name'), 'X-Gateway');
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(SecretTextField, 'Header value'),
          matching: find.byType(EditableText),
        ),
        'test-token-0000',
      );
      await _tap(tester, find.text('Save'));
      final header = h.repo.saved.single.credentials.headers.single;
      expect(header.name, 'X-Gateway');
      expect(header.value, 'test-token-0000');
    });

    testWidgets('removing a header row removes it', (tester) async {
      await _pump(tester, UiHarness());
      await _tap(tester, find.text('Add header'));
      expect(find.text('Header name'), findsOneWidget);
      await _tap(tester, find.byTooltip('Remove header'));
      expect(find.text('Header name'), findsNothing);
    });

    testWidgets('a repository failure is explained, not thrown', (
      tester,
    ) async {
      final h = UiHarness();
      h.repo.saveError = const AppError(
        ErrorCategory.parseError,
        debugDetail: 'invalid address',
      );
      await _pump(tester, h);
      await _fillValid(tester);
      await _tap(tester, find.text('Save'));
      expect(find.text("Couldn't save the server"), findsOneWidget);
    });
  });

  group('editing', () {
    UiHarness existing({bool needsCredentials = false}) => UiHarness(
      servers: [
        entry('a', name: 'Example Sonarr', needsCredentials: needsCredentials),
      ],
    );

    testWidgets('prefills identity but never secrets, and says how to keep', (
      tester,
    ) async {
      final h = existing();
      h.repo.credentials['a'] = const ServerCredentials(
        apiKey: 'test-key-0000',
      );
      await _pump(tester, h, screen: const ServerEditorScreen(serverId: 'a'));
      expect(find.text('Edit server'), findsOneWidget);
      expect(find.text('Example Sonarr'), findsOneWidget);
      expect(find.text('test-key-0000'), findsNothing);
      expect(find.text('Leave empty to keep the saved value.'), findsOneWidget);
      await _tap(tester, find.text('Save'));
      expect(h.repo.saved.single.credentials.apiKey, isNull);
      expect(h.repo.saved.single.id, 'a');
    });

    testWidgets('missing secrets show the re-entry prompt', (tester) async {
      await _pump(
        tester,
        existing(needsCredentials: true),
        screen: const ServerEditorScreen(serverId: 'a'),
      );
      expect(
        find.textContaining('credentials for this server are missing'),
        findsOneWidget,
      );
    });

    testWidgets('the saved test uses stored secrets unless replaced', (
      tester,
    ) async {
      final h = existing();
      h.repo.credentials['a'] = const ServerCredentials(
        apiKey: 'test-key-0000',
      );
      await _pump(tester, h, screen: const ServerEditorScreen(serverId: 'a'));
      await _tap(tester, find.text('Test connection'));
      expect(h.tester.credentials.single.apiKey, 'test-key-0000');
    });

    testWidgets('a changed address needs the secrets again and the test never '
        'sends the stored ones', (tester) async {
      final h = existing();
      h.repo.credentials['a'] = const ServerCredentials(
        apiKey: 'test-key-0000',
      );
      await _pump(tester, h, screen: const ServerEditorScreen(serverId: 'a'));
      await tester.enterText(_field('Address'), 'https://other-host.example');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('stored key or password will not be used'),
        findsOneWidget,
      );
      expect(find.text('Leave empty to keep the saved value.'), findsNothing);

      // Saving is blocked until the key is typed again.
      await _tap(tester, find.text('Save'));
      expect(h.repo.saved, isEmpty);
      expect(
        find.textContaining('Enter the key or password again'),
        findsOneWidget,
      );

      await tester.enterText(_field('API key'), 'test-key-1111');
      await _tapTest(tester);
      expect(h.tester.credentials.single.apiKey, 'test-key-1111');
      expect(
        h.tester.credentials.map((c) => c.apiKey),
        isNot(contains('test-key-0000')),
      );
    });

    testWidgets(
      'pinned certificate is shown and can be removed after confirm',
      (tester) async {
        final h = existing();
        final key = pinKeyFor('a');
        final fp = details().fingerprint;
        await h.pins.write(
          key,
          fp,
          UserPinConfirmation.userAccepted(key: key, fingerprint: fp),
        );
        await _pump(tester, h, screen: const ServerEditorScreen(serverId: 'a'));
        await tester.ensureVisible(find.text('Trusted certificate'));
        expect(find.text(fp.display), findsOneWidget);
        await _tap(tester, find.text('Remove trusted certificate'));
        expect(await h.pins.read(key), isNotNull, reason: 'needs confirmation');
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Remove'),
          ),
        );
        await tester.pumpAndSettle();
        expect(await h.pins.read(key), isNull);
        expect(find.text('Trusted certificate'), findsNothing);
      },
    );
  });

  group('connection test', () {
    testWidgets('testing state, then success with the version', (tester) async {
      final tester0 = FakeTester()..gate = Completer<void>();
      final h = UiHarness(tester: tester0);
      await _pump(tester, h);
      await _fillValid(tester);
      await tester.ensureVisible(find.text('Test connection'));
      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Testing…'), findsOneWidget);
      tester0.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Connected. Server version 4.0.1.'), findsOneWidget);
    });

    testWidgets('an invalid form is not tested', (tester) async {
      final h = UiHarness();
      await _pump(tester, h);
      await _tap(tester, find.text('Test connection'));
      expect(h.tester.profiles, isEmpty);
      expect(find.text('Enter the server address.'), findsOneWidget);
    });

    const failures = [
      AppError(ErrorCategory.authFailed),
      AppError(ErrorCategory.authFailed, debugDetail: 'needs_credentials'),
      AppError(ErrorCategory.timeout),
      AppError(ErrorCategory.cleartextRefused),
      AppError(ErrorCategory.unsupportedVersion),
      AppError(ErrorCategory.notFound),
      AppError(ErrorCategory.serverError),
      AppError(ErrorCategory.networkUnreachable),
      AppError(ErrorCategory.parseError),
      AppError(ErrorCategory.redirectRefused),
      AppError(ErrorCategory.responseTooLarge),
    ];
    for (final error in failures) {
      testWidgets(
        'failure ${error.category.code} ${error.debugDetail ?? ''} shows '
        'its own message and fix hint',
        (tester) async {
          final h = UiHarness(tester: FakeTester([_fail(error)]));
          await _pump(tester, h);
          await _fillValid(tester);
          await _tap(tester, find.text('Test connection'));
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ServerEditorScreen)),
          );
          final m = connectionErrorMessage(l10n, error);
          expect(find.text('Failed'), findsOneWidget);
          expect(find.text(m.message), findsOneWidget);
          expect(find.text(m.hint), findsOneWidget);
        },
      );
    }

    testWidgets('the result clears when the form changes', (tester) async {
      await _pump(tester, UiHarness());
      await _fillValid(tester);
      await _tap(tester, find.text('Test connection'));
      expect(find.text('Connected'), findsOneWidget);
      await tester.enterText(_field('Address'), 'https://other.example');
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsNothing);
    });
  });

  group('trust sheet', () {
    CertificateDecisionRequired firstUse() => CertificateDecisionRequired(
      key: pinKeyFor('x'),
      certificate: details(),
    );

    testWidgets('accept writes the pin for the saved id and retests', (
      tester,
    ) async {
      final h = UiHarness(
        tester: FakeTester([
          _fail(firstUse()),
          const ConnectionTestSuccess(version: '4.0.1'),
        ]),
      );
      await _pump(tester, h);
      await _fillValid(tester);
      await _tapTest(tester);
      expect(find.text('Trust this certificate?'), findsOneWidget);
      expect(find.text('AB:CC:CC:CC'), findsWidgets);
      await tester.tap(find.text('Trust certificate'));
      await tester.pumpAndSettle();
      expect(await h.pins.read(pinKeyFor('x')), details().fingerprint);
      expect(h.tester.profiles, hasLength(2));
      expect(find.text('Connected'), findsOneWidget);
      expect(h.analytics.events, contains('certificate_decision'));
      expect(
        h.analytics.parameters.any((p) => p['decision'] == 'accepted'),
        isTrue,
      );
    });

    testWidgets('reject writes nothing and leaves the failure visible', (
      tester,
    ) async {
      final h = UiHarness(tester: FakeTester([_fail(firstUse())]));
      await _pump(tester, h);
      await _fillValid(tester);
      await _tapTest(tester);
      await tester.tap(find.text("Don't trust"));
      await tester.pumpAndSettle();
      expect(await h.pins.read(pinKeyFor('x')), isNull);
      expect(h.tester.profiles, hasLength(1));
      expect(
        find.text("The server's certificate is not trusted by this device."),
        findsOneWidget,
      );
      expect(
        h.analytics.parameters.any((p) => p['decision'] == 'rejected'),
        isTrue,
      );
    });

    testWidgets('mismatch blocks, warns and shows the previous fingerprint', (
      tester,
    ) async {
      final old = details(hex: '11').fingerprint;
      final h = UiHarness(
        tester: FakeTester([
          _fail(
            TlsPinMismatch(
              key: pinKeyFor('x'),
              pinned: old,
              presented: details(hex: '22'),
            ),
          ),
        ]),
      );
      final key = pinKeyFor('x');
      await h.pins.write(
        key,
        old,
        UserPinConfirmation.userAccepted(key: key, fingerprint: old),
      );
      await _pump(tester, h);
      await _fillValid(tester);
      await _tapTest(tester);
      expect(find.text('Certificate changed'), findsOneWidget);
      expect(find.textContaining('intercepting'), findsOneWidget);
      expect(find.text('11:CC:CC:CC'), findsWidgets);
      await tester.tap(find.text("Don't trust"));
      await tester.pumpAndSettle();
      expect(await h.pins.read(key), old, reason: 'blocked, pin unchanged');
      expect(
        find.textContaining('different from the one you trusted'),
        findsOneWidget,
      );
    });

    testWidgets('mismatch accept is an explicit re-trust', (tester) async {
      final old = details(hex: '11').fingerprint;
      final fresh = details(hex: '22');
      final h = UiHarness(
        tester: FakeTester([
          _fail(
            TlsPinMismatch(key: pinKeyFor('x'), pinned: old, presented: fresh),
          ),
          const ConnectionTestSuccess(version: '4.0.1'),
        ]),
      );
      final key = pinKeyFor('x');
      await h.pins.write(
        key,
        old,
        UserPinConfirmation.userAccepted(key: key, fingerprint: old),
      );
      await _pump(tester, h);
      await _fillValid(tester);
      await _tapTest(tester);
      await tester.tap(find.text('Trust new certificate'));
      await tester.pumpAndSettle();
      expect(await h.pins.read(key), fresh.fingerprint);
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('expired certificate cannot be trusted', (tester) async {
      final h = UiHarness(
        tester: FakeTester([
          _fail(
            CertificateExpired(
              key: pinKeyFor('x'),
              certificate: details(notAfter: DateTime.utc(2020)),
            ),
          ),
        ]),
      );
      await _pump(tester, h);
      await _fillValid(tester);
      await _tapTest(tester);
      expect(find.text('Certificate expired'), findsOneWidget);
      final accept = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Trust certificate'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(accept.onPressed, isNull);
      await tester.tap(find.text("Don't trust"));
      await tester.pumpAndSettle();
      expect(await h.pins.read(pinKeyFor('x')), isNull);
    });
  });

  group('secret handling', () {
    testWidgets('secure flag is on only while a secret is revealed', (
      tester,
    ) async {
      final h = UiHarness();
      await _pump(tester, h);
      expect(h.secureScreen.isSecure, isFalse);
      await _tap(tester, find.byTooltip('Show value'));
      expect(h.secureScreen.isSecure, isTrue);
      await _tap(tester, find.byTooltip('Hide value'));
      expect(h.secureScreen.isSecure, isFalse);
    });

    testWidgets('leaving the screen while revealed clears the flag', (
      tester,
    ) async {
      final h = UiHarness();
      await _pump(tester, h);
      await _tap(tester, find.byTooltip('Show value'));
      expect(h.secureScreen.isSecure, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(h.secureScreen.isSecure, isFalse);
    });
  });

  group('unsaved changes', () {
    testWidgets('back with edits asks first; keep editing stays', (
      tester,
    ) async {
      await _pump(tester, UiHarness());
      await tester.enterText(_field('Display name'), 'Example');
      await tester.pump();
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Add server'), findsOneWidget);
    });

    testWidgets('a pristine form does not ask', (tester) async {
      await _pump(tester, UiHarness());
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
    });
  });

  group('screen view', () {
    testWidgets('reports screen_viewed once', (tester) async {
      final h = UiHarness();
      await _pump(tester, h);
      expect(
        h.analytics.events.where((e) => e == 'screen_viewed'),
        hasLength(1),
      );
    });
  });

  group('matrix', () {
    testWidgets('no overflow with long text in every size/scale/locale/theme', (
      tester,
    ) async {
      final long = 'a' * 120;
      await pumpMatrix(tester, (v) {
        final h = UiHarness(
          servers: [entry('a', name: long, address: 'https://$long.example')],
        );
        return h.app(v, const ServerEditorScreen(serverId: 'a'));
      });
    });

    testWidgets('accessibility at 2.0 in ar and en_XA, and 1.0 in en', (
      tester,
    ) async {
      for (final locales in [
        [const Locale('ar'), const Locale('en', 'XA')],
        [const Locale('en')],
      ]) {
        await pumpMatrix(
          tester,
          (v) => UiHarness().app(v, const ServerEditorScreen()),
          variants: harnessMatrix(
            textScales: [locales.length == 2 ? 2 : 1],
            locales: locales,
          ),
          verify: (_) => expectAccessible(tester),
        );
      }
    });

    testWidgets('failure and trust sheet states pass the matrix too', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => UiHarness(
          tester: FakeTester([_fail(const AppError(ErrorCategory.timeout))]),
        ).app(v, const ServerEditorScreen()),
        variants: harnessMatrix(sizes: [const Size(320, 568)], textScales: [2]),
      );
    });
  });
}
