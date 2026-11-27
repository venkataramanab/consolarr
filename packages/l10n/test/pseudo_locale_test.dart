// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/pseudo.dart';

void main() {
  test('accents letters, wraps and lengthens by about 40%', () {
    const source = 'Add a media server or download client to get started.';
    final out = pseudoLocalize(source);
    expect(out, startsWith('['));
    expect(out, endsWith(']'));
    expect(out, isNot(contains('A')));
    expect(out.length / source.length, inInclusiveRange(1.35, 1.6));
  });

  test('keeps simple placeholders intact', () {
    final out = pseudoLocalize('Hello {name}, welcome');
    expect(out, contains('{name}'));
    expect(out, isNot(contains('Hello')));
  });

  test('keeps plural structure and placeholders intact', () {
    final out = pseudoLocalize(
      '{count, plural, =0{No servers} =1{1 server} other{{count} servers}}',
    );
    expect(out, startsWith('{count,plural,'));
    expect(out, contains('=0{'));
    expect(out, contains('=1{'));
    expect(out, contains('other{{count} '));
    expect(out, isNot(contains('servers')));
    expect(out, endsWith('}'));
  });

  test('keeps select structure', () {
    final out = pseudoLocalize('{kind, select, tv{TV show} other{Movie}}');
    expect(out, contains('tv{'));
    expect(out, contains('other{'));
  });

  test('leaves non-letters alone and is deterministic', () {
    expect(pseudoLocalize('123'), pseudoLocalize('123'));
    expect(pseudoLocalize('123'), contains('123'));
  });
}
