// SPDX-License-Identifier: GPL-3.0-or-later

/// Removes secrets from text, URLs, headers and structured data before it is
/// logged, reported or shared.
///
/// Covers: API keys, `Authorization` / `X-Api-Key` / cookie headers,
/// passwords, tokens, URL credentials (user info) and sensitive query keys.
/// Redaction is idempotent and errs on the side of over-redaction.
class Redactor {
  const Redactor();

  /// Replacement for every removed secret.
  static const placeholder = '[REDACTED]';

  static const _sensitiveHeaderNames = {
    'authorization',
    'proxy-authorization',
    'x-api-key',
    'x-auth-token',
    'cookie',
    'set-cookie',
  };

  static final _separators = RegExp(r'[\s_.\-]');

  /// Whether a header, query, form or JSON key name denotes a secret value.
  static bool isSensitiveKey(String key) {
    final k = key.toLowerCase().replaceAll(_separators, '');
    if (k.isEmpty) return false;
    return k.endsWith('key') ||
        k == 'pwd' ||
        k == 'pass' ||
        k == 'sid' ||
        k == 'auth' ||
        k == 'session' ||
        k == 'sessionid' ||
        k == 'cookie' ||
        k.contains('token') ||
        k.contains('password') ||
        k.contains('passwd') ||
        k.contains('secret') ||
        k.contains('credential') ||
        k.contains('authorization') ||
        k.contains('bearer');
  }

  // --- free text -----------------------------------------------------------

  static final _urlInText = RegExp('[a-zA-Z][a-zA-Z0-9+.\\-]*://[^\\s"\'<>]+');

  static final _headerLine = RegExp(
    r'\b(authorization|proxy-authorization|x-api-key|x-auth-token|set-cookie|cookie)(\s*[:=]\s*)([^\r\n]+)',
    caseSensitive: false,
  );

  static final _scheme = RegExp(
    r'\b(bearer|basic)(\s+)(?!\[REDACTED\])[A-Za-z0-9._~+/=\-]{6,}',
    caseSensitive: false,
  );

  static final _keyValue = RegExp(
    '(["\']?)'
    r'((?:[\w.\-]*(?:api[_\-]?key|token|password|passwd|secret|credential|authorization)[\w.\-]*)|(?<![\w])(?:pwd|pass|auth|sid|key))'
    '\\1'
    r'(\s*[:=]\s*)'
    '("[^"]*"|\'[^\']*\'|(?!\\[REDACTED\\])[^\\s,;&})\\]"\']+)',
    caseSensitive: false,
  );

  static final _longHex = RegExp(
    r'(?<![0-9A-Za-z])[0-9a-fA-F]{32,}(?![0-9A-Za-z])',
  );
  static final _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*',
  );

  /// Redacts secrets in arbitrary [input] text.
  String redactText(String input) {
    var out = input.replaceAllMapped(_urlInText, (m) => redactUrl(m[0]!));
    out = out.replaceAllMapped(
      _headerLine,
      (m) => '${m[1]}${m[2]}$placeholder',
    );
    out = out.replaceAllMapped(_scheme, (m) => '${m[1]}${m[2]}$placeholder');
    out = out.replaceAllMapped(_keyValue, (m) {
      final value = m[4]!;
      final quote = value.isNotEmpty && (value[0] == '"' || value[0] == "'")
          ? value[0]
          : '';
      return '${m[1]}${m[2]}${m[1]}${m[3]}$quote$placeholder$quote';
    });
    out = out.replaceAll(_jwt, placeholder);
    out = out.replaceAll(_longHex, placeholder);
    return out;
  }

  // --- URLs ----------------------------------------------------------------

  static final _urlParts = RegExp(
    r'^([a-zA-Z][a-zA-Z0-9+.\-]*://)([^/?#]*@)?([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$',
    dotAll: true,
  );

  /// Redacts user info and sensitive query / fragment parameters of [url].
  String redactUrl(String url) {
    final m = _urlParts.firstMatch(url);
    if (m == null) return redactText(_stripUnparsable(url));
    final userInfo = m[2] == null ? '' : '$placeholder@';
    final query = m[5] == null ? '' : '?${_redactParams(m[5]!.substring(1))}';
    final fragment = m[6] == null ? '' : _redactFragment(m[6]!);
    return '${m[1]}$userInfo${m[3]}${m[4]}$query$fragment';
  }

  String _stripUnparsable(String s) => s.replaceAll(RegExp(r'[^\s]*@'), '');

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
          final decoded = _safeDecode(name);
          return isSensitiveKey(decoded) ? '$name=$placeholder' : pair;
        })
        .join('&');
  }

  String _safeDecode(String s) {
    try {
      return Uri.decodeQueryComponent(s);
    } on Object {
      return s;
    }
  }

  // --- headers & structured data -------------------------------------------

  /// Returns a copy of [headers] with secret values replaced.
  Map<String, String> redactHeaders(Map<String, Object?> headers) {
    return {
      for (final e in headers.entries)
        e.key:
            (_sensitiveHeaderNames.contains(e.key.toLowerCase()) ||
                isSensitiveKey(e.key))
            ? placeholder
            : redactText(_headerValue(e.value)),
    };
  }

  String _headerValue(Object? v) => v is Iterable ? v.join(', ') : '$v';

  /// Recursively redacts maps, lists and strings (e.g. decoded JSON).
  Object? redactValue(Object? value) {
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key: (e.key is String && isSensitiveKey(e.key as String))
              ? placeholder
              : redactValue(e.value),
      };
    }
    if (value is Iterable) return value.map(redactValue).toList();
    if (value is String) return redactText(value);
    return value;
  }
}
