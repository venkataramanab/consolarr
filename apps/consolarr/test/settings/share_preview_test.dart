// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/data/external_actions.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_preview_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

import '../../../../packages/observability/test/canary_corpus.dart';

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

void main() {
  testWidgets('the preview shows exactly the text that is shared, even '
      'when the log is far over the cap', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final h = ScreenHarness(
      stored: {SettingsKeys.diagnosticsEnabled: '1'},
      servers: [entry('a')],
    );
    applyVariantView(tester, wide);
    await tester.pumpWidget(h.screen(wide, const DiagnosticsPreviewScreen()));
    final c = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final log = c.read(diagnosticsLogProvider)..level = LogLevel.debug;
    // 500 entries of about 1 KB: well beyond what a 150 KB share allows.
    for (var i = 0; i < 500; i++) {
      log.add(LogLevel.info, 'entry $i ${'ع' * 400}');
    }
    c.invalidate(diagnosticsBundleProvider);
    await tester.pumpAndSettle();
    final bundle = c.read(diagnosticsBundleProvider).requireValue;
    expect(
      utf8.encode(bundle.text).length,
      lessThanOrEqualTo(shareTextMaxBytes),
    );
    expect(bundle.text, contains('older entries left out'));

    final share = find.text(l10n.diagShareFile, skipOffstage: false);
    for (var i = 0; i < 80 && share.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
    }
    await tester.ensureVisible(share);
    await tester.pumpAndSettle();
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(h.base.actions.shared.single, bundle.text);
    // Every section the preview renders is part of the shared text.
    for (final s in bundle.sections) {
      expect(h.base.actions.shared.single, contains(s.body));
    }
  });

  group('canary corpus after the share cap', () {
    test('capShareText keeps the corpus out of the shared text', () {
      final bundle = DiagnosticsBundle.build(
        info: const DiagnosticsInfo(
          appVersion: '1',
          buildMode: 'release',
          platform: 'Android API 34',
          locale: 'en',
        ),
        errorCategories: const [],
        entries: [
          for (final c in canaryCorpus)
            LogEntry(
              time: DateTime.utc(2026),
              level: LogLevel.error,
              message: c.text,
            ),
        ],
      );
      // A tiny cap forces the cut path.
      for (final max in [shareTextMaxBytes, 900]) {
        final out = capShareText(bundle.text, '[cut]', maxBytes: max).text;
        for (final f in canaryForbidden) {
          expect(
            out.toLowerCase(),
            isNot(contains(f.toLowerCase())),
            reason: f,
          );
        }
      }
    });
  });
}
