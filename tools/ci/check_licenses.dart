// SPDX-License-Identifier: GPL-3.0-or-later

// Verifies that every hosted dependency in pubspec.lock is licensed under
// terms compatible with distributing a GPL-3.0-or-later combined work.
//
// Usage: dart run tools/ci/check_licenses.dart [pubspec.lock]
//
// The licence is detected from the LICENSE file in the local pub cache.
// Unknown licences fail the check; resolve by reviewing the package and
// adding it to tools/ci/license_overrides.txt (one `name  SPDX-id` per line).
// AGPL, GPL-2.0-only and LGPL-2.1 texts are detected as such and rejected.
// Self-test: dart run tools/ci/check_licenses_selftest.dart

import 'dart:io';

/// Licences compatible with GPL-3.0-or-later (permissive or GPL-compatible).
const _compatible = {
  'BSD-3-Clause',
  'BSD-2-Clause',
  'MIT',
  'Apache-2.0',
  'ISC',
  'Zlib',
  'MPL-2.0',
  'Unlicense',
  'CC0-1.0',
  'LGPL-3.0',
  'GPL-3.0',
  'GPL-3.0-or-later',
};

String? detect(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (t.contains('apache license') && t.contains('version 2.0')) {
    return 'Apache-2.0';
  }
  if (t.contains('mozilla public license') && t.contains('2.0')) {
    return 'MPL-2.0';
  }
  // The AGPL text quotes the GPL, so test for it (and the LGPL) first.
  if (t.contains('gnu affero general public license')) {
    final v3 = t.contains('version 3');
    return v3 ? 'AGPL-3.0' : 'AGPL';
  }
  if (t.contains('gnu lesser general public license')) {
    if (t.contains('version 3')) return 'LGPL-3.0';
    if (t.contains('version 2.1')) return 'LGPL-2.1';
    return 'LGPL';
  }
  if (t.contains('gnu general public license')) {
    if (t.contains('version 3')) return 'GPL-3.0';
    if (t.contains('version 2')) return 'GPL-2.0';
    return 'GPL';
  }
  if (t.contains('permission is hereby granted, free of charge')) return 'MIT';
  if (t.contains(
    'this is free and unencumbered software released into the '
    'public domain',
  )) {
    return 'Unlicense';
  }
  if (t.contains(
    'permission to use, copy, modify, and/or distribute this '
    'software for any purpose with or without fee',
  )) {
    return 'ISC';
  }
  if (t.contains('redistribution and use in source and binary forms')) {
    final clauses = RegExp(
      r'neither the name|the names of|may not be used to endorse|endorse or promote',
    ).hasMatch(t);
    return clauses ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (t.contains(
    'permission is granted to anyone to use this software for '
    'any purpose',
  )) {
    return 'Zlib';
  }
  return null;
}

Map<String, String> readOverrides() {
  final f = File('tools/ci/license_overrides.txt');
  if (!f.existsSync()) return {};
  final out = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final l = line.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final parts = l.split(RegExp(r'\s+'));
    if (parts.length >= 2) out[parts[0]] = parts[1];
  }
  return out;
}

Future<void> main(List<String> args) async {
  final lockFile = File(args.isNotEmpty ? args.first : 'pubspec.lock');
  final lock = lockFile.readAsStringSync();
  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final overrides = readOverrides();

  // Entries look like:
  //   name:
  //     ...
  //     description:
  //       name: name
  //       url: "https://pub.dev"
  //     source: hosted
  //     version: "1.2.3"
  final entry = RegExp(
    r'^  ([a-z0-9_]+):\n((?:    .*\n|\n)+)',
    multiLine: true,
  );
  final failures = <String>[];
  var checked = 0;
  for (final m in entry.allMatches(lock)) {
    final name = m.group(1)!;
    final body = m.group(2)!;
    if (!body.contains('source: hosted')) continue; // sdk / path packages
    final version = RegExp(r'version: "([^"]+)"').firstMatch(body)!.group(1)!;
    final host = RegExp(r'url: "https?://([^/"]+)').firstMatch(body)?.group(1);
    final dir = Directory(
      '$pubCache/hosted/${host ?? 'pub.dev'}/$name-$version',
    );
    String? id = overrides[name];
    if (id == null) {
      if (!dir.existsSync()) {
        failures.add('$name $version: not in pub cache (run pub get first)');
        continue;
      }
      final licenseFile = dir.listSync().whereType<File>().where((f) {
        final base = f.uri.pathSegments.last.toLowerCase();
        return base.startsWith('license') || base.startsWith('copying');
      }).firstOrNull;
      if (licenseFile == null) {
        failures.add('$name $version: no LICENSE file');
        continue;
      }
      id = detect(licenseFile.readAsStringSync());
    }
    checked++;
    if (id == null) {
      failures.add('$name $version: licence not recognised');
    } else if (!_compatible.contains(id)) {
      failures.add('$name $version: $id is not GPL-3.0-or-later compatible');
    }
  }

  stdout.writeln('Licence check: $checked hosted packages checked.');
  if (failures.isNotEmpty) {
    stderr.writeln('Licence problems:\n  ${failures.join('\n  ')}');
    exit(1);
  }
}
