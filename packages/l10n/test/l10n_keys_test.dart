// SPDX-License-Identifier: GPL-3.0-or-later

// Key hygiene for the localization pipeline:
//  * every key has an @description,
//  * no missing or extra keys between locales,
//  * every key is used through a real accessor in source code (no dead
//    strings; see tool/src/unused_keys.dart and its self-tests),
//  * merged/generated ARB files are in sync with the per-feature sources,
//    so the pseudo-locale can never be hand-edited.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/merge.dart';
import '../tool/src/unused_keys.dart';

Directory findRepoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: consolarr_workspace')) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) fail('Repository root not found');
    dir = parent;
  }
}

Set<String> keysOf(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final root = findRepoRoot();
  final features = featureL10nDirs(root);

  test('at least one feature provides localizations', () {
    expect(features, isNotEmpty);
  });

  group('per-feature ARB files', () {
    for (final dir in features) {
      final feature = dir.parent.path.split('/').last;

      test('$feature: same keys in every source locale', () {
        final en = keysOf(readArb(File('${dir.path}/app_en.arb')));
        for (final locale in sourceLocales.where((l) => l != 'en')) {
          final keys = keysOf(readArb(File('${dir.path}/app_$locale.arb')));
          expect(
            en.difference(keys),
            isEmpty,
            reason: '$feature: keys missing in $locale',
          );
          expect(
            keys.difference(en),
            isEmpty,
            reason: '$feature: extra keys in $locale',
          );
        }
      });

      test('$feature: every key has a non-empty @description', () {
        final arb = readArb(File('${dir.path}/app_en.arb'));
        for (final key in keysOf(arb)) {
          final meta = arb['@$key'];
          expect(meta, isA<Map<String, Object?>>(), reason: '@$key missing');
          final description = (meta! as Map<String, Object?>)['description'];
          expect(
            description,
            isA<String>().having((s) => s.trim(), 'trimmed', isNotEmpty),
            reason: '@$key needs a description',
          );
        }
      });

      test('$feature: every key has a @description in every locale', () {
        for (final locale in sourceLocales) {
          final arb = readArb(File('${dir.path}/app_$locale.arb'));
          for (final key in keysOf(arb)) {
            final meta = arb['@$key'];
            final description = meta is Map<String, Object?>
                ? meta['description']
                : null;
            expect(
              description,
              isA<String>().having((s) => s.trim(), 'trimmed', isNotEmpty),
              reason: '$feature/app_$locale.arb: @$key needs a description',
            );
          }
        }
      });

      test('$feature: placeholders match across locales', () {
        final en = readArb(File('${dir.path}/app_en.arb'));
        for (final locale in sourceLocales.where((l) => l != 'en')) {
          final other = readArb(File('${dir.path}/app_$locale.arb'));
          for (final key in keysOf(en)) {
            final a = placeholdersOf(en['@$key']);
            final b = placeholdersOf(other['@$key']);
            expect(b, a, reason: '$feature/$key placeholders in $locale');
          }
        }
      });
    }
  });

  test('keys are unique across features', () {
    // mergeFeatureArbs throws on duplicates.
    expect(() => mergeFeatureArbs(root), returnsNormally);
  });

  test('no unused keys: every key is referenced in source code', () {
    final merged = mergeFeatureArbs(root)['en']!;
    final sources = <String>[];
    for (final top in ['apps', 'packages']) {
      for (final entity in Directory(
        '${root.path}/$top',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final p = entity.path;
        if (p.contains('/lib/src/generated/') ||
            p.contains('/test/') ||
            p.contains('/.dart_tool/') ||
            p.contains('/build/')) {
          continue;
        }
        sources.add(entity.readAsStringSync());
      }
    }
    final unused = findUnusedKeys(keysOf(merged), sources).toSet();
    final reserved = _reservedKeys(root);
    expect(
      unused.difference(reserved),
      isEmpty,
      reason: 'Unused localization keys: ${unused.difference(reserved)}',
    );
    expect(
      reserved.difference(keysOf(merged)),
      isEmpty,
      reason: 'reserved_keys.txt names keys that do not exist',
    );
    expect(
      reserved.difference(unused),
      isEmpty,
      reason:
          'These reserved keys are in use now: remove them from '
          'apps/consolarr/lib/shared/l10n/reserved_keys.txt',
    );
  });

  group('generated files', () {
    final arbDir = '${root.path}/packages/l10n/lib/arb';

    test('merged ARB files match the feature sources (run melos run l10n)', () {
      final merged = mergeFeatureArbs(root);
      for (final e in merged.entries) {
        final file = File('$arbDir/app_${e.key}.arb');
        expect(file.existsSync(), isTrue, reason: '${file.path} missing');
        expect(
          file.readAsStringSync(),
          encodeArb(e.value),
          reason:
              'app_${e.key}.arb is stale or hand-edited; run '
              '`melos run l10n`',
        );
      }
    });

    test('pseudo-locale has exactly the English keys and descriptions', () {
      final en = readArb(File('$arbDir/app_en.arb'));
      final xa = readArb(File('$arbDir/app_en_XA.arb'));
      expect(keysOf(xa), keysOf(en));
      for (final key in keysOf(en)) {
        expect(xa['@$key'], en['@$key']);
      }
    });
  });
}

/// Keys declared ahead of use (see `reserved_keys.txt`).
Set<String> _reservedKeys(Directory root) {
  final file = File(
    '${root.path}/apps/consolarr/lib/shared/l10n/reserved_keys.txt',
  );
  if (!file.existsSync()) return {};
  return {
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
        line.trim(),
  };
}

Set<String> placeholdersOf(Object? meta) {
  if (meta is! Map<String, Object?>) return {};
  final p = meta['placeholders'];
  return p is Map<String, Object?> ? p.keys.toSet() : {};
}
