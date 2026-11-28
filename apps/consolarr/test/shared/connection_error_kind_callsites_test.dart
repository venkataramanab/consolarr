// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sonarr and Radarr reject a login with a 401 whatever the user typed; the
/// copy that says "use the API key" needs the server kind. A call site that
/// forgets `kind:` shows the generic "check the username and password" text
/// for an arr server, so every call inside an arr feature must pass it.
///
/// Features whose servers can be any kind (servers, settings) pass the kind of
/// the server at hand. The torrent features are not arr and are left out.
const _featuresThatMustPassKind = [
  'sonarr',
  'radarr',
  'arr_common',
  'servers',
  'settings',
];

void main() {
  test('every connectionErrorMessage call in an arr feature passes kind:', () {
    final offenders = <String>[];
    var calls = 0;
    for (final feature in _featuresThatMustPassKind) {
      final dir = Directory('lib/features/$feature');
      expect(dir.existsSync(), isTrue, reason: feature);
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final source = f.readAsStringSync();
        for (final m in RegExp(
          r'connectionErrorMessage\(',
        ).allMatches(source)) {
          calls++;
          var depth = 1;
          var i = m.end;
          while (i < source.length && depth > 0) {
            final c = source[i++];
            if (c == '(') depth++;
            if (c == ')') depth--;
          }
          final args = source.substring(m.end, i - 1);
          if (!RegExp(r'\bkind:').hasMatch(args)) {
            final line =
                '\n'.allMatches(source.substring(0, m.start)).length + 1;
            offenders.add('${f.path}:$line');
          }
        }
      }
    }
    expect(calls, greaterThan(10), reason: 'the scan finds the call sites');
    expect(offenders, isEmpty, reason: 'pass kind: at these call sites');
  });
}
