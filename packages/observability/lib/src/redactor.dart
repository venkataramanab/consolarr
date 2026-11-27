// SPDX-License-Identifier: GPL-3.0-or-later

/// Removes secrets from text, URLs, headers and structured data before it is
/// logged, reported or shared.
///
/// Covers: API keys, `Authorization` / `X-Api-Key` / cookie headers,
/// passwords, tokens, URL credentials (user info) and sensitive query keys.
/// Redaction is idempotent and errs on the side of over-redaction: an
/// unquoted value runs to the end of the line (or the next `&field=` of a
/// form body), and a sensitive key followed by an array or object redacts the
/// whole structure.
///
/// Input longer than [maxInputLength] is truncated (followed by
/// [truncationMarker]) before any pattern runs, which bounds the work done per
/// call. Every pattern below is linear in the input length.
class Redactor {
  const Redactor();

  /// Replacement for every removed secret.
  static const placeholder = '[REDACTED]';

  /// Longest input (in UTF-16 code units) that [redactText] examines.
  static const maxInputLength = 8192;

  /// Appended to input that was cut at [maxInputLength].
  static const truncationMarker = ' ...[TRUNCATED]';

  static const _sensitiveHeaderNames = {
    'authorization',
    'proxy-authorization',
    'x-api-key',
    'x-auth-token',
    'x-transmission-session-id',
    'cookie',
    'set-cookie',
  };

  static final _separators = RegExp(r'[\s_.\-\[\]]');

  /// Whether a header, query, form or JSON key name denotes a secret value.
  ///
  /// Percent-encoded names (`api%5Fkey`) are decoded first, up to three times.
  static bool isSensitiveKey(String key) {
    final k = _decodeKey(key).toLowerCase().replaceAll(_separators, '');
    if (k.isEmpty) return false;
    return k.endsWith('key') ||
        k.endsWith('keys') ||
        k.endsWith('otp') ||
        k == 'pwd' ||
        k == 'pw' ||
        k == 'pass' ||
        k == 'sid' ||
        k.startsWith('qbtsid') || // qBittorrent: QBT_SID_<port>
        k.endsWith('sessionid') || // X-Transmission-Session-Id
        k == 'auth' ||
        k == 'session' ||
        k == 'sessionid' ||
        k == 'cookie' ||
        k.contains('token') ||
        k.contains('password') ||
        k.contains('passwd') ||
        k.contains('passphrase') ||
        k.contains('passcode') ||
        k.contains('secret') ||
        k.contains('credential') ||
        k.contains('authorization') ||
        k.contains('signature') ||
        k.contains('jwt') ||
        k.contains('bearer');
  }

  static String _decodeKey(String key) {
    var k = key;
    for (var i = 0; i < 3 && k.contains('%'); i++) {
      try {
        final decoded = Uri.decodeQueryComponent(k);
        if (decoded == k) break;
        k = decoded;
      } on Object {
        break;
      }
    }
    return k;
  }

  // --- free text -----------------------------------------------------------

  // The lookbehind keeps the scan linear: a scheme can only start at the
  // beginning of a run of scheme characters.
  static final _urlInText = RegExp(
    r'(?<![a-zA-Z0-9+.\-])[a-zA-Z][a-zA-Z0-9+.\-]*://\S+',
  );

  static final _headerLine = RegExp(
    r'\b(authorization|proxy-authorization|x-api-key|x-auth-token|x-transmission-session-id|set-cookie|cookie)([ \t]*[:=][ \t]*)([^\r\n]+)',
    caseSensitive: false,
  );

  /// `X-Custom-Auth-Thing: value`: a dashed header name whose name says secret.
  static final _dashedHeader = RegExp(
    r'(?<![\w\-])([A-Za-z0-9]+(?:-[A-Za-z0-9]+)+)(?![ \t]*:[ \t]*(?:\[REDACTED\]|\w+=))([ \t]*:[ \t]*)([^\r\n]+)',
  );

