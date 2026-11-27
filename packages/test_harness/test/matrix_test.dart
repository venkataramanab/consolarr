// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

Widget _wide() => Row(
  // ignore: consolarr_no_ui_string -- test fixture, not user-facing
  children: [Text('x' * 400)],
);

Widget _fine() => const SingleChildScrollView(child: Text('ok'));

void main() {
  test('default matrix covers sizes x scales x locales x themes', () {
    final m = harnessMatrix();
    expect(m, hasLength(3 * 2 * 3 * 2));
    expect(m.map((v) => v.size).toSet(), harnessSizes.toSet());
    expect(m.map((v) => v.textScale).toSet(), {1.0, 2.0});
    expect(m.map((v) => v.locale.toString()).toSet(), {'en', 'en_XA', 'ar'});
    expect(m.map((v) => v.brightness).toSet(), {
      Brightness.dark,
      Brightness.light,
    });
  });

  testWidgets('pumpMatrix visits every variant for a well-behaved widget', (
    tester,
  ) async {
    final visited = <String>[];
    await pumpMatrix(
      tester,
      (v) => harnessApp(v, _fine()),
      verify: (v) async => visited.add(v.label),
    );
    expect(visited, hasLength(36));
    expect(visited.toSet(), hasLength(36));
  });

  testWidgets('pumpMatrix applies size, text scale, locale and theme', (
    tester,
  ) async {
    late MediaQueryData media;
    late Locale locale;
    late Brightness brightness;
    final variant = const HarnessVariant(
      size: Size(320, 568),
      textScale: 2,
      locale: Locale('ar'),
      brightness: Brightness.light,
    );
    await pumpMatrix(
      tester,
      (v) => harnessApp(
        v,
        Builder(
          builder: (context) {
            media = MediaQuery.of(context);
            locale = Localizations.localeOf(context);
            brightness = Theme.of(context).brightness;
            return const SizedBox();
          },
        ),
      ),
      variants: [variant],
    );
    expect(media.size, const Size(320, 568));
    expect(media.textScaler.scale(10), 20);
    expect(locale, const Locale('ar'));
    expect(brightness, Brightness.light);
  });

  testWidgets('pumpMatrix fails on a RenderFlex overflow', (tester) async {
    await expectTestFailure(
      () => pumpMatrix(
        tester,
        (v) => harnessApp(v, _wide()),
        variants: [harnessMatrix().first],
      ),
      message: allOf(contains('RenderFlex overflow'), contains('320x568')),
    );
  });

  testWidgets('pumpMatrix fails on any other framework exception', (
    tester,
  ) async {
    await expectTestFailure(
      () => pumpMatrix(
        tester,
        (v) => harnessApp(v, Builder(builder: (_) => throw StateError('boom'))),
        variants: [harnessMatrix().first],
      ),
      message: contains('Exception'),
    );
  });
}
