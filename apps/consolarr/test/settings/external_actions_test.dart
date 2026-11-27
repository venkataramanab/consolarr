// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

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

    test('long text is cut within the cap and carries the note', () {
      final r = capShareText('a' * 1000, '[cut]', maxBytes: 100);
      expect(r.truncated, isTrue);
      expect(utf8.encode(r.text).length, lessThanOrEqualTo(100));
      expect(r.text, endsWith('\n\n[cut]'));
    });

    test('never splits a multi-byte character', () {
      final r = capShareText('ع' * 500, '[cut]', maxBytes: 101);
      expect(r.truncated, isTrue);
      expect(utf8.encode(r.text).length, lessThanOrEqualTo(101));
      expect(r.text, isNot(contains('�')));
    });

    test('the default cap is about 500 KB', () {
      expect(shareTextMaxBytes, 500 * 1024);
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
        text: 'x' * (shareTextMaxBytes + 10),
        subject: 's',
        truncationNote: '[short]',
      );
      expect(cut, isTrue);
      final sent = (calls.single.arguments as Map)['text'] as String;
      expect(utf8.encode(sent).length, lessThanOrEqualTo(shareTextMaxBytes));
      expect(sent, endsWith('[short]'));
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
