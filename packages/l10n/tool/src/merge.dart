// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'pseudo.dart';

/// Locales shipped as hand-written ARB files per feature.
const sourceLocales = ['en', 'ar'];

/// The generated pseudo-locale (accented, ~40% longer).
const pseudoLocale = 'en_XA';

const _encoder = JsonEncoder.withIndent('  ');

/// l10n source directories: `apps/consolarr/lib/features/<f>/l10n` for each
/// feature, plus `apps/consolarr/lib/shared/l10n` for strings several
/// features use (connection errors, common actions).
List<Directory> featureL10nDirs(Directory repoRoot) {
  final lib = '${repoRoot.path}/apps/consolarr/lib';
  final dirs = <Directory>[];
  for (final f in Directory(
    '$lib/features',
  ).listSync().whereType<Directory>()) {
    final l10n = Directory('${f.path}/l10n');
    if (l10n.existsSync()) dirs.add(l10n);
  }
  final shared = Directory('$lib/shared/l10n');
  if (shared.existsSync()) dirs.add(shared);
  dirs.sort((a, b) => a.path.compareTo(b.path));
  return dirs;
}

Map<String, Object?> readArb(File file) =>
    json.decode(file.readAsStringSync()) as Map<String, Object?>;

/// Merges every feature's `app_<locale>.arb` into one map per locale
/// (including `en_XA`, generated from `en`).
///
/// Throws a [StateError] on duplicate keys across features.
Map<String, Map<String, Object?>> mergeFeatureArbs(Directory repoRoot) {
  final merged = <String, Map<String, Object?>>{
    for (final l in sourceLocales) l: {'@@locale': l},
  };
  final owner = <String, String>{};
  for (final dir in featureL10nDirs(repoRoot)) {
    for (final locale in sourceLocales) {
      final file = File('${dir.path}/app_$locale.arb');
      if (!file.existsSync()) {
        throw StateError('Missing ${file.path}');
      }
      for (final e in readArb(file).entries) {
        if (e.key == '@@locale') continue;
        final isMeta = e.key.startsWith('@');
        if (!isMeta && locale == 'en') {
          final prev = owner[e.key];
          if (prev != null) {
            throw StateError(
              'Duplicate key "${e.key}" in $prev and ${dir.path}',
            );
          }
          owner[e.key] = dir.path;
        }
        merged[locale]![e.key] = e.value;
      }
    }
  }
  merged[pseudoLocale] = pseudoArb(merged['en']!);
  return merged;
}

/// Builds the `en_XA` ARB from the merged English ARB.
Map<String, Object?> pseudoArb(Map<String, Object?> en) {
  final out = <String, Object?>{'@@locale': pseudoLocale};
  for (final e in en.entries) {
    if (e.key == '@@locale') continue;
    if (e.key.startsWith('@')) {
      out[e.key] = e.value;
    } else {
      out[e.key] = pseudoLocalize(e.value! as String);
    }
  }
  return out;
}

/// Canonical serialization of an ARB map.
String encodeArb(Map<String, Object?> arb) => '${_encoder.convert(arb)}\n';
