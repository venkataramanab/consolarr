// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/features/about/app_info.dart';
import 'package:consolarr/features/about/source_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version constants equal pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(
      r'^version:\s*(\S+)\+(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(appVersion, m[1]);
    expect(appBuild, m[2]);
  });

  test('the source link is the one public https repository address', () {
    expect(sourceRepositoryUri.scheme, 'https');
    expect(sourceRepositoryUri.host, 'github.com');
    expect(sourceRepositoryUri.userInfo, isEmpty);
    expect(sourceRepositoryUri.hasQuery, isFalse);
    // The single source of the address: nothing else in the app hard-codes it.
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('source_link.dart') &&
            f.readAsStringSync().contains('github.com/'))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
