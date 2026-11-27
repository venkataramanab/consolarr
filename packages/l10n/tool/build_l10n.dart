// SPDX-License-Identifier: GPL-3.0-or-later

// Merges per-feature ARB files into packages/l10n, generates the en_XA
// pseudo-locale and runs `flutter gen-l10n`.
//
// Usage: dart run packages/l10n/tool/build_l10n.dart

import 'dart:io';

import 'src/merge.dart';

Future<void> main() async {
  // This script lives at <root>/packages/l10n/tool/build_l10n.dart.
  final script = File.fromUri(Platform.script);
  final l10nPackage = script.parent.parent;
  final root = l10nPackage.parent.parent;

  final merged = mergeFeatureArbs(root);
  final arbDir = Directory('${l10nPackage.path}/lib/arb');
  if (arbDir.existsSync()) arbDir.deleteSync(recursive: true);
  arbDir.createSync(recursive: true);
  for (final e in merged.entries) {
    File('${arbDir.path}/app_${e.key}.arb')
        .writeAsStringSync(encodeArb(e.value));
  }

  final outDir = Directory('${l10nPackage.path}/lib/src/generated');
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);

  final gen = await Process.run('flutter', [
    'gen-l10n',
  ], workingDirectory: l10nPackage.path);
  stdout.write(gen.stdout);
  stderr.write(gen.stderr);
  if (gen.exitCode != 0) exit(gen.exitCode);

  final fmt = await Process.run('dart', ['format', outDir.path]);
  stderr.write(fmt.stderr);
  if (fmt.exitCode != 0) exit(fmt.exitCode);
  stdout.writeln('l10n: ${merged.keys.join(', ')} generated.');
}
