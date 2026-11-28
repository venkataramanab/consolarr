// SPDX-License-Identifier: GPL-3.0-or-later

// Every host the app can open on a tap must be named in the privacy
// statement (en, ar) and in README.md. A new external host without that
// update fails here.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = '../..';

String _arb(String locale) {
  final json = jsonDecode(
    File('$_root/apps/consolarr/lib/features/settings/l10n/app_$locale.arb')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  return json['aboutPrivacyBody']! as String;
}

/// Hosts written as literals in `lib/` code: `Uri.https('host'` and
/// `https://host`. The constants file and comments are not counted.
Set<String> _literalHosts() {
  final found = <String>{};
  final call = RegExp(r'''Uri\.https\(\s*['"]([^'"]+)['"]''');
  final url = RegExp(r'''https?://([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,})''');
  for (final top in ['apps', 'packages']) {
    for (final entity in Directory('$_root/$top').listSync()) {
      final lib = Directory('${entity.path}/lib');
      if (!lib.existsSync()) continue;
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        final path = f.path;
        if (!path.endsWith('.dart') ||
            path.contains('/generated/') ||
            path.endsWith('.g.dart') ||
            path.endsWith('external_hosts.dart') ||
            path.contains('/packages/test_harness/')) {
          continue;
        }
        for (final line in f.readAsLinesSync()) {
          final code = line.trimLeft();
          if (code.startsWith('//')) continue;
          for (final m in call.allMatches(line)) {
            found.add(m.group(1)!);
          }
          for (final m in url.allMatches(line)) {
            found.add(m.group(1)!);
          }
        }
      }
    }
  }
  return found;
}

void main() {
  test('the host list is not empty and has no duplicates', () {
    expect(ExternalHosts.all, isNotEmpty);
    expect(ExternalHosts.all.toSet(), hasLength(ExternalHosts.all.length));
  });

  test('en, ar and README name every external host', () {
    final readme = File('$_root/README.md').readAsStringSync();
    final en = _arb('en');
    final ar = _arb('ar');
    for (final host in ExternalHosts.all) {
      expect(en, contains(host), reason: 'en statement misses $host');
      expect(ar, contains(host), reason: 'ar statement misses $host');
      expect(readme, contains(host), reason: 'README misses $host');
    }
  });

  test('the Arabic statement isolates Latin hosts (FSI..PDI)', () {
    final ar = _arb('ar');
    for (final host in ExternalHosts.all) {
      expect(ar, contains('⁨$host⁩'), reason: host);
    }
  });

  test('source scan: literal hosts in lib/ are all in the list', () {
    final literals = _literalHosts();
    final known = ExternalHosts.all.toSet();
    final unknown = literals.difference(known);
    expect(
      unknown,
      isEmpty,
      reason:
          'External hosts written inline: $unknown. Add them to '
          'ExternalHosts and to the privacy statements and README.',
    );
  });
}
