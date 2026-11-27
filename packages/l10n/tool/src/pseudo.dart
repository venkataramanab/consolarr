// SPDX-License-Identifier: GPL-3.0-or-later

/// Generates the `en_XA` pseudo-locale from English messages.
///
/// Letters are replaced by accented look-alikes and text is padded so strings
/// are about 40% longer, exposing truncation and hard-coded layouts. ICU
/// placeholders, plural and select syntax are preserved. Never hand-edit the
/// generated ARB; change this script instead.
library;

const _lower = 'àƀçðéƒĝĥîĵķļɱñöþǫŕšţüṽŵẋýž';
const _upper = 'ÀßÇÐÉƑĜĤÎĴĶĻṀÑÖÞǪŔŠŢÜṼŴẊÝŽ';

/// Expansion factor applied to each literal run.
const double pseudoExpansion = 0.4;

String _accent(String literal) {
  final out = StringBuffer();
  for (final rune in literal.runes) {
    final ch = String.fromCharCode(rune);
    if (rune >= 0x61 && rune <= 0x7a) {
      out.write(_lower[rune - 0x61]);
    } else if (rune >= 0x41 && rune <= 0x5a) {
      out.write(_upper[rune - 0x41]);
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

String _padded(String literal) {
  if (literal.trim().isEmpty) return literal;
  final pad = (literal.runes.length * pseudoExpansion).ceil();
  return '${_accent(literal)}${'~' * pad}';
}

/// Pseudo-localizes one ICU [message].
String pseudoLocalize(String message) {
  final parser = _Parser(message);
  final body = parser.parseMessage();
  return parser.sawComplex ? body : '[$body]';
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;
  bool sawComplex = false;

  /// Parses literal text and `{...}` expressions until end of input or an
  /// unmatched `}` (when inside a plural/select clause).
  String parseMessage({bool inClause = false}) {
    final out = StringBuffer();
    final literal = StringBuffer();
    void flush() {
      if (literal.isNotEmpty) {
        out.write(_padded(literal.toString()));
        literal.clear();
      }
    }

    while (i < s.length) {
      final c = s[i];
      if (c == '}' && inClause) break;
      if (c == '{') {
        flush();
        out.write(_parseExpression());
        continue;
      }
      literal.write(c);
      i++;
    }
    flush();
    return out.toString();
  }

  String _parseExpression() {
    // s[i] == '{'
    final start = i;
    i++;
    final nameEnd = _indexOfAny(const [',', '}']);
    final name = s.substring(i, nameEnd);
    if (s[nameEnd] == '}') {
      i = nameEnd + 1;
      return s.substring(start, i); // simple placeholder
    }
    // Complex: {name, plural|select|selectordinal, clauses...}
    sawComplex = true;
    final typeEnd = _indexOf(',', nameEnd + 1);
    final type = s.substring(nameEnd + 1, typeEnd).trim();
    final out = StringBuffer('{$name,$type,');
    i = typeEnd + 1;
    while (i < s.length && s[i] != '}') {
      final ws = StringBuffer();
      while (i < s.length && s[i] == ' ') {
        ws.write(' ');
        i++;
      }
      final selStart = i;
      while (i < s.length && s[i] != '{') {
        i++;
      }
      final selector = s.substring(selStart, i);
      i++; // consume '{'
      final inner = parseMessage(inClause: true);
      i++; // consume '}'
      out.write('$ws$selector{$inner}');
    }
    i++; // consume closing '}'
    out.write('}');
    return out.toString();
  }

  int _indexOf(String ch, int from) {
    final idx = s.indexOf(ch, from);
    if (idx < 0) throw FormatException('Unterminated ICU message: $s');
    return idx;
  }

  int _indexOfAny(List<String> chars) {
    for (var k = i; k < s.length; k++) {
      if (chars.contains(s[k])) return k;
    }
    throw FormatException('Unterminated ICU message: $s');
  }
}
