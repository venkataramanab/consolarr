// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/server_switcher_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../servers/ui/support.dart';

final _stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

const _longName =
    'Living room media server with a very long descriptive name that wraps';

UiHarness _harness({int count = 3}) => UiHarness(
  servers: [
    for (var i = 0; i < count; i++)
      entry(
        's$i',
        name: i == 1 ? _longName : 'Example Sonarr $i',
        sortOrder: i,
      ),
  ],
  health: {
    's0': ServerHealth.healthy,
    's1': ServerHealth.unauthorized,
    's2': ServerHealth.unreachable,
  },
);

Widget _sheet(HarnessVariant v, UiHarness h) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    ...h.overrides,
    uiServersProvider.overrideWith((ref) => AsyncData(h.repo.entries)),
  ],
  child: harnessApp(
    v,
    const Scaffold(body: ServerSwitcherSheet(kind: ServiceKind.sonarr)),
  ),
);

void main() {
  testWidgets('no overflow across the full matrix', (tester) async {
    final h = _harness();
    await pumpMatrix(tester, (v) => _sheet(v, h));
  });

  testWidgets('accessible at 320x568, scale 2.0, ar and en_XA', (tester) async {
    final h = _harness();
    await pumpMatrix(
      tester,
      (v) => _sheet(v, h),
      variants: _stress,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('accessible in en at scale 1.0', (tester) async {
    final h = _harness();
    await pumpMatrix(
      tester,
      (v) => _sheet(v, h),
      variants: harnessMatrix(textScales: [1], locales: [const Locale('en')]),
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('the empty list says so and survives the stress matrix', (
    tester,
  ) async {
    final h = _harness(count: 0);
    await pumpMatrix(
      tester,
      (v) => _sheet(v, h),
      variants: _stress,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('picking a server makes it active', (tester) async {
    final h = _harness();
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(_sheet(v, h));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Sonarr 2'));
    await tester.pumpAndSettle();
    expect(h.repo.active[ServiceKind.sonarr], 's2');
  });
}
