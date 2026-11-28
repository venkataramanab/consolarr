// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:consolarr/features/settings/data/external_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];
  @override
  get linkDelegate => null;

  Object? error;
  bool result = true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (error != null) throw error!;
    launched.add(url);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('capShareText', () {
    test('short text is untouched', () {
      final r = capShareText('hello', 'note');
      expect(r.text, 'hello');
      expect(r.truncated, isFalse);
    });

    String logText(int lines) => [
      'Consolarr diagnostics',
      '## Log',
      for (var i = 0; i < lines; i++) 'line $i',
    ].join('\n');

    test('long text is cut within the cap and carries the note', () {
      final r = capShareText(logText(500), '[cut]', maxBytes: 200);
      expect(r.truncated, isTrue);
      expect(utf8.encode(r.text).length, lessThanOrEqualTo(200));
      expect(r.text, contains('\n\n[cut]\n\n'));
    });

    test('keeps the header and the newest lines, not the oldest', () {
      final r = capShareText(logText(500), '[cut]', maxBytes: 200);
      expect(r.text, startsWith('Consolarr diagnostics\n## Log'));
      expect(r.text, endsWith('line 499'));
      expect(r.text, isNot(contains('line 100\n')));
      // The tail starts on a whole line.
      final tail = r.text.split('[cut]\n\n').last;
      expect(tail, matches(RegExp(r'^line \d+(\nline \d+)*$')));
    });

    test('the cap is measured in bytes, at the exact boundary', () {
      const max = 100;
      final fits = 'a' * max;
      expect(capShareText(fits, '[cut]', maxBytes: max).truncated, isFalse);
      final over = capShareText('${fits}a', '[cut]', maxBytes: max);
      expect(over.truncated, isTrue);
      expect(utf8.encode(over.text).length, lessThanOrEqualTo(max));
      // 60 two-byte characters are 120 bytes: over, though under in characters.
      expect(capShareText('ع' * 60, '[cut]', maxBytes: max).truncated, isTrue);
    });

    test('never splits a multi-byte character (Arabic, emoji)', () {
      for (final unit in ['ع', '😀', 'سجل 😀 ']) {
        for (final max in [101, 102, 103, 104, 150]) {
          final text = List.generate(300, (i) => '$unit$i').join('\n');
          final r = capShareText(text, '[cut]', maxBytes: max);
          expect(r.truncated, isTrue, reason: '$unit $max');
          expect(utf8.encode(r.text).length, lessThanOrEqualTo(max));
          expect(r.text, isNot(contains('\uFFFD')), reason: '$unit $max');
        }
      }
    });

    test('a single huge line keeps its newest part', () {
      final r = capShareText('${'x' * 1000}END', '[cut]', maxBytes: 100);
      expect(r.truncated, isTrue);
      expect(r.text, endsWith('xxEND'));
      expect(utf8.encode(r.text).length, lessThanOrEqualTo(100));
    });

    test('the default cap is 150 KB of UTF-8', () {
      expect(shareTextMaxBytes, 150 * 1024);
    });

    group('at the real 150 KB cap', () {
      const cap = shareTextMaxBytes;
      const note = '[older lines left out]';
      int bytes(String s) => utf8.encode(s).length;
      String lines(int n) => [
        'Consolarr diagnostics',
        '## Log',
        for (var i = 0; i < n; i++) 'line $i ${'ع' * 20}',
      ].join('\n');

      test('cap-1, cap and cap+1 bytes', () {
        for (final (size, cut) in [
          (cap - 1, false),
          (cap, false),
          (cap + 1, true),
        ]) {
          final text = 'a' * size;
          final r = capShareText(text, note);
          expect(r.truncated, cut, reason: '$size');
          expect(bytes(r.text), lessThanOrEqualTo(cap), reason: '$size');
          if (!cut) expect(r.text, text);
        }
      });

      test('the result with its note is at most the cap, for many sizes', () {
        for (final n in [10000, 12000, 50000]) {
          final r = capShareText(lines(n), note);
          expect(r.truncated, isTrue, reason: '$n');
          expect(bytes(r.text), lessThanOrEqualTo(cap), reason: '$n');
          expect(r.text, contains(note));
        }
      });

      test('keeps the head and the newest tail', () {
        final r = capShareText(lines(20000), note);
        expect(r.text, startsWith('Consolarr diagnostics\n## Log'));
        expect(r.text, endsWith('line 19999 ${'ع' * 20}'));
        expect(r.text, isNot(contains('line 100 ')));
      });

      test('a 4-byte emoji and Arabic at the cut are never split', () {
        for (final unit in ['😀', 'ع', 'x😀', 'عx']) {
          for (var pad = 0; pad < 8; pad++) {
            final text = '${'a' * pad}${unit * (cap ~/ 2 + 50)}';
            final r = capShareText(text, note);
            expect(r.truncated, isTrue);
            expect(bytes(r.text), lessThanOrEqualTo(cap));
            expect(r.text, isNot(contains('\uFFFD')), reason: '$unit $pad');
            // Every character is whole: encoding and decoding round-trips.
            expect(utf8.decode(utf8.encode(r.text)), r.text);
          }
        }
      });

      test('is idempotent on its own output', () {
        final once = capShareText(lines(20000), note);
        final twice = capShareText(once.text, note);
        expect(twice.truncated, isFalse);
        expect(twice.text, once.text);
      });
    });

    test('the native guard has the same cap in both flavors', () {
      for (final app in ['consolarr', 'consolarr_play']) {
        final kotlin = File(
          '../$app/android/app/src/main/kotlin/org/consolarr/app/MainActivity.kt',
        ).readAsStringSync();
        final m = RegExp(r'const val MAX_SHARE_TEXT_BYTES = (\d+) \* 1024')
            .firstMatch(kotlin);
        expect(m, isNotNull, reason: app);
        expect(int.parse(m!.group(1)!) * 1024, shareTextMaxBytes, reason: app);
        expect(kotlin, contains('"too_large"'));
        expect(kotlin, contains('toByteArray(Charsets.UTF_8).size'));
        // The guard runs before the intent is built.
        expect(
          kotlin.indexOf('too_large'),
          lessThan(kotlin.indexOf('Intent(Intent.ACTION_SEND)')),
        );
      }
    });
  });

  group('PlatformExternalActions', () {
    const actions = PlatformExternalActions();
    final calls = <MethodCall>[];

    void mock(String channel, Future<Object?> Function(MethodCall) handler) =>
        messenger.setMockMethodCallHandler(MethodChannel(channel), handler);

    tearDown(() {
      for (final c in ['consolarr/share', 'consolarr/platform_info']) {
        messenger.setMockMethodCallHandler(MethodChannel(c), null);
      }
      calls.clear();
    });

    test('shareText sends the text and subject on the share channel', () async {
      mock('consolarr/share', (c) async {
        calls.add(c);
        return null;
      });
      final cut = await actions.shareText(
        text: 'diagnostics',
        subject: 'Subject',
        truncationNote: 'note',
      );
      expect(cut, isFalse);
      expect(calls.single.method, 'shareText');
      expect(calls.single.arguments, {
        'text': 'diagnostics',
        'subject': 'Subject',
      });
    });

    test('an oversized text is cut before it crosses the channel', () async {
      mock('consolarr/share', (c) async {
        calls.add(c);
        return null;
      });
      final cut = await actions.shareText(
        text: 'ع' * shareTextMaxBytes,
        subject: 's',
        truncationNote: '[short]',
      );
      expect(cut, isTrue);
      final sent = (calls.single.arguments as Map)['text'] as String;
      expect(utf8.encode(sent).length, lessThanOrEqualTo(shareTextMaxBytes));
      expect(sent, contains('[short]'));
    });

    test('a native too_large refusal is a typed error', () async {
      mock('consolarr/share', (_) async {
        throw PlatformException(code: 'too_large');
      });
      await expectLater(
        actions.shareText(text: 't', subject: 's', truncationNote: 'n'),
        throwsA(isA<ShareTextTooLarge>()),
      );
    });

    test('a failing share sheet surfaces as an error', () async {
      mock('consolarr/share', (_) async {
        throw PlatformException(code: 'unavailable');
      });
      await expectLater(
        actions.shareText(text: 't', subject: 's', truncationNote: 'n'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('platformDescription reads the API level, else "unknown"', () async {
      mock('consolarr/platform_info', (_) async => 34);
      expect(await actions.platformDescription(), 'Android API 34');
      mock('consolarr/platform_info', (_) async => null);
      expect(await actions.platformDescription(), 'unknown');
      mock('consolarr/platform_info', (_) async {
        throw PlatformException(code: 'x');
      });
      expect(await actions.platformDescription(), 'unknown');
    });

    group('openHttps', () {
      late UrlLauncherPlatform previous;
      late _FakeLauncher launcher;

      setUp(() {
        previous = UrlLauncherPlatform.instance;
        launcher = _FakeLauncher();
        UrlLauncherPlatform.instance = launcher;
      });
      tearDown(() => UrlLauncherPlatform.instance = previous);

      test('opens https addresses', () async {
        expect(await actions.openHttps(Uri.parse('https://example.com')), true);
        expect(launcher.launched, ['https://example.com']);
      });

      test('refuses every other scheme without launching', () async {
        for (final u in ['http://example.com', 'intent://x', 'file:///x']) {
          expect(await actions.openHttps(Uri.parse(u)), isFalse);
        }
        expect(launcher.launched, isEmpty);
      });

      test(
        'reports false when nothing handles it or the launcher throws',
        () async {
          launcher.result = false;
          expect(
            await actions.openHttps(Uri.parse('https://example.com')),
            false,
          );
          launcher.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
          expect(
            await actions.openHttps(Uri.parse('https://example.com')),
            false,
          );
        },
      );
    });
  });

  group('RecordingExternalActions', () {
    test('records shared text, applying the same cap', () async {
      final r = RecordingExternalActions();
      final cut = await r.shareText(
        text: 'ok',
        subject: 's',
        truncationNote: 'n',
      );
      expect(cut, isFalse);
      expect(r.shared, ['ok']);
      expect(await r.openHttps(Uri.parse('http://x.example')), isFalse);
      expect(await r.openHttps(Uri.parse('https://x.example')), isTrue);
      expect(await r.platformDescription(), 'Android API 34');
    });
  });
}
