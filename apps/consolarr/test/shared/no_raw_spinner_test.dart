// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Indeterminate progress indicators loop forever and ignore reduce-motion.
/// `BusyIndicator` (design_system) is the only place allowed to build one.
/// A determinate indicator (one with `value:`) does not loop and is fine.
final _constructor = RegExp(
  r'\b(CircularProgressIndicator|LinearProgressIndicator|'
  r'RefreshProgressIndicator|CupertinoActivityIndicator)\s*(\.\w+)?\s*\(',
);

/// The call arguments starting at the `(` at [open], up to its match.
String _arguments(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return source.substring(open, i + 1);
  }
  return source.substring(open);
}

/// Locations of raw indeterminate indicators in [source].
List<int> rawIndeterminate(String source) => [
  for (final m in _constructor.allMatches(source))
    if (!RegExp(r'\bvalue\s*:').hasMatch(_arguments(source, m.end - 1)))
      m.start,
];

void main() {
  test(
    'the detector flags indeterminate and spares determinate indicators',
    () {
      expect(rawIndeterminate('const CircularProgressIndicator()'), isNotEmpty);
      expect(
        rawIndeterminate('LinearProgressIndicator(minHeight: 2)'),
        isNotEmpty,
      );
      expect(rawIndeterminate('CupertinoActivityIndicator()'), isNotEmpty);
      expect(
        rawIndeterminate('CircularProgressIndicator(value: 0.4)'),
        isEmpty,
      );
      expect(rawIndeterminate('BusyIndicator(semanticLabel: null)'), isEmpty);
    },
  );

  test('no raw indeterminate progress indicator outside design_system', () {
    final root = Directory('../..');
    final offenders = <String>[];
    for (final top in ['apps', 'packages']) {
      for (final entity in Directory(
        '${root.path}/$top',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final p = entity.path;
        if (p.contains('/design_system/') ||
            p.contains('/test/') ||
            p.contains('/integration_test/') ||
            p.contains('/.dart_tool/') ||
            p.contains('/build/') ||
            p.contains('/generated/')) {
          continue;
        }
        if (rawIndeterminate(entity.readAsStringSync()).isNotEmpty) {
          offenders.add(p);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'use BusyIndicator from design_system instead',
    );
  });
}
