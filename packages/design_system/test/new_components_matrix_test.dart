// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support/host.dart';
import 'support/samples.dart';

const _new = [
  'GlassSheet',
  'NestedMenu',
  'SortSheet',
  'FilterSheet',
  'SelectionBar',
  'StagedReveal',
  'SettingsSection',
  'SettingsRow (disabled)',
  'SwitchRow (off, disabled)',
];

const _a11y = [
  A11yVariant.normal,
  A11yVariant.highContrastVariant,
  A11yVariant.large,
];

void main() {
  final samples = componentSamples();
  for (final name in _new) {
    for (final a in _a11y) {
      testWidgets('$name [${a.name}]: full matrix, no overflow', (
        tester,
      ) async {
        await pumpMatrix(tester, (v) => hostApp(v, samples[name]!(), a11y: a));
      });

      testWidgets('$name [${a.name}]: accessible at 320x568 scale 2.0', (
        tester,
      ) async {
        await pumpMatrix(
          tester,
          (v) => hostApp(v, samples[name]!(), a11y: a),
          variants: harnessMatrix(
            sizes: const [Size(320, 568)],
            textScales: [2],
            locales: [const Locale('ar'), const Locale('en', 'XA')],
          ),
          verify: (v) => expectAccessible(tester),
        );
      });
    }
  }

  testWidgets('animated (motion on) variants also lay out', (tester) async {
    for (final name in _new) {
      await pumpMatrix(
        tester,
        (v) => hostApp(
          v,
          samples[name]!(),
          a11y: const A11yVariant('motion', reduceMotion: false),
        ),
        variants: harnessMatrix(
          sizes: const [Size(360, 800)],
          textScales: [1],
          locales: [const Locale('en')],
        ),
      );
    }
  });
}
