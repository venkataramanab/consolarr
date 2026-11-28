// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/presentation/reset_secure_storage.dart';
import 'package:consolarr/features/settings/presentation/settings_screen.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

import '../settings/screens_support.dart';

/// Becomes readable again once cleared, like a real Keystore after a reset.
class _LockedStore extends InMemorySecretStore {
  _LockedStore() : super({'s1/api_key': 'test-key-0000'}) {
    unavailable = true;
  }

  bool failClear = false;

  @override
  Future<void> deleteAll() async {
    if (failClear) throw const SecretStoreUnavailable();
    await super.deleteAll();
    unavailable = false;
  }
}

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Scaffold(
    body: SingleChildScrollView(child: SecureStorageUnavailableBanner()),
  );
}

Widget _app(HarnessVariant v, _LockedStore store, AppDatabase db, Widget home) {
  return ProviderScope(
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      databaseProvider.overrideWithValue(db),
    ],
    child: harnessApp(v, home),
  );
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('banner is hidden while the store is readable', (tester) async {
    final store = _LockedStore()..unavailable = false;
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_app(wide, store, db, const _Host()));
    await tester.pumpAndSettle();
    final l10n = await _en();
    expect(find.text(l10n.resetStorageBannerTitle), findsNothing);
  });

  testWidgets('unavailable: banner explains and cancel keeps everything', (
    tester,
  ) async {
    final store = _LockedStore();
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_app(wide, store, db, const _Host()));
    await tester.pumpAndSettle();
    final l10n = await _en();
    expect(find.text(l10n.resetStorageBannerTitle), findsOneWidget);

    await tester.tap(find.text(l10n.resetStorageBannerAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resetStorageConfirmTitle), findsOneWidget);
    expect(find.text(l10n.resetStorageConfirmBody), findsOneWidget);

    await tester.tap(find.text(l10n.settingsCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resetStorageConfirmTitle), findsNothing);
    store.unavailable = false;
    expect(await store.read('s1/api_key'), 'test-key-0000');
    expect(find.text(l10n.resetStorageBannerTitle), findsOneWidget);
  });

  testWidgets('confirm clears everything and the banner goes away', (
    tester,
  ) async {
    final store = _LockedStore();
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_app(wide, store, db, const _Host()));
    await tester.pumpAndSettle();
    final l10n = await _en();

    await tester.tap(find.text(l10n.resetStorageBannerAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.resetStorageConfirmAction));
    await tester.pumpAndSettle();

    expect(await store.read('s1/api_key'), isNull);
    expect(find.text(l10n.resetStorageBannerTitle), findsNothing);
  });

  testWidgets('a failed clear says so and keeps the banner', (tester) async {
    final store = _LockedStore()..failClear = true;
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_app(wide, store, db, const _Host()));
    await tester.pumpAndSettle();
    final l10n = await _en();

    await tester.tap(find.text(l10n.resetStorageBannerAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.resetStorageConfirmAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resetStorageFailed), findsOneWidget);
    expect(find.text(l10n.resetStorageBannerTitle), findsOneWidget);
  });

  testWidgets('the banner and the dialog pass the accessibility matrix', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => _app(v, _LockedStore(), AppDatabase.memory(), const _Host()),
      variants: harnessMatrix(),
      verify: (v) async {
        await tester.pumpAndSettle();
        await expectAccessible(tester);
        await tester.ensureVisible(find.byType(TextButton));
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await expectAccessible(tester);
        await tester.tap(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextButton),
              )
              .first,
        );
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('settings has the reset row under Security', (tester) async {
    final h = ScreenHarness();
    applyVariantView(tester, wide);
    await tester.pumpWidget(h.screen(wide, const SettingsScreen()));
    await tester.pumpAndSettle();
    final l10n = await _en();
    expect(find.text(l10n.resetStorageRowTitle), findsOneWidget);
  });
}
