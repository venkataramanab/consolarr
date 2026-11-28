// SPDX-License-Identifier: GPL-3.0-or-later

// Every host the app can open on a tap must be named in the privacy
// statement (en, ar) and in README.md. A new external host without that
// update fails here.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = '../..';

// First strong isolate and pop directional isolate, built from code points.
final _fsi = String.fromCharCode(0x2068);
final _pdi = String.fromCharCode(0x2069);

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
  // `Uri(scheme: 'https', host: 'h')` and `Uri.http('h', ...)`.
  final ctor = RegExp(r'''host\s*:\s*['"]([^'"$]+)['"]''');
  final http = RegExp(r'''Uri\.http\(\s*['"]([^'"$]+)['"]''');
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
          for (final m in ctor.allMatches(line)) {
            found.add(m.group(1)!);
          }
          for (final m in http.allMatches(line)) {
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

/// Hosts that are not a plain literal: `Uri.https(x`, `Uri.http(x`,
/// `Uri(scheme: .., host: x)` and `Uri.parse('https://$x')`. A host taken from
/// `ExternalHosts` is fine. Matched over the whole source, so line breaks do
/// not hide a call.
final _dynamicHost = RegExp(
  r'''Uri\.https?\(\s*(?!ExternalHosts\.)[^'"\s)]'''
  r'''|Uri\(\s*[^;)]*?\bhost\s*:\s*(?!ExternalHosts\.)[^'"\s,)]'''
  r'''|Uri\.parse\(\s*['"]https?://\$''',
);

/// Files that build a `Uri` from a variable host, with why that is fine. Each
/// is one construction. Nothing else in `lib/` may.
const _dynamicHostAllowlist = {
  // Same server, another path: an image request, never opened externally.
  'packages/arr_api/lib/src/arr_client_base.dart',
  // The user's own qBittorrent origin for a CSRF header, never opened.
  'packages/torrent_clients/lib/src/qbittorrent_client.dart',
  // The pre-filled issue; the launchers refuse any host off the list.
  'packages/observability/lib/src/diagnostics.dart',
};

void main() {
  test('the scan catches constructor, Uri.http and interpolated hosts', () {
    expect(_dynamicHost.hasMatch('Uri.https(host, "/x")'), isTrue);
    expect(_dynamicHost.hasMatch('Uri.http(h, "/x")'), isTrue);
    expect(_dynamicHost.hasMatch("Uri(scheme: 'https', host: h)"), isTrue);
    expect(
      _dynamicHost.hasMatch("Uri(\n  scheme: 'https',\n  host: h,\n)"),
      isTrue,
    );
    expect(_dynamicHost.hasMatch(r"Uri.parse('https://$h/x')"), isTrue);
    expect(_dynamicHost.hasMatch(r"Uri.parse('https://${h}/x')"), isTrue);
    expect(_dynamicHost.hasMatch('UrlLink(host: uri.host)'), isFalse);
    expect(
      _dynamicHost.hasMatch('Uri.https(ExternalHosts.github, "/x")'),
      isFalse,
    );
    expect(_dynamicHost.hasMatch("Uri.https('github.com', '/x')"), isFalse);
  });

  test('source scan: no host in lib/ comes from anything but the list', () {
    final offenders = <String>[];
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
          final code = f.readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
          if (_dynamicHostAllowlist.any((a) => path.endsWith(a))) continue;
          for (final m in _dynamicHost.allMatches(code)) {
            offenders.add(
              '$path: ${m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}',
            );
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

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
      expect(ar, contains('$_fsi$host$_pdi'), reason: host);
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
