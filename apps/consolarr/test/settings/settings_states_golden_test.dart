// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/connection_check_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_preview_screen.dart';
import 'package:consolarr/features/settings/presentation/lock_settings_screen.dart';
import 'package:consolarr/features/settings/presentation/privacy_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

const _variants = {
  'dark_en_360x800': HarnessVariant(
    size: Size(360, 800),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.dark,
  ),
  'light_ar_320x568_x2': HarnessVariant(
    size: Size(320, 568),
    textScale: 2,
    locale: Locale('ar'),
    brightness: Brightness.light,
  ),
};

Future<void> _golden(
  WidgetTester tester,
  String name,
  HarnessVariant v,
  ScreenHarness h,
  Widget screen, {
  Future<void> Function()? after,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(h.screen(v, screen));
  await tester.pumpAndSettle();
  if (after != null) await after();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/settings_${name}_${_nameOf(v)}.png'),
  );
}

String _nameOf(HarnessVariant v) =>
    _variants.entries.firstWhere((e) => e.value == v).key;

void main() {
  for (final v in _variants.values) {
    testWidgets('golden: lock settings, lock off ${_nameOf(v)}', (
      tester,
    ) async {
      await _golden(
        tester,
        'lock_off',
        v,
        ScreenHarness(),
        const LockSettingsScreen(),
      );
    });

    testWidgets('golden: privacy, consent on ${_nameOf(v)}', (tester) async {
      await _golden(
        tester,
        'privacy_consent_on',
        v,
        ScreenHarness(
          stored: {
            SettingsKeys.consentCrashReports: '1',
            SettingsKeys.consentAnalytics: '1',
          },
        ),
        const PrivacyScreen(),
      );
    });

    testWidgets('golden: diagnostics preview loading ${_nameOf(v)}', (
      tester,
    ) async {
      final never = StreamController<List<ServerEntry>>();
      addTearDown(never.close);
      applyVariantView(tester, v);
      final h = ScreenHarness(serversStream: () => never.stream);
      await tester.pumpWidget(h.screen(v, const DiagnosticsPreviewScreen()));
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_preview_loading_${_nameOf(v)}.png'),
      );
    });

    testWidgets('golden: diagnostics preview error ${_nameOf(v)}', (
      tester,
    ) async {
      await _golden(
        tester,
        'preview_error',
        v,
        ScreenHarness(
          serversStream: () =>
              Stream<List<ServerEntry>>.error(StateError('db')),
        ),
        const DiagnosticsPreviewScreen(),
      );
    });

    testWidgets('golden: connection check, no servers ${_nameOf(v)}', (
      tester,
    ) async {
      await _golden(
        tester,
        'check_no_servers',
        v,
        ScreenHarness(),
        const ConnectionCheckScreen(),
      );
    });

    testWidgets('golden: connection check, mid-run ${_nameOf(v)}', (
      tester,
    ) async {
      final h = ScreenHarness(servers: [entry('a', name: 'Example A')]);
      h.ui.tester.gate = Completer<void>();
      applyVariantView(tester, v);
      await tester.pumpWidget(h.screen(v, const ConnectionCheckScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_check_midrun_${_nameOf(v)}.png'),
      );
      h.ui.tester.gate!.complete();
      await tester.pumpAndSettle();
    });

    // The three states of the services check on the diagnostics preview.
    for (final phase in ['checking', 'partial', 'failed']) {
      testWidgets(
        'golden: diagnostics preview, services $phase ${_nameOf(v)}',
        (tester) async {
          final stream = StreamController<List<ServerEntry>>();
          addTearDown(stream.close);
          final h = ScreenHarness(
            stored: {SettingsKeys.diagnosticsEnabled: '1'},
            serversStream: () => stream.stream,
          );
          stream.add([entry('a')]);
          applyVariantView(tester, v);
          await tester.pumpWidget(
            h.screen(v, const DiagnosticsPreviewScreen()),
          );
          await tester.pumpAndSettle();
          switch (phase) {
            case 'checking':
              h.ui.tester.gate = Completer<void>();
              await tester.tap(find.byType(OutlinedButton).first);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 50));
            case 'partial':
              await tester.tap(find.byType(OutlinedButton).first);
              await tester.pumpAndSettle();
              stream.add([entry('a'), entry('b')]);
              await tester.pumpAndSettle();
            case 'failed':
              stream.addError(StateError('db'));
              await tester.pumpAndSettle();
              await tester.tap(find.byType(OutlinedButton).first);
              await tester.pumpAndSettle();
          }
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/settings_preview_services_${phase}_${_nameOf(v)}.png',
            ),
          );
          final gate = h.ui.tester.gate;
          if (gate != null && !gate.isCompleted) {
            gate.complete();
            await tester.pumpAndSettle();
          }
        },
      );
    }
  }
}
