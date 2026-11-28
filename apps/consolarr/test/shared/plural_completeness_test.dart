// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The plural clauses of one message: selector -> true for every top-level
/// `{count, plural, ...}` block (nested plurals are read too).
List<Set<String>> pluralForms(String message) {
  final result = <Set<String>>[];
  final head = RegExp(r'\{\s*\w+\s*,\s*plural\s*,');
  for (final m in head.allMatches(message)) {
    var i = m.end;
    final forms = <String>{};
    // Read `selector{...}` clauses until the closing brace of the plural.
    while (i < message.length) {
      while (i < message.length && ' \n\t'.contains(message[i])) {
        i++;
      }
      if (i >= message.length || message[i] == '}') break;
      final start = i;
      while (i < message.length && message[i] != '{') {
        i++;
      }
      if (i >= message.length) break;
      forms.add(message.substring(start, i).trim());
      var depth = 0;
      while (i < message.length) {
        if (message[i] == '{') depth++;
        if (message[i] == '}') {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
        i++;
      }
    }
    result.add(forms);
  }
  return result;
}

bool _has(Set<String> f, String word, String exact) =>
    f.contains(word) || f.contains(exact);

List<File> _arabicArbs() {
  final out = <File>[];
  for (final root in ['lib', '../../packages']) {
    for (final f in Directory(root).listSync(recursive: true)) {
      if (f is File &&
          f.path.endsWith('app_ar.arb') &&
          !f.path.contains('.dart_tool') &&
          !f.path.contains('/lib/arb/')) {
        out.add(f);
      }
    }
  }
  return out;
}

/// Messages whose count really can be 0 on screen (an empty log, a rating
/// nobody has voted on): English and Arabic both need an explicit `=0` clause
/// so zero never reads as "0 entries" or falls into the wrong plural.
const _countCanBeZero = {'diagCapturing', 'sonarrDetailRatingValue'};

void main() {
  test('the scan finds the plural keys it is meant to check', () {
    expect(_arabicArbs().length, greaterThan(5));
    expect(pluralForms('{n, plural, =1{a} few{b {n}} other{{n} c}}').single, {
      '=1',
      'few',
      'other',
    });
  });

  test('every Arabic plural has few, many and other, and the forms its '
      'English counterpart needs', () {
    final problems = <String>[];
    for (final ar in _arabicArbs()) {
      final en = File(ar.path.replaceFirst('app_ar.arb', 'app_en.arb'));
      final arb = jsonDecode(ar.readAsStringSync()) as Map<String, dynamic>;
      final enArb = en.existsSync()
          ? jsonDecode(en.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
      for (final e in arb.entries) {
        final v = e.value;
        if (e.key.startsWith('@') || v is! String) continue;
        final arForms = pluralForms(v);
        for (var i = 0; i < arForms.length; i++) {
          final f = arForms[i];
          final where = '${ar.path}: ${e.key}';
          for (final w in ['few', 'many', 'other']) {
            if (!f.contains(w)) problems.add('$where lacks $w');
          }
          final enV = enArb[e.key];
          final enForms = enV is String ? pluralForms(enV) : const [];
          final enF = i < enForms.length ? enForms[i] : <String>{};
          // English has one/=1 when the count can be 1 (then 2 matters too).
          if (_has(enF, 'one', '=1')) {
            if (!_has(f, 'one', '=1')) problems.add('$where lacks one/=1');
            if (!_has(f, 'two', '=2')) problems.add('$where lacks two/=2');
          }
          if (_countCanBeZero.contains(e.key)) {
            if (!_has(enF, 'zero', '=0')) problems.add('$where: en lacks =0');
            if (!_has(f, 'zero', '=0')) problems.add('$where lacks zero/=0');
          }
          if (_has(enF, 'zero', '=0') && !_has(f, 'zero', '=0')) {
            problems.add('$where lacks zero/=0');
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
