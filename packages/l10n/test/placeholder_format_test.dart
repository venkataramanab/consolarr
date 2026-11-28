// SPDX-License-Identifier: GPL-3.0-or-later

// One numeral system per locale. An int/num placeholder without a `format`
// renders through Dart's `toString` (Western digits even in `ar`), while dates
// and formatted counts follow the locale (Arabic-Indic digits in `ar`). Every
// numeric placeholder therefore declares a format so all of them localize.
// Values where grouping would change the meaning (ports, ids, resolutions) are
// String placeholders filled through `AppLocalizations.plainInt`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/merge.dart';
import 'l10n_keys_test.dart' show findRepoRoot;

void main() {
  final root = findRepoRoot();
  for (final dir in featureL10nDirs(root)) {
    final feature = dir.parent.path.split('/').last;
    for (final locale in sourceLocales) {
      test('$feature/$locale: int and num placeholders declare a format', () {
        final arb = readArb(File('${dir.path}/app_$locale.arb'));
        final missing = <String>[];
        for (final e in arb.entries) {
          if (!e.key.startsWith('@') || e.value is! Map<String, Object?>) {
            continue;
          }
          final placeholders =
              (e.value! as Map<String, Object?>)['placeholders'];
          if (placeholders is! Map<String, Object?>) continue;
          for (final p in placeholders.entries) {
            final meta = p.value! as Map<String, Object?>;
            final type = meta['type'];
            if ((type == 'int' || type == 'num') &&
                (meta['format'] as String?)?.isNotEmpty != true) {
              missing.add('${e.key}.${p.key}');
            }
          }
        }
        expect(missing, isEmpty);
      });
    }
  }
}
