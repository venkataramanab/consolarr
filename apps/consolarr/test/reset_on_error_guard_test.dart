// SPDX-License-Identifier: GPL-3.0-or-later

// `resetOnError: true` makes the plugin delete every key and secret when a
// cipher error occurs. It is allowed in exactly one place, the user-confirmed
// "Reset secure storage" path, and nowhere else in `lib/`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _resetOnErrorTrue = RegExp(r'resetOnError\s*:\s*(?!false\b)[^,)\s]+');

String _withoutComments(String source) =>
    source.replaceAll(RegExp(r'//[^\n]*'), '');

/// Lines in [source] that set `resetOnError` to anything but a literal false.
List<String> riskyResetOnError(String source) {
  final code = _withoutComments(source);
  return [
    for (final m in _resetOnErrorTrue.allMatches(code))
      '${'\n'.allMatches(code.substring(0, m.start)).length + 1}: ${m.group(0)}',
  ];
}

void main() {
  test('the matcher flags true and non-literal values, not false', () {
    expect(riskyResetOnError('AndroidOptions(resetOnError: false)'), isEmpty);
    expect(
      riskyResetOnError('AndroidOptions(resetOnError: true)'),
      hasLength(1),
    );
    expect(
      riskyResetOnError('AndroidOptions(resetOnError:true)'),
      hasLength(1),
    );
    expect(
      riskyResetOnError('AndroidOptions(resetOnError: flag)'),
      hasLength(1),
    );
  });

  test('resetOnError is only enabled in the confirmed reset path', () {
    final roots = [Directory('lib'), Directory('../../packages')];
    final hits = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final f in root.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/test/')) continue;
        for (final h in riskyResetOnError(f.readAsStringSync())) {
          hits.add('${f.path}:$h');
        }
      }
    }
    expect(hits, [
      'lib/src/storage/flutter_secure_secret_store.dart:${_expectedLine()}',
    ]);
  });
}

String _expectedLine() {
  final src = File('lib/src/storage/flutter_secure_secret_store.dart')
      .readAsStringSync();
  return riskyResetOnError(src).single;
}
