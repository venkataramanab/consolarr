// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

const r = Redactor();
const mask = Redactor.placeholder;

/// Printable ASCII, space included (0x20-0x7E).
final _printable = String.fromCharCodes([for (var c = 0x20; c < 0x7f; c++) c]);

/// Printable ASCII without whitespace and the URL structure characters `&#`.
final _urlSafe = _printable.replaceAll(RegExp(r'[ &#]'), '');

const _tokenChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~%';

/// Random secret. Always starts with a letter so it can't be mistaken for a
/// placeholder. [chars] defaults to every printable ASCII character.
String secret(Random rnd, {int min = 8, int max = 40, String? chars}) {
  final alphabet = chars ?? _printable;
  final n = min + rnd.nextInt(max - min + 1);
  return 'Z${List.generate(n, (_) => alphabet[rnd.nextInt(alphabet.length)]).join()}';
}

void main() {
  group('examples', () {
    test('URL credentials', () {
      expect(
        r.redactUrl('https://admin:hunter2pass@host.example:8989/api'),
        'https://$mask@host.example:8989/api',
      );
      expect(
        r.redactText('GET https://u:p@192.0.2.5/x failed'),
        'GET https://$mask@192.0.2.5/x failed',
      );
    });

    test('query keys', () {
      expect(
        r.redactUrl('https://h.example/api?apikey=test-key-0000&page=2'),
        'https://h.example/api?apikey=$mask&page=2',
      );
      expect(
        r.redactUrl('https://h.example/?access_token=abc123&x=1#id_token=zzz'),
        'https://h.example/?access_token=$mask&x=1#id_token=$mask',
      );
    });

    test('headers', () {
      final out = r.redactHeaders({
        'Authorization': 'Bearer test-key-0000',
        'X-Api-Key': 'test-key-0000',
        'Cookie': 'SID=abc',
        'Accept': 'application/json',
      });
      expect(out['Authorization'], mask);
      expect(out['X-Api-Key'], mask);
      expect(out['Cookie'], mask);
      expect(out['Accept'], 'application/json');
    });

    test('header lines in free text', () {
      expect(
        r.redactText('X-Api-Key: test-key-0000\nAccept: */*'),
        'X-Api-Key: $mask\nAccept: */*',
      );
      expect(
        r.redactText('authorization=Bearer abcdefghij'),
        'authorization=$mask',
      );
    });

    test('passwords and tokens in JSON / form text', () {
      expect(
        r.redactText('{"username":"u","password":"p@ss w0rd","n":1}'),
        '{"username":"u","password":"$mask","n":1}',
      );
      expect(
        r.redactText('username=u&password=s3cret&token=t0k'),
        'username=u&password=$mask&token=$mask',
      );
    });

    test('32-char hex api keys and JWTs standing alone', () {
      const key = '0123456789abcdef0123456789abcdef';
      expect(r.redactText('key was $key.'), 'key was $mask.');
      expect(r.redactText('t=eyJhbGciOi.eyJzdWIiOiIx.sig_-x'), 't=$mask');
    });

    test('is idempotent and leaves harmless text alone', () {
      const harmless = 'Queue has 3 items, status=ok, page=2';
      expect(r.redactText(harmless), harmless);
      final once = r.redactText('password=abc&apikey=def');
      expect(r.redactText(once), once);
    });

    test('JSON-RPC login params are redacted wholesale', () {
      expect(
        r.redactText('{"method":"auth.login","params":["secret"]}'),
        '{"method":"auth.login","params":$mask}',
      );
      expect(
        r.redactText('{"params":["secret","x"],"id":1,"method":"auth.login"}'),
        '{"params":$mask,"id":1,"method":"auth.login"}',
      );
      expect(
        r.redactText(
          '{"jsonrpc":"2.0","method":"core.login","params":{"u":"a","p":"b"}}',
        ),
        '{"jsonrpc":"2.0","method":"core.login","params":$mask}',
      );
      expect(
        r.redactText(r'{\"method\":\"auth.login\",\"params\":[\"s3\"]}'),
        r'{\"method\":\"auth.login\",\"params\":'
        '$mask}',
      );
      // Other methods are left alone.
      const other = '{"method":"core.get_torrents","params":["abc"]}';
      expect(r.redactText(other), other);
    });

    test('JSON-RPC login params in decoded structures', () {
      expect(
        r.redactValue({
          'method': 'auth.login',
          'params': ['secret'],
          'id': 1,
        }),
        {'method': 'auth.login', 'params': mask, 'id': 1},
      );
      expect(
        r.redactValue([
          {'method': 'auth.check_session', 'params': <Object?>[]},
          {
            'method': 'core.get_torrents',
            'params': ['a'],
          },
        ]),
        [
          {'method': 'auth.check_session', 'params': mask},
          {
            'method': 'core.get_torrents',
            'params': ['a'],
          },
        ],
      );
    });

    test('scheme-less user info', () {
      expect(
        r.redactText('connect user:pass@192.0.2.5:8080 failed'),
        'connect $mask@192.0.2.5:8080 failed',
      );
      expect(
        r.redactText('proxy=user:p@ss@192.0.2.5:8080'),
        'proxy=$mask@192.0.2.5:8080',
      );
      // Plain e-mail style text without a colon before the @ is kept.
      expect(
        r.redactText('contact me@host.example'),
        'contact me@host.example',
      );
    });

    test('user info containing / # ? is parsed up to the last @', () {
      expect(
        r.redactUrl('https://us/er:pa#ss?x@host.example:81/p?a=1'),
        'https://$mask@host.example:81/p?a=1',
      );
      expect(
        r.redactText('GET https://u:p/a?b#c@192.0.2.5/x failed'),
        'GET https://$mask@192.0.2.5/x failed',
      );
    });

    test('sensitive key followed by an array or object', () {
      expect(
        r.redactText('{"apiKeys":["S1","S2"],"n":1}'),
        '{"apiKeys":$mask,"n":1}',
      );
      expect(
        r.redactText('{"secret":{"a":"S","b":["x]","y"]},"n":1}'),
        '{"secret":$mask,"n":1}',
      );
      expect(r.redactText('tokens=[S1, S2]'), 'tokens=$mask');
      expect(r.redactText('{"password":["S'), '{"password":$mask');
    });

    test('escaped quotes, semicolons and spaces inside values', () {
      expect(
        r.redactText(r'{"password":"ab\"cd","n":1}'),
        '{"password":"$mask","n":1}',
      );
      expect(
        r.redactText(r'{\"password\":\"ab12\",\"n\":1}'),
        r'{\"password\":\"'
        '$mask'
        r'\",\"n\":1}',
      );
      expect(r.redactText('password=ab;cd ef'), 'password=$mask');
      expect(
        r.redactText('password=my secret phrase\nnext=1'),
        'password=$mask\nnext=1',
      );
      expect(
        r.redactText('Cookie-ish: token=a;b=c'),
        'Cookie-ish: token=$mask',
      );
      expect(
        r.redactText('username=u&password=s3 cret&token=t0k'),
        'username=u&password=$mask&token=$mask',
      );
      expect(
        r.redactText('{"password":12345,"user":"bob"}'),
        '{"password":$mask,"user":"bob"}',
      );
    });

    test('percent signs in bearer / basic tokens', () {
      expect(r.redactText('Bearer abc%2Fdef%3D ok'), 'Bearer $mask ok');
      expect(r.redactText('got basic dXNlcjpw%3D%3D ok'), 'got basic $mask ok');
    });

    test('more key names, plurals and encoded names', () {
      for (final name in [
        'passphrase',
        'otp',
        'totp',
        'signature',
        'X-Amz-Signature',
        'jwt',
        'apiKeys',
        'api_keys',
        'secrets',
        'tokens',
        'passwords',
        'api%5Fkey',
        'api%255Fkey',
        'X%2DApi%2DKey',
        'pass%77ord',
        'user[password]',
        'apiKeys[]',
      ]) {
        expect(Redactor.isSensitiveKey(name), isTrue, reason: name);
        expect(
          r.redactUrl('https://h.example/p?a=1&$name=S3&b=2'),
          'https://h.example/p?a=1&$name=$mask&b=2',
          reason: name,
        );
      }
      expect(r.redactText('api%5Fkey=S3cr3t'), 'api%5Fkey=$mask');
      expect(r.redactText('{"otp":"123456"}'), '{"otp":"$mask"}');
      expect(Redactor.isSensitiveKey('status'), isFalse);
      expect(Redactor.isSensitiveKey('page'), isFalse);
    });

    test('long input is truncated with a marker (idempotent)', () {
      final long = 'x ' * 10000;
      final out = r.redactText(long);
      expect(
        out.length,
        Redactor.maxInputLength + Redactor.truncationMarker.length,
      );
      expect(out, endsWith(Redactor.truncationMarker));
      expect(r.redactText(out), out);
      const short = 'short text';
      expect(r.redactText(short), short);
    });

    test('redactValue walks nested structures', () {
      final out = r.redactValue({
        'password': 'x',
        'nested': {
          'apiKey': 'k',
          'list': [
            {'token': 't', 'ok': 1},
            'password=abc',
          ],
        },
      });
      expect(out, {
        'password': mask,
        'nested': {
          'apiKey': mask,
          'list': [
            {'token': mask, 'ok': 1},
            'password=$mask',
          ],
        },
      });
    });
  });

  group('properties (seeded, 300 iterations each, printable ASCII)', () {
    final rnd = Random(20260101);
    const runs = 300;

    test('URL userinfo never survives, host and path do', () {
      for (var i = 0; i < runs; i++) {
        final user = secret(rnd, max: 12, chars: _urlSafe.replaceAll('@', ''));
        final pass = secret(rnd, chars: _urlSafe);
        final url = 'https://$user:$pass@host$i.example:${1000 + i}/p/$i';
        final out = r.redactUrl(url);
        expect(out, isNot(contains(user)), reason: url);
        expect(out, isNot(contains(pass)), reason: url);
        expect(out, contains('host$i.example:${1000 + i}/p/$i'));
        final text = r.redactText('see $url now');
        expect(text, isNot(contains(pass)), reason: url);
        expect(text, startsWith('see https://'));
        expect(text, endsWith('/p/$i now'));
        final bare = 'user:$pass@192.0.2.$i:8080';
        expect(
          r.redactText('dial $bare ok'),
          isNot(contains(pass)),
          reason: bare,
        );
      }
    });

    test('sensitive query keys are masked, others kept', () {
      const names = [
        'apikey',
        'api_key',
        'apiKey',
        'apiKeys',
        'token',
        'access_token',
        'password',
        'passphrase',
        'otp',
        'signature',
        'jwt',
        'key',
        'secret',
        'X-Api-Key',
        'api%5Fkey',
      ];
      for (var i = 0; i < runs; i++) {
        final s = secret(rnd, chars: _urlSafe.replaceAll('@', ''));
        final name = names[rnd.nextInt(names.length)];
        final out = r.redactUrl('https://h.example/a?x=1&$name=$s&y=2');
        expect(out, isNot(contains(s)), reason: out);
        expect(out, contains('x=1'));
        expect(out, contains('y=2'));
      }
    });

    test('secret headers are masked regardless of case', () {
      const names = [
        'Authorization',
        'authorization',
        'X-API-KEY',
        'x-api-key',
        'Cookie',
        'Set-Cookie',
        'Proxy-Authorization',
        'X-Auth-Token',
      ];
      for (var i = 0; i < runs; i++) {
        final s = secret(rnd);
        final name = names[rnd.nextInt(names.length)];
        final out = r.redactHeaders({name: 'Bearer $s', 'Accept': 'x'});
        expect(out[name], mask);
        expect(out['Accept'], 'x');
        final line = r.redactText('$name: Bearer $s');
        expect(line, isNot(contains(s)));
      }
    });

    test('key=value / JSON secrets in free text are masked', () {
      const names = [
        'password',
        'passwd',
        'passphrase',
        'pwd',
        'token',
        'otp',
        'signature',
        'jwt',
        'api_key',
        'apikey',
        'apiKeys',
        'secret',
        'client_secret',
        'refresh_token',
        'sonarr_api_key',
        'api%5Fkey',
      ];
      for (var i = 0; i < runs; i++) {
        // `&` followed by `name=` is a form-field boundary by design.
        final s = secret(rnd, chars: _printable.replaceAll('&', ''));
        final name = names[rnd.nextInt(names.length)];
        final single = s.replaceAll(RegExp(r"['\\]"), 'q');
        for (final text in [
          '$name=$s',
          '$name: $s',
          '{"$name":${jsonEncode(s)}}',
          '{"$name": ${jsonEncode(s)}, "n": 1}',
          "{'$name': '$single'}",
          '{"$name":[${jsonEncode(s)}]}',
          '${jsonEncode({name: s})}',
          'before $name=$s&after=1',
        ]) {
          final out = r.redactText(text);
          expect(out, isNot(contains(s)), reason: '$text -> $out');
          expect(r.redactText(out), out, reason: 'idempotent: $out');
        }
        // Secret embedded in an escaped JSON string.
        final escaped = jsonEncode(jsonEncode({name: s}));
        final inner = escaped.substring(1, escaped.length - 1);
        final out = r.redactText('log: $inner');
        expect(out, isNot(contains(s)), reason: '$inner -> $out');
      }
    });

    test('JSON-RPC login params are masked for every secret', () {
      for (var i = 0; i < runs; i++) {
        final s = secret(rnd);
        final method = [
          'auth.login',
          'core.login',
          'auth.check_session',
        ][i % 3];
        final text = jsonEncode({
          'method': method,
          'params': [
            s,
            {'k': s},
          ],
          'id': i,
        });
        final out = r.redactText(text);
        expect(out, isNot(contains(s)), reason: '$text -> $out');
        expect(r.redactText(out), out);
      }
    });

    test('standalone 32+ hex keys and bearer tokens are masked', () {
      const hex = '0123456789abcdef';
      for (var i = 0; i < runs; i++) {
        final key = List.generate(
          32 + rnd.nextInt(33),
          (_) => hex[rnd.nextInt(16)],
        ).join();
        expect(r.redactText('k $key e'), 'k $mask e');
        final b = secret(rnd, chars: _tokenChars);
        expect(r.redactText('got Bearer $b ok'), 'got Bearer $mask ok');
        expect(r.redactText('got Basic $b ok'), 'got Basic $mask ok');
      }
    });

    test('text without secrets is unchanged', () {
      for (var i = 0; i < runs; i++) {
        final text =
            'Fetched ${rnd.nextInt(500)} items from page '
            '${rnd.nextInt(20)} in ${rnd.nextInt(900)} ms (status=ok)';
        expect(r.redactText(text), text);
      }
    });
  });

  group('performance', () {
    final shapes = <String, String Function(int)>{
      'plain words': (n) => 'lorem ipsum ' * (n ~/ 12),
      'one long word': (n) => 'a' * n,
      'key chars': (n) => 'api_key.' * (n ~/ 8),
      'separators': (n) => '=' * n,
      'colons': (n) => 'a:' * (n ~/ 2),
      'sensitive keys without values': (n) => 'password ' * (n ~/ 9),
      'sensitive keys with equals': (n) => 'token=x ' * (n ~/ 8),
      'spaces': (n) => 'a${' ' * n}b',
      'quotes': (n) => '"' * n,
      'brackets': (n) => '[{' * (n ~/ 2),
      'at signs': (n) => 'a:b@' * (n ~/ 4),
      'schemes': (n) => 'a://' * (n ~/ 4),
      'rpc': (n) => '"method":"auth.login","params":' * (n ~/ 31),
      'boundary colons': (n) => '=a:' * (n ~/ 3),
      'at then colons': (n) => ('a@' * (n ~/ 4)) + (':b' * (n ~/ 4)),
      'percent': (n) => 'bearer ${'%' * n}',
    };

    for (final entry in shapes.entries) {
      test('${entry.key}: 200 KB redacts in under 200 ms', () {
        final input = entry.value(200 * 1024);
        final sw = Stopwatch()..start();
        r.redactText(input);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(200), reason: entry.key);
      });

      test('${entry.key}: input at the cap stays linear', () {
        final input = entry.value(Redactor.maxInputLength);
        final sw = Stopwatch()..start();
        r.redactText(input);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(200), reason: entry.key);
      });
    }

    test('4000 chars of key-like text is fast (was quadratic)', () {
      final input = 'a.' * 2000;
      final sw = Stopwatch()..start();
      r.redactText(input);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  group('AppLogger', () {
    test('redacts messages and errors and honours minLevel', () {
      final lines = <String>[];
      final log = AppLogger(sink: (l, m) => lines.add('${l.name}:$m'));
      log
        ..debug('dropped')
        ..info('GET https://u:pw1234@h.example/?apikey=test-key-0000')
        ..error('boom', error: 'password=hunter2');
      expect(lines, [
        'info:GET https://$mask@h.example/?apikey=$mask',
        'error:boom: password=$mask',
      ]);
    });
  });

  group('interfaces and no-ops', () {
    test('consent defaults to off and no-ops do nothing', () async {
      expect(await const NoopConsentStore().load(), ConsentState.none);
      final store = InMemoryConsentStore();
      expect((await store.load()).analytics, isFalse);
      await store.save(const ConsentState(analytics: true));
      expect((await store.load()).analytics, isTrue);
      await const NoopCrashReporter().recordError(StateError('x'), null);
      await const NoopAnalytics().logEvent('e');
    });
  });
}
