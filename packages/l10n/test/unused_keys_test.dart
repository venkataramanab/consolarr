// SPDX-License-Identifier: GPL-3.0-or-later

// Self-tests for the unused-localization-key check: only real accessor usage
// counts, and a planted unused key must be reported.

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/unused_keys.dart';

void main() {
  group('findUnusedKeys', () {
    test('accessor forms count as usage', () {
      const src = '''
        final l10n = context.l10n;
        Widget a() => Text(l10n.alpha);
        Widget b(BuildContext c) => Text(AppLocalizations.of(c).beta);
        Widget d(BuildContext c) => Text(AppLocalizations.of(c)!.gamma);
        Widget e(BuildContext c) => Text(context.l10n.delta(3));
        Widget f(BuildContext c) => Text(AppLocalizations.of(maybe(c))!.epsilon);
        Widget g() => Text(
          l10n
              .zeta,
        );
      ''';
      expect(
        findUnusedKeys(
          {'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'},
          [src],
        ),
        isEmpty,
      );
    });

    test('a planted unused key is reported', () {
      const src = 'Widget a() => Text(l10n.used);';
      expect(findUnusedKeys({'used', 'plantedUnused'}, [src]), [
        'plantedUnused',
      ]);
    });

    test('mentions in comments do not count', () {
      const src = '''
        // l10n.inLine
        /// l10n.inDoc
        /* l10n.inBlock /* nested l10n.inNested */ l10n.stillBlock */
        Widget a() => Text(l10n.used);
      ''';
      expect(
        findUnusedKeys(
          {'used', 'inLine', 'inDoc', 'inBlock', 'inNested', 'stillBlock'},
          [src],
        ),
        unorderedEquals([
          'inLine',
          'inDoc',
          'inBlock',
          'inNested',
          'stillBlock',
        ]),
      );
    });

    test(
      'mentions inside string literals do not count, interpolation does',
      () {
        const src = r'''
        const a = 'l10n.inString';
        const b = "see l10n.inDouble for details";
        const c = r'l10n.inRaw';
        const d = """
l10n.inTriple
""";
        final e = 'x ${l10n.interpolated} y';
        final f = 'url: https://example.invalid/l10n.inUrl';
      ''';
        expect(
          findUnusedKeys(
            {
              'inString',
              'inDouble',
              'inRaw',
              'inTriple',
              'interpolated',
              'inUrl',
            },
            [src],
          ),
          unorderedEquals([
            'inString',
            'inDouble',
            'inRaw',
            'inTriple',
            'inUrl',
          ]),
        );
      },
    );

    test('same-named members of other objects do not count', () {
      const src = '''
        final a = user.title;
        final b = widget.title;
        final c = other.l10nTitle;
        final d = l10n.title2;
      ''';
      expect(
        findUnusedKeys({'title', 'l10nTitle'}, [src]),
        unorderedEquals(['title', 'l10nTitle']),
      );
    });

    test('a longer key does not satisfy a shorter one', () {
      expect(findUnusedKeys({'home', 'homeTitle'}, ['x(l10n.homeTitle);']), [
        'home',
      ]);
    });
  });
}