  static final _scheme = RegExp(
    r'\b(bearer|basic)([ \t]+)(?!\[REDACTED\])[A-Za-z0-9._~+/=%\-]{6,}',
    caseSensitive: false,
  );

  /// A key token followed by `:` or `=`. The lookbehind pins the start to a
  /// token boundary, so the scan is linear (no leading `[\w.-]*` to retry from
  /// every offset). Whether the key is sensitive is decided in code.
  static final _keySep = RegExp(
    '(?<![\\w.\\-%])(\\\\?["\'])?([\\w.\\-%]+)(?:\\\\?["\']|\\])?[ \\t]*[:=][ \\t]*',
  );

  static final _formBoundary = RegExp(r'&[\w.\-%\[\]]+=');

  static final _rpcSensitiveMethod = RegExp(
    '\\\\?"method\\\\?"\\s*:\\s*\\\\?"(?:(?:[\\w\\-]+\\.)*login|auth\\.[\\w.\\-]*)\\\\?"',
    caseSensitive: false,
  );
  static final _rpcMethodName = RegExp(
    r'^(?:(?:[\w\-]+\.)*login|auth\.[\w.\-]*)$',
    caseSensitive: false,
  );
  static final _rpcParams = RegExp('\\\\?"params\\\\?"\\s*:\\s*');

