// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/server_editor_screen.dart';
import 'package:consolarr/features/servers/presentation/servers_list_screen.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

void main() {
  testWidgets('golden: servers list with data (en, dark, 360x800)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    final h = UiHarness(
      servers: [
        entry('a', name: 'Example Sonarr', isStartup: true),
        entry(
          'b',
          name: 'Example qBittorrent',
          kind: ServiceKind.qbittorrent,
          address: 'http://192.0.2.10:8080',
          allowCleartext: true,
          sortOrder: 1,
        ),
        entry(
          'c',
          name: 'Example Backup',
          needsCredentials: true,
          sortOrder: 2,
        ),
      ],
      health: const {
        'a': ServerHealth.healthy,
        'b': ServerHealth.unreachable,
        'c': ServerHealth.unauthorized,
      },
    );
    h.repo.active[ServiceKind.sonarr] = 'a';
    applyVariantView(tester, v);
    await tester.pumpWidget(h.app(v, const ServersListScreen()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/servers_list_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: editor with a failed test (ar, light, 360x800)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('ar'),
      brightness: Brightness.light,
    );
    final h = UiHarness(
      tester: FakeTester([
        const ConnectionTestFailure(AppError(ErrorCategory.authFailed)),
      ]),
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(h.app(v, const ServerEditorScreen()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Example Sonarr');
    await tester.enterText(fields.at(1), 'https://sonarr.example');
    await tester.pumpAndSettle();
    final test = find.byType(FilledButton);
    await tester.ensureVisible(test);
    await tester.pumpAndSettle();
    await tester.tap(test);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/server_editor_failed_ar_light_360x800.png'),
    );
  });
}
