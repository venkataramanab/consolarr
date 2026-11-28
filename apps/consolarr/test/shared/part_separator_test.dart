// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

void main() {
  test(
    'R2: joinParts uses the localized separator, in both languages',
    () async {
      for (final locale in const [
        Locale('en'),
        Locale('ar'),
        Locale('en', 'XA'),
      ]) {
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(l10n.sharedPartSeparator, isNotEmpty);
        expect(
          joinParts(l10n, ['a', 'b', 'c']),
          'a${l10n.sharedPartSeparator}b'
          '${l10n.sharedPartSeparator}c',
        );
        expect(joinParts(l10n, ['only']), 'only');
        expect(joinParts(l10n, const []), '');
      }
    },
  );

  test('R2: no hardcoded separator or bullet in the Sonarr, Radarr and '
      'torrent screens', () {
    final bad = RegExp(r"""['"] [·•–—|/] ['"]|const (_?dot) = """);
    final hits = <String>[];
    for (final feature in ['sonarr', 'radarr', 'torrents']) {
      for (final f in Directory(
        'lib/features/$feature',
      ).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (bad.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
