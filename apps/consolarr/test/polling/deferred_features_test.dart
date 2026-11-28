// SPDX-License-Identifier: GPL-3.0-or-later

// Notifications and background execution are deferred: nothing of them ships.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final roots = [
    Directory.current.path,
    '${Directory.current.parent.path}/consolarr_play',
  ];
  final lock = File('${Directory.current.parent.parent.path}/pubspec.lock')
      .readAsStringSync();

  test('no background or notification dependency, direct or locked', () {
    const banned = [
      'workmanager',
      'flutter_local_notifications',
      'awesome_notifications',
      'firebase_messaging',
      'flutter_background_service',
      'android_alarm_manager',
      'background_fetch',
      'permission_handler',
    ];
    for (final root in roots) {
      final pubspec = File('$root/pubspec.yaml').readAsStringSync();
      for (final name in banned) {
        expect(pubspec, isNot(contains(name)), reason: '$root $name');
      }
    }
    for (final name in banned) {
      expect(lock, isNot(contains('\n  $name:')), reason: name);
    }
  });

  test('the manifests add no notification, wake, boot or service entry', () {
    for (final root in roots) {
      final dir = Directory('$root/android/app/src');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('AndroidManifest.xml')) continue;
        final xml = f.readAsStringSync();
        for (final banned in [
          'POST_NOTIFICATIONS',
          'WAKE_LOCK',
          'RECEIVE_BOOT_COMPLETED',
          'FOREGROUND_SERVICE',
        ]) {
          expect(xml, isNot(contains(banned)), reason: '${f.path} $banned');
        }
        // A service or receiver may only appear to be removed.
        for (final m in RegExp(
          r'<(service|receiver)\b[^>]*>',
        ).allMatches(xml)) {
          expect(m.group(0), contains('tools:node="remove"'), reason: f.path);
        }
      }
    }
  });

  test('the polling layer declares no provider (nothing starts at launch)', () {
    final dir = Directory('lib/shared/polling');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(
        providerDeclarations(f.readAsStringSync()),
        isEmpty,
        reason: f.path,
      );
    }
  });

  test('nothing outside the polling layer imports the change detection', () {
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      expect(
        importsChangeDetection(f.path, f.readAsStringSync()),
        isFalse,
        reason: '${f.path} wires the change detection into the app',
      );
    }
  });

  group('the guards themselves (negative self-tests)', () {
    test('providerDeclarations finds every Riverpod declaration style', () {
      for (final planted in [
        'final aProvider = Provider<int>((ref) => 1);',
        'final aProvider = Provider((ref) => 1);',
        'final a = FutureProvider.autoDispose<int>((ref) async => 1);',
        'final a = StreamProvider.family<int, String>((ref, id) => x);',
        'final a = NotifierProvider<N, int>(N.new);',
        'final a = AsyncNotifierProvider.autoDispose<N, int>(N.new);',
        'final a = StateProvider<int>((ref) => 0);',
        'final a = ChangeNotifierProvider(\n(ref) => X());',
        '@riverpod\nint a(Ref ref) => 1;',
        '@Riverpod(keepAlive: true)\nint a(Ref ref) => 1;',
      ]) {
        expect(providerDeclarations(planted), isNotEmpty, reason: planted);
      }
    });

    test('providerDeclarations ignores comments and plain words', () {
      expect(
        providerDeclarations(
          '// final a = Provider<int>(x);\n'
          '/* NotifierProvider( */\n'
          'final provider = 1; // the provider (none)\n',
        ),
        isEmpty,
      );
    });

    test('a provider planted in a temp copy of the layer fails the guard', () {
      final tmp = Directory.systemTemp.createTempSync('polling_guard');
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory('lib/shared/polling').listSync(recursive: true).forEach((e) {
        if (e is! File) return;
        final rel = e.path.substring('lib/shared/polling/'.length);
        final copy = File('${tmp.path}/$rel')..createSync(recursive: true);
        copy.writeAsStringSync(e.readAsStringSync());
      });
      File('${tmp.path}/poll_scheduler.dart').writeAsStringSync(
        '${File('${tmp.path}/poll_scheduler.dart').readAsStringSync()}\n'
        'final sneakyProvider = Provider.autoDispose<int>((ref) => 1);\n',
      );
      final hits = [
        for (final f in tmp.listSync(recursive: true).whereType<File>())
          if (providerDeclarations(f.readAsStringSync()).isNotEmpty) f.path,
      ];
      expect(hits, [endsWith('poll_scheduler.dart')]);
    });

    test('importsChangeDetection flags an import from outside the layer', () {
      const planted =
          "import 'package:consolarr/shared/polling/change_detection/"
          "poll_cycle.dart';";
      expect(importsChangeDetection('lib/features/x/y.dart', planted), isTrue);
      expect(
        importsChangeDetection(
          'lib/features/x/y.dart',
          "import '../../../shared/polling/change_detection/diff.dart';",
        ),
        isTrue,
      );
      expect(
        importsChangeDetection(
          'lib/shared/polling/snapshot_sources.dart',
          planted,
        ),
        isFalse,
      );
      expect(
        importsChangeDetection(
          'lib/features/x/y.dart',
          "import 'package:consolarr/shared/polling/poll_scheduler.dart';",
        ),
        isFalse,
      );
    });
  });
}

/// Riverpod declarations in [source] (comments are ignored).
List<String> providerDeclarations(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  return [
    for (final m in RegExp(
      r'\b\w*Provider(\.\w+)*\s*[<(]|@[Rr]iverpod\b',
    ).allMatches(code))
      m.group(0)!,
  ];
}

/// Whether [path] (a file under `lib/`) outside `shared/polling` imports the
/// change-detection layer.
bool importsChangeDetection(String path, String source) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.contains('shared/polling/')) return false;
  return RegExp(
    r'''^\s*(?:import|export)\s+['"][^'"]*shared/polling/change_detection/''',
    multiLine: true,
  ).hasMatch(source);
}
