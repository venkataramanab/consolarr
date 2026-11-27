// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

const r = Redactor();
const mask = Redactor.placeholder;

/// Random secret made of characters that are legal in tokens and userinfo.
String secret(Random rnd, {int min = 8, int max = 40}) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~';
  final n = min + rnd.nextInt(max - min + 1);
  // Always start with a letter so it can't be mistaken for a placeholder.
  return 'Z${List.generate(n, (_) => chars[rnd.nextInt(chars.length)]).join()}';
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

  group('properties (seeded, 300 iterations each)', () {
    final rnd = Random(20260101);
    const runs = 300;

    test('URL userinfo never survives, host and path do', () {
      for (var i = 0; i < runs; i++) {
        final user = secret(rnd, max: 12);
        final pass = secret(rnd);
        final url = 'https://$user:$pass@host$i.example:${1000 + i}/p/$i';
        final out = r.redactUrl(url);
        expect(out, isNot(contains(user)));
        expect(out, isNot(contains(pass)));
        expect(out, contains('host$i.example:${1000 + i}/p/$i'));
        final text = r.redactText('see $url now');
        expect(text, isNot(contains(pass)));
        expect(text, startsWith('see https://'));
      }
    });

    test('sensitive query keys are masked, others kept', () {
      const names = [
        'apikey',
        'api_key',
        'apiKey',
        'token',
        'access_token',
        'password',
        'key',
        'secret',
        'X-Api-Key',
      ];
      for (var i = 0; i < runs; i++) {
        final s = secret(rnd);
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
        'pwd',
        'token',
        'api_key',
        'apikey',
        'secret',
        'client_secret',
        'refresh_token',
        'sonarr_api_key',
      ];
      for (var i = 0; i < runs; i++) {
        final s = secret(rnd);
        final name = names[rnd.nextInt(names.length)];
        for (final text in [
          '$name=$s',
          '$name: $s',
          '{"$name":"$s"}',
          "{'$name': '$s'}",
          'before $name=$s&after=1',
        ]) {
          final out = r.redactText(text);
          expect(out, isNot(contains(s)), reason: '$text -> $out');
          expect(r.redactText(out), out, reason: 'idempotent: $out');
        }
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
        final b = secret(rnd);
        expect(r.redactText('got Bearer $b ok'), isNot(contains(b)));
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
