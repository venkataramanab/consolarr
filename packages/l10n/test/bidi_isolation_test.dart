// SPDX-License-Identifier: GPL-3.0-or-later

// Arabic strings embed Latin or user-supplied text (titles, hosts, versions,
// file names, units). Without isolation the Unicode bidi algorithm lets that
// text pull the punctuation and digits around it into the wrong visual place.
// The convention (docs/patterns.md, section 9): in `app_ar.arb` every
// `{placeholder}` of type String is written as FSI `{p}` PDI, so translators
// keep control of where the isolate sits. This test checks that mechanically
// from the placeholder metadata of the English template.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

import '../tool/src/merge.dart';
import 'l10n_keys_test.dart' show findRepoRoot;

const _fsi = '⁨';
const _pdi = '⁩';
// Openers accepted before a String placeholder: FSI, LRI, RLI.
const _openers = {'⁨', '⁦', '⁧'};

/// Keys whose text is owned by another workstream; they are checked once the
/// owner has finished (see the W6b hand-off in docs/patterns.md).
bool _exempt(String key) =>
    key.startsWith('about') || key.startsWith('privacy');

Set<String> _stringPlaceholders(Object? meta) {
  if (meta is! Map<String, Object?>) return {};
  final p = meta['placeholders'];
  if (p is! Map<String, Object?>) return {};
  return {
    for (final e in p.entries)
      if ((e.value as Map<String, Object?>)['type'] == 'String') e.key,
  };
}

/// Whether [index] sits inside an isolate that is still open there (for
/// example a `host:port` pair wrapped as a whole).
bool _insideIsolate(String message, int index) {
  var depth = 0;
  for (var i = 0; i < index; i++) {
    final c = message[i];
    if (_openers.contains(c)) depth++;
    if (c == _pdi && depth > 0) depth--;
  }
  return depth > 0;
}

void main() {
  final root = findRepoRoot();

  test('isolate() wraps in FSI and PDI', () {
    expect(isolate('Sonarr'), '${_fsi}Sonarr$_pdi');
    expect(isolate(''), '');
  });

  test('isolate() leaves already-isolated text alone', () {
    final once = isolate('v1.2');
    expect(isolate(once), once);
  });

  for (final dir in featureL10nDirs(root)) {
    final feature = dir.parent.path.split('/').last;
    test('$feature: ar String placeholders are isolated', () {
      final en = readArb(File('${dir.path}/app_en.arb'));
      final ar = readArb(File('${dir.path}/app_ar.arb'));
      final problems = <String>[];
      for (final key in en.keys.where((k) => !k.startsWith('@'))) {
        if (_exempt(key)) continue;
        final message = ar[key]! as String;
        for (final p in _stringPlaceholders(en['@$key'])) {
          final pattern = RegExp('\\{$p\\}');
          final hits = pattern.allMatches(message).toList();
          if (hits.isEmpty) problems.add('$key: {$p} missing');
          for (final m in hits) {
            final before = m.start == 0 ? '' : message[m.start - 1];
            final after = m.end >= message.length ? '' : message[m.end];
            final wrapped = _openers.contains(before) && after == _pdi;
            if (!wrapped && !_insideIsolate(message, m.start)) {
              problems.add('$key: {$p} not isolated');
              break;
            }
          }
        }
      }
      expect(problems, isEmpty);
    });
  }
}