  static final _longHex = RegExp(
    r'(?<![0-9A-Za-z])[0-9a-fA-F]{32,}(?![0-9A-Za-z])',
  );
  static final _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*',
  );

  static final _chunk = RegExp(r'\S+');

  /// Redacts secrets in arbitrary [input] text.
  String redactText(String input) {
    var out = input.length > maxInputLength
        ? '${input.substring(0, maxInputLength)}$truncationMarker'
        : input;
    if (_rpcSensitiveMethod.hasMatch(out)) out = _redactRpcParams(out);
    out = out.replaceAllMapped(_urlInText, (m) => redactUrl(m[0]!));
    out = _redactSchemeLessUserInfo(out);
    out = out.replaceAllMapped(
      _headerLine,
      (m) => '${m[1]}${m[2]}$placeholder',
    );
    out = out.replaceAllMapped(_scheme, (m) => '${m[1]}${m[2]}$placeholder');
    out = out.replaceAllMapped(_dashedHeader, (m) {
      return isSensitiveHeaderName(m[1]!)
          ? '${m[1]}${m[2]}$placeholder'
          : m[0]!;
    });
    out = _redactKeyValues(out);
    out = out.replaceAll(_jwt, placeholder);
    out = out.replaceAll(_longHex, placeholder);
    return out;
  }

  static const _userInfoBoundary = '=(<,"\'[{;';
  static final _userChar = RegExp(r'[\w.\-%+~]');
  static final _hostStart = RegExp(r'[\w\[]');

  /// `user:pass@host` without a scheme: for a whitespace-delimited chunk, the
  /// user info runs from a `user:` token (at the start of the chunk or right
  /// after one of `=(<,"'[{;`) up to the last `@` that precedes a host.
  String _redactSchemeLessUserInfo(String text) {
    return text.replaceAllMapped(_chunk, (m) {
      final chunk = m[0]!;
      if (chunk.contains('://')) return chunk;
      var at = chunk.lastIndexOf('@');
      while (at > 0 && at < chunk.length - 1) {
        if (_hostStart.hasMatch(chunk[at + 1])) break;
        at = chunk.lastIndexOf('@', at - 1);
      }
      if (at <= 0 || at >= chunk.length - 1) return chunk;
      for (var c = chunk.indexOf(':'); c >= 0 && c < at;) {
        var start = c;
        while (start > 0 && _userChar.hasMatch(chunk[start - 1])) {
          start--;
        }
        final bounded =
            start == 0 || _userInfoBoundary.contains(chunk[start - 1]);
        if (start < c && bounded) {
          return '${chunk.substring(0, start)}$placeholder${chunk.substring(at)}';
        }
        c = chunk.indexOf(':', c + 1);
      }
      return chunk;
    });
  }

  String _redactRpcParams(String text) {
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in _rpcParams.allMatches(text)) {
      if (m.start < cursor) continue;
      final v = _scanValue(text, m.end, quotedKey: true);
      if (v == null) continue;
      buf
        ..write(text.substring(cursor, m.end))
        ..write(v.replacement);
      cursor = v.end;
    }
    return (buf..write(text.substring(cursor))).toString();
  }

  String _redactKeyValues(String text) {
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in _keySep.allMatches(text)) {
      if (m.start < cursor) continue;
      if (!isSensitiveKey(m[2]!)) continue;
      final v = _scanValue(text, m.end, quotedKey: m[1] != null);
      if (v == null) continue;
      buf
        ..write(text.substring(cursor, m.end))
        ..write(v.replacement);
      cursor = v.end;
    }
    return (buf..write(text.substring(cursor))).toString();
  }

  static const _afterClosingQuote = ' \t\r\n,;&})]:>';

  /// Finds the value starting at [start]. Returns null when there is nothing
  /// to redact (empty or already redacted).
  ({int end, String replacement})? _scanValue(
    String s,
    int start, {
    required bool quotedKey,
  }) {
    final n = s.length;
    if (start >= n) return null;
    if (s.startsWith(placeholder, start)) {
      final next = start + placeholder.length;
      if (next >= n || '&"\'\r\n,;})]'.contains(s[next])) return null;
    }
    final c = s[start];
    if (c == '\r' || c == '\n') return null;

    // Quoted string, possibly with escaped quotes (`\"...\"`).
    var open = start;
    while (open < n && s[open] == r'\') {
      open++;
    }
    if (open < n && (s[open] == '"' || s[open] == "'")) {
      final q = s[open];
      final escaped = open > start;
      var j = open + 1;
      while (j < n) {
        final ch = s[j];
        if (ch == '\r' || ch == '\n') break;
        if (ch == r'\') {
          if (escaped && j + 1 < n && s[j + 1] == q) {
            final prefix = s.substring(start, open + 1);
            return (
              end: j + 2,
              replacement: '$prefix$placeholder${s.substring(j, j + 2)}',
            );
          }
          j += 2;
          continue;
        }
        if (ch == q && !escaped) {
          final after = j + 1;
          if (after >= n || _afterClosingQuote.contains(s[after])) {
            final prefix = s.substring(start, open + 1);
            return (end: after, replacement: '$prefix$placeholder$q');
          }
        }
        j++;
      }
      // Unterminated: redact to the end of the line.
      final prefix = s.substring(start, open + 1);
      return (end: j < n ? j : n, replacement: '$prefix$placeholder');
    }

    if (c == '[' || c == '{') {
      return (end: _structureEnd(s, start), replacement: placeholder);
    }

    int end;
    if (quotedKey) {
      // JSON-style bare value (number, true, null): ends at a delimiter.
      end = start;
      while (end < n && !' \t\r\n,;&})]"\''.contains(s[end])) {
        end++;
      }
    } else {
      end = s.indexOf(RegExp(r'[\r\n]'), start);
      if (end < 0) end = n;
      final boundary = _formBoundary.firstMatch(s.substring(start, end));
      if (boundary != null) end = start + boundary.start;
    }
    if (end <= start) return null;
    return (end: end, replacement: placeholder);
  }

  /// End (exclusive) of the balanced `[...]` / `{...}` starting at [start];
  /// the end of [s] when it never closes.
  int _structureEnd(String s, int start) {
    var depth = 0;
    var inString = false;
    for (var i = start; i < s.length; i++) {
      final ch = s[i];
      if (ch == r'\') {
        i++;
      } else if (ch == '"') {
        inString = !inString;
      } else if (!inString) {
        if (ch == '[' || ch == '{') {
          depth++;
        } else if (ch == ']' || ch == '}') {
          depth--;
          if (depth == 0) return i + 1;
        }
      }
    }
    return s.length;
  }

  // --- URLs ----------------------------------------------------------------

  static final _urlScheme = RegExp(
    r'^([a-zA-Z][a-zA-Z0-9+.\-]*://)(.*)$',
    dotAll: true,
  );
  static final _whitespace = RegExp(r'\s');

  /// Redacts user info and sensitive query / fragment parameters of [url].
  ///
  /// User info is everything before the *last* `@` that precedes whitespace,
  /// so a password containing `/`, `#`, `?` or `@` cannot leak.
  String redactUrl(String url) {
    final m = _urlScheme.firstMatch(url);
    if (m == null) return redactText(url);
    final rest = m[2]!;
    final ws = rest.indexOf(_whitespace);
    final limit = ws < 0 ? rest.length : ws;
    final at = limit == 0 ? -1 : rest.lastIndexOf('@', limit - 1);
    final userInfo = at < 0 ? '' : '$placeholder@';
    final afterUser = at < 0 ? rest : rest.substring(at + 1);

    final hash = afterUser.indexOf('#');
    final beforeHash = hash < 0 ? afterUser : afterUser.substring(0, hash);
    final fragment = hash < 0 ? '' : _redactFragment(afterUser.substring(hash));
    final q = beforeHash.indexOf('?');
    final base = q < 0 ? beforeHash : beforeHash.substring(0, q);
    final query = q < 0 ? '' : '?${_redactParams(beforeHash.substring(q + 1))}';
    return '${m[1]}$userInfo$base$query$fragment';
  }

  String _redactFragment(String fragment) {
    final body = fragment.substring(1);
    return body.contains('=') ? '#${_redactParams(body)}' : fragment;
  }

  String _redactParams(String params) {
    return params
        .split('&')
        .map((pair) {
          final i = pair.indexOf('=');
          if (i < 0) return pair;
          final name = pair.substring(0, i);
          return isSensitiveKey(name) ? '$name=$placeholder' : pair;
        })
        .join('&');
  }

  // --- headers & structured data -------------------------------------------

  /// Returns a copy of [headers] with secret values replaced.
  Map<String, String> redactHeaders(Map<String, Object?> headers) {
    return {
      for (final e in headers.entries)
        e.key:
            (_sensitiveHeaderNames.contains(e.key.toLowerCase()) ||
                isSensitiveHeaderName(e.key) ||
                isSensitiveKey(e.key))
            ? placeholder
            : redactText(_headerValue(e.value)),
    };
  }

  /// Header names are broader than other keys: anything containing
  /// auth, key, token, session or cookie is a secret.
  static bool isSensitiveHeaderName(String name) {
    final n = name.toLowerCase();
    return n.contains('auth') ||
        n.contains('key') ||
        n.contains('token') ||
        n.contains('session') ||
        n.contains('cookie');
  }

  String _headerValue(Object? v) => v is Iterable ? v.join(', ') : '$v';

  /// Recursively redacts maps, lists and strings (e.g. decoded JSON).
  ///
  /// A map whose `method` is a login / `auth.*` JSON-RPC method has its
  /// `params` replaced entirely.
  Object? redactValue(Object? value) {
    if (value is Map) {
      final method = value['method'];
      final sensitiveRpc = method is String && _rpcMethodName.hasMatch(method);
      return {
        for (final e in value.entries)
          e.key:
              ((e.key is String && isSensitiveKey(e.key as String)) ||
                  (sensitiveRpc && e.key == 'params'))
              ? placeholder
              : redactValue(e.value),
      };
    }
    if (value is Iterable) return value.map(redactValue).toList();
    if (value is String) return redactText(value);
    return value;
  }
}
