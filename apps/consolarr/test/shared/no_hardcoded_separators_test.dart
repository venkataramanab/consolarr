// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Punctuation that glues user-facing parts together must come from the
/// localization (`sharedListSeparator`, `sharedPartSeparator`, ... and
/// messages with placeholders), so Arabic gets its own comma and the order of
/// the parts can change. Widget code may not hardcode it.
final _patterns = <String, RegExp>{
  "join(', ') / join('. ') / join(' · ')": RegExp(
    r'''\.join\(\s*['"](, |\. |; | · |: )['"]\s*\)''',
  ),
  'bullet prefix': RegExp(r'''['"]• '''),
  'middle dot or en dash between parts': RegExp(r"""['"]\s?[·–—]\s?['"]"""),
  'comma between interpolations': RegExp(r'\$\{?[\w.!?]+\}?, \$'),
  'value (value) pattern': RegExp(r'\}\)? \(\$\{?[\w.!?]+\}?\)'),
  'part with trailing en dash literal': RegExp(r"""return\s+['"][–—]['"]"""),
};

/// Source files whose strings are not shown to users.
bool _isUiSource(String path) =>
    (path.contains('/presentation/') ||
        path.contains('/shared/widgets/') ||
        path.contains('/shared/l10n/') ||
        path.contains('packages/design_system/lib/')) &&
    !path.endsWith('.g.dart');

List<String> findHardcodedSeparators(String rawSource) {
  // Comments may quote punctuation.
  final source = rawSource.replaceAll(RegExp(r'//.*'), '');
  final hits = <String>[];
  for (final entry in _patterns.entries) {
    for (final m in entry.value.allMatches(source)) {
      final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
      hits.add('${entry.key} (line $line)');
    }
  }
  return hits;
}

void main() {
  test('the detector finds each kind of hardcoded separator', () {
    expect(findHardcodedSeparators("x.join(', ');"), isNotEmpty);
    expect(findHardcodedSeparators("x.join('. ');"), isNotEmpty);
    expect(findHardcodedSeparators("Text('• \$line');"), isNotEmpty);
    expect(findHardcodedSeparators("'\$a, \$b'"), isNotEmpty);
    expect(findHardcodedSeparators("'\${m.title} (\${m.year})'"), isNotEmpty);
    expect(
      findHardcodedSeparators("x.join(l10n.sharedListSeparator);"),
      isEmpty,
    );
    expect(findHardcodedSeparators("x.join('/');"), isEmpty);
  });

  test('widget code hardcodes no separators between user-facing parts', () {
    final offenders = <String>[];
    for (final top in ['apps', 'packages']) {
      for (final e in Directory('../../$top').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final p = e.path;
        // The one design-system file that spells the default marks out.
        if (p.endsWith('/design_system/lib/src/label_separators.dart') ||
            p.contains('/test/') ||
            p.contains('/.dart_tool/') ||
            p.contains('/build/') ||
            !_isUiSource(p)) {
          continue;
        }
        for (final hit in findHardcodedSeparators(e.readAsStringSync())) {
          offenders.add('${p.replaceFirst('../../', '')}: $hit');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use localized separators');
  });
}
