// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support/samples.dart';

Widget _host(HarnessVariant v, Widget child) => harnessApp(
  v,
  ConsolarrEffectsScope(
    reduceMotion: true,
    child: Scaffold(
      body: SafeArea(child: SingleChildScrollView(child: child)),
    ),
  ),
);

/// Public widgets that are deliberately not sampled on their own: the host
/// wrapper every sample is pumped under.
const _notSampled = {
  'ConsolarrEffectsScope',
  'TouchTargetsScope',
  'ConsolarrSeparatorsScope',
};

void main() {
  test('every public design-system widget has a matrix sample', () {
    final widget = RegExp(
      r'^class ([A-Z]\w*) extends '
      r'(?:StatelessWidget|StatefulWidget|SingleChildRenderObjectWidget)\b',
      multiLine: true,
    );
    final exported = <String>{
      for (final file in Directory('lib/src').listSync().whereType<File>())
        for (final m in widget.allMatches(file.readAsStringSync())) m[1]!,
    }..removeAll(_notSampled);
    expect(exported, containsAll(['PosterCard', 'CertificateTrustSheet']));

    final sampled = componentSamples().keys.join('\n');
    final missing = [
      for (final name in exported)
        if (!sampled.contains(name)) name,
    ];
    expect(
      missing,
      isEmpty,
      reason: 'add these to componentSamples() in test/support/samples.dart',
    );
  });

  componentSamples().forEach((name, build) {
    testWidgets('$name: no overflow across the full matrix', (tester) async {
      await pumpMatrix(tester, (v) => _host(v, build()));
    });

    testWidgets('$name: accessible at scale 2.0 in ar and en_XA', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => _host(v, build()),
        variants: harnessMatrix(
          textScales: [2],
          locales: [const Locale('ar'), const Locale('en', 'XA')],
        ),
        verify: (v) => expectAccessible(tester),
      );
    });

    testWidgets('$name: accessible at scale 1.0 in en', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _host(v, build()),
        variants: harnessMatrix(textScales: [1], locales: [const Locale('en')]),
        verify: (v) => expectAccessible(tester),
      );
    });
  });
}
