// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/features/settings/domain/privacy_payload.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

/// Event names declared in an events YAML (the keys under `events:`).
Set<String> _events(String path) {
  final lines = File(path).readAsLinesSync();
  final out = <String>{};
  var inEvents = false;
  for (final line in lines) {
    if (line.startsWith('events:')) {
      inEvents = true;
      continue;
    }
    if (!inEvents) continue;
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      inEvents = false;
      continue;
    }
    final m = RegExp(r'^  ([a-z][a-z0-9_]*):\s*$').firstMatch(line);
    if (m != null) out.add(m[1]!);
  }
  return out;
}

void main() {
  const events = '../../packages/observability/events';

  test('every catalog event has a description, and no description is '
      'stale (all areas)', () {
    final declared = <String>{
      for (final f in Directory(events).listSync())
        if (f is File && f.path.endsWith('.yaml')) ..._events(f.path),
    };
    expect(declared, hasLength(greaterThanOrEqualTo(25)));
    expect(privacyPayloadItems.keys.toSet(), declared);
  });

  test('every item has distinct copy in every shipped locale', () async {
    for (final locale in const [
      Locale('en'),
      Locale('ar'),
      Locale('en', 'XA'),
    ]) {
      final l10n = await AppLocalizations.delegate.load(locale);
      final texts = {for (final d in privacyPayloadItems.values) d(l10n)};
      expect(texts.length, privacyPayloadItems.length, reason: '$locale');
      expect(texts.every((t) => t.isNotEmpty), isTrue);
    }
  });

  test('the described payload names no free-text field', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final all = privacyPayloadItems.values
        .map((d) => d(l10n))
        .join(' ')
        .toLowerCase();
    for (final bad in ['url', 'address:', 'password', 'api key', 'title:']) {
      expect(all, isNot(contains(bad)));
    }
  });
}
