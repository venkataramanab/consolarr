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

  test('nothing outside the polling layer reaches the change detection', () {
    final sources = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          f.path.replaceAll('\\', '/'): f.readAsStringSync(),
    };
    // The guard resolves real files: the polling layer's own wiring reaches
    // the layer, so a guard that resolved nothing could not pass this.
    final reaching = filesReachingChangeDetection(sources, inside: _polling);
    expect(
      reaching.keys,
      containsAll([
        'lib/shared/polling/snapshot_sources.dart',
        'lib/shared/polling/poll_telemetry.dart',
      ]),
    );
    final offenders = filesReachingChangeDetection(sources);
    expect(
      offenders,
      isEmpty,
      reason: 'these files wire the change detection into the app',
    );
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

    // A synthetic app: the layer, the two polling files that re-export or use
    // it, and the polling files that do not touch it.
    const layer = 'lib/shared/polling/change_detection/change_detection.dart';
    const wiring = {
      layer: "export 'package:core/change_detection.dart';",
      'lib/shared/polling/snapshot_sources.dart':
          "import 'package:consolarr/shared/polling/change_detection/"
          "change_detection.dart';",
      'lib/shared/polling/poll_telemetry.dart':
          "import 'change_detection/change_detection.dart';",
      'lib/shared/polling/poll_scheduler.dart': "import 'dart:async';",
      'lib/shared/polling/poll_visibility.dart':
          "import 'poll_scheduler.dart';",
    };

    /// The files outside the polling layer that reach it when [planted] is
    /// added to the synthetic app as `lib/features/x/y.dart` (or [at]).
    Set<String> offenders(
      String planted, {
      String at = 'lib/features/x/y.dart',
    }) => filesReachingChangeDetection({...wiring, at: planted}).keys.toSet();

    test('flags every way of reaching the layer from outside it', () {
      const at = 'lib/features/x/y.dart';
      for (final planted in [
        // Direct, as a package URI and as relative hops.
        "import 'package:consolarr/shared/polling/change_detection/diff.dart';",
        "import '../../shared/polling/change_detection/diff.dart';",
        "import '../../shared/polling/../polling/change_detection/diff.dart';",
        "import './../../shared/polling/change_detection/change_detection.dart';",
        'import "../../shared/polling/change_detection/diff.dart";',
        "export '../../shared/polling/change_detection/diff.dart';",
        // The core library behind the layer.
        "import 'package:core/change_detection.dart';",
        "import 'package:core/src/change_detection/diff.dart';",
        // Through the two polling files that re-export or use it.
        "import 'package:consolarr/shared/polling/snapshot_sources.dart';",
        "import 'package:consolarr/shared/polling/poll_telemetry.dart';",
        "import '../../shared/polling/snapshot_sources.dart';",
        "import '../../shared/polling/poll_telemetry.dart' show x;",
        "export '../../shared/polling/poll_telemetry.dart';",
        "import\n    '../../shared/polling/snapshot_sources.dart'\n    as s;",
      ]) {
        expect(offenders(planted), contains(at), reason: planted);
      }
      // A relative import of the layer from another `lib/shared/` folder
      // (the form the old guard missed), and a chain through another file.
      expect(
        offenders(
          "import '../polling/change_detection/diff.dart';",
          at: 'lib/shared/other/x.dart',
        ),
        contains('lib/shared/other/x.dart'),
      );
      final chained = filesReachingChangeDetection({
        ...wiring,
        'lib/features/a.dart': "import 'b.dart';",
        'lib/features/b.dart':
            "import '../shared/polling/snapshot_sources.dart';",
      }).keys;
      expect(
        chained,
        containsAll(['lib/features/a.dart', 'lib/features/b.dart']),
      );
    });

    test('flags a conditional import or export and a part directive', () {
      for (final planted in [
        // The first URI is harmless; the layer hides behind a condition.
        "import 'a.dart' if (dart.library.io) "
            "'../../shared/polling/change_detection/diff.dart';",
        "import 'a.dart' if (dart.library.html) 'b.dart' "
            "if (dart.library.io) '../../shared/polling/snapshot_sources.dart';",
        "export 'a.dart'\n    if (dart.library.io)\n    "
            "'package:core/change_detection.dart';",
        "import 'a.dart' if (dart.library.io == 'true') "
            "'package:core/src/change_detection/diff.dart';",
        // A part file is part of the library that declares it.
        "part '../../shared/polling/change_detection/diff.dart';",
        "part '../../shared/polling/snapshot_sources.dart';",
        'part "package:consolarr/shared/polling/poll_telemetry.dart";',
      ]) {
        expect(
          offenders(planted),
          contains('lib/features/x/y.dart'),
          reason: planted,
        );
      }
      // A part is followed to what it imports, like any other file.
      final viaPart = filesReachingChangeDetection({
        ...wiring,
        'lib/features/a.dart': "part 'b.dart';",
        'lib/features/b.dart':
            "import '../shared/polling/snapshot_sources.dart';",
      }).keys;
      expect(viaPart, contains('lib/features/a.dart'));
    });

    test('conditional alternatives that are harmless stay harmless', () {
      for (final planted in [
        "import 'a.dart' if (dart.library.io) 'b.dart';",
        "import 'package:core/core.dart' if (dart.library.io) 'c.dart';",
        "part 'other.dart';",
        "part of 'a.dart';",
        "// import 'a.dart' if (dart.library.io) 'package:core/change_detection.dart';",
      ]) {
        expect(offenders(planted), isEmpty, reason: planted);
      }
      expect(
        directiveUris(
          "import 'a.dart' if (dart.library.io) 'b.dart' "
          "if (dart.library.html) 'c.dart';",
        ),
        ['a.dart', 'b.dart', 'c.dart'],
      );
    });

    test('lets the rest of the polling layer and unrelated code through', () {
      for (final planted in [
        "import 'package:consolarr/shared/polling/poll_scheduler.dart';",
        "import '../../shared/polling/poll_visibility.dart';",
        "import 'package:core/core.dart';",
        "import 'package:consolarr/shared/l10n/x.dart';",
        "// import 'package:core/change_detection.dart';",
        "/* import '../../shared/polling/snapshot_sources.dart'; */",
        "import 'dart:io';",
      ]) {
        expect(offenders(planted), isEmpty, reason: planted);
      }
    });

    test('files inside the polling layer are the layer, not offenders', () {
      expect(filesReachingChangeDetection(wiring), isEmpty);
    });

    test('import cycles terminate', () {
      expect(
        filesReachingChangeDetection({
          'lib/a.dart': "import 'b.dart';",
          'lib/b.dart': "import 'a.dart';",
        }),
        isEmpty,
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

const _polling = 'lib/shared/polling/';
const _appLayer = 'lib/shared/polling/change_detection/';
const _coreLibrary = 'package:core/change_detection.dart';
const _coreSources = 'package:core/src/change_detection/';

/// Every URI an import, export or part directive of [source] can load
/// (comments ignored), as written: the first URI and each
/// `if (...) '<uri>'` alternative of a conditional one.
List<String> directiveUris(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  final uris = <String>[];
  for (final d in RegExp(
    r'''\b(?:import|export|part)\s+(['"][^;]*);''',
  ).allMatches(code)) {
    final body = d.group(1)!;
    final first = RegExp(r'''^['"]([^'"]+)['"]''').firstMatch(body);
    if (first != null) uris.add(first.group(1)!);
    for (final m in RegExp(
      r'''\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]''',
    ).allMatches(body)) {
      uris.add(m.group(1)!);
    }
  }
  return uris;
}

/// The canonical name of the file that [uri], written in the file [from]
/// (`lib/...`), points at: `lib/...` for the app's own files whether they are
/// spelled as `package:consolarr/...` or as relative hops (`..`, `.`), and the
/// package URI for the other packages. `dart:` libraries are null.
String? canonicalImport(String from, String uri) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:consolarr/')) {
    return 'lib/${uri.substring('package:consolarr/'.length)}';
  }
  if (uri.contains(':')) return uri;
  return Uri.parse(from).resolve(uri).path;
}

bool _isLayer(String canonical) =>
    canonical.startsWith(_appLayer) ||
    canonical == _coreLibrary ||
    canonical.startsWith(_coreSources);

/// The files of [sources] (canonical `lib/...` path -> text) that reach the
/// change-detection layer through any chain of imports and exports, with the
/// first file of the chain that is the layer's own wiring.
///
/// Every directive is resolved to a canonical path first, so a relative hop
/// from any folder, a package URI and a detour through a file that re-exports
/// the layer (`snapshot_sources.dart`, `poll_telemetry.dart`) are all seen.
/// The files in [inside] (the polling layer itself, by default) are the layer
/// and are not reported.
Map<String, String> filesReachingChangeDetection(
  Map<String, String> sources, {
  String? inside,
}) {
  final graph = <String, List<String>>{
    for (final e in sources.entries)
      e.key: [
        for (final uri in directiveUris(e.value)) ?canonicalImport(e.key, uri),
      ],
  };
  final reaches = <String, String>{};
  for (final start in graph.keys) {
    final isInside = start.startsWith(_polling);
    if (inside == null ? isInside : !isInside) continue;
    final seen = <String>{start};
    final queue = [start];
    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      for (final target in graph[file] ?? const <String>[]) {
        if (_isLayer(target)) {
          reaches[start] = file;
          queue.clear();
          break;
        }
        if (graph.containsKey(target) && seen.add(target)) queue.add(target);
      }
    }
  }
  return reaches;
}
