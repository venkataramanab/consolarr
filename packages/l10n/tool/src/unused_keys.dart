// SPDX-License-Identifier: GPL-3.0-or-later

/// Finds localization keys that no source file uses.
///
/// Only real accessor usage counts: `l10n.<key>` (which also covers
/// `context.l10n.<key>`) and `AppLocalizations.of(...).<key>` (with optional
/// `!`). Comments and the literal text of strings are removed first, so a key
/// mentioned in documentation or inside a string never keeps a dead key alive;
/// code inside `${...}` interpolations is kept.
library;

/// Keys from [keys] that are not accessed in any of [sources], sorted.
List<String> findUnusedKeys(Set<String> keys, Iterable<String> sources) {
  final code = sources.map(stripCommentsAndStrings).join('\n');
  final unused = [
    for (final key in keys)
      if (!_accessor(key).hasMatch(code)) key,
  ]..sort();
  return unused;
}

RegExp _accessor(String key) => RegExp(
  r'(?:\bl10n|\bAppLocalizations\s*\.\s*of\s*\((?:[^()]|\([^()]*\))*\)\s*!?)'
  '\\s*\\.\\s*${RegExp.escape(key)}\\b',
);

/// Dart source with comments removed and string literals emptied (their
/// interpolated expressions are kept).
String stripCommentsAndStrings(String source) => _Stripper(source).run();

class _Stripper {
  _Stripper(this.s);

  final String s;
  final out = StringBuffer();
  int i = 0;

  String run() {
    _code(inInterpolation: false);
    return out.toString();
  }

  bool _isIdent(String ch) => RegExp(r'[A-Za-z0-9_$]').hasMatch(ch);

  /// Scans code. When [inInterpolation], returns at the unmatched `}` (not
  /// consumed).
  void _code({required bool inInterpolation}) {
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (c == '/' && next == '/') {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/' && next == '*') {
        var nesting = 1;
        i += 2;
        while (i < s.length && nesting > 0) {
          if (s.startsWith('/*', i)) {
            nesting++;
            i += 2;
          } else if (s.startsWith('*/', i)) {
            nesting--;
            i += 2;
          } else {
            i++;
          }
        }
        continue;
      }
      if (c == "'" || c == '"') {
        _string(raw: false);
        continue;
      }
      if (c == 'r' &&
          (next == "'" || next == '"') &&
          (i == 0 || !_isIdent(s[i - 1]))) {
        i++;
        _string(raw: true);
        continue;
      }
      if (inInterpolation) {
        if (c == '{') depth++;
        if (c == '}') {
          if (depth == 0) return;
          depth--;
        }
      }
      out.write(c);
      i++;
    }
  }

  void _string({required bool raw}) {
    final q = s[i];
    final triple = s.startsWith(q * 3, i);
    i += triple ? 3 : 1;
    out.write("''");
    while (i < s.length) {
      final c = s[i];
      if (triple ? s.startsWith(q * 3, i) : c == q) {
        i += triple ? 3 : 1;
        return;
      }
      if (!raw && c == r'\') {
        i += 2;
        continue;
      }
      if (!raw && c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
        i += 2;
        out.write(' ');
        _code(inInterpolation: true);
        out.write(' ');
        if (i < s.length) i++; // closing brace
        continue;
      }
      if (!triple && c == '\n') return; // unterminated; recover
      i++;
    }
  }
}
