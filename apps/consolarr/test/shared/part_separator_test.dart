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

  test('R2: no hardcoded separator or bullet in any feature screen', () {
    // A separator or bullet character in code (a string or a join) must come
    // from the ARB (`sharedPartSeparator`). `home` is excluded: PR #10 deletes
    // that screen.
    final bad = RegExp(r"""['"] [·•–—|/] ['"]|const (_?dot) = |·""");
    final hits = <String>[];
    for (final dir in Directory('lib/features').listSync()) {
      if (dir is! Directory) continue;
      final name = dir.path.split(Platform.pathSeparator).last;
      if (name == 'home') continue;
      for (final f in dir.listSync(recursive: true)) {
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

  test('the guard itself flags the separators it is meant to', () {
    final bad = RegExp(r"""['"] [·•–—|/] ['"]|const (_?dot) = |·""");
    for (final planted in [
      ".join(' · ')",
      "'\${a} · \${b}'",
      "const _dot = '.';",
    ]) {
      expect(bad.hasMatch(planted), isTrue, reason: planted);
    }
  });
}
