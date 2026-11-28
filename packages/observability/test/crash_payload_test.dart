// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/observability.dart';
import 'package:test/test.dart';

class _Crash implements CrashReporter {
  final List<(Object, StackTrace?, bool)> calls = [];

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async => calls.add((error, stackTrace, fatal));
}

class _Boom implements Exception {
  _Boom(this.message);
  final String message;
  @override
  String toString() => 'Boom: $message';
}

void main() {
  // Canaries are assembled at runtime: no literal in the repository.
  final host = ['nas', 'canary', 'example'].join('.');
  final key = List.filled(32, 'b').join();
  final title = ['The', 'Secret', 'Movie', 'Title'].join(' ');
  final user = ['canary', 'user'].join('-');

  late _Crash sink;
  late ConsentManager manager;

  setUp(() async {
    sink = _Crash();
    manager = ConsentManager(
      store: InMemoryConsentStore(),
      analytics: const NoopAnalytics(),
      crashReporter: sink,
      breadcrumbs: Breadcrumbs(),
      categorize: (e) => e is _Boom ? ErrorCategoryParam.timeout : null,
    );
    await manager.set(ConsentPurpose.crashReports, enabled: true);
  });

  test('the sink gets a typed payload; message, host, key and title never '
      'reach it', () async {
    final trace = StackTrace.fromString(
      [
        '#0      _Boom.explain ($title $host) (package:consolarr/src/a_b.dart:12:7)',
        '#1      load (file:///home/$user/proj/lib/c.dart:3:9)',
        '#2      main (https://$host/path?apikey=$key)',
        '#3      <asynchronous suspension>',
      ].join('\n'),
    );
    await manager.crashReporter.recordError(
      _Boom('failed for $title at $host with $key'),
      trace,
      fatal: true,
    );

    final (error, stack, fatal) = sink.calls.single;
    expect(fatal, isTrue);
    expect(error, isA<CrashPayload>());
    final payload = error as CrashPayload;
    expect(payload.typeName, '_Boom');
    expect(payload.category, ErrorCategoryParam.timeout);
    expect(payload.frames, ['package:consolarr/src/a_b.dart:12', 'c.dart:3']);

    final everything = '$error ${payload.frames} $stack';
    for (final canary in [host, key, title, user, 'apikey']) {
      expect(everything, isNot(contains(canary)), reason: canary);
    }
  });

  test('without a trace or a category the payload is just the type', () async {
    await manager.crashReporter.recordError(StateError('x $host'), null);
    final payload = sink.calls.single.$1 as CrashPayload;
    expect(payload.typeName, 'StateError');
    expect(payload.category, isNull);
    expect(payload.frames, isEmpty);
  });

  test('a throwing categorizer never blocks the report', () async {
    final m = ConsentManager(
      store: InMemoryConsentStore(),
      analytics: const NoopAnalytics(),
      crashReporter: sink,
      breadcrumbs: Breadcrumbs(),
      categorize: (_) => throw StateError('nope'),
    );
    await m.set(ConsentPurpose.crashReports, enabled: true);
    await m.crashReporter.recordError(_Boom('x'), null);
    expect(sink.calls, hasLength(1));
  });

  test('consent off: nothing reaches the sink', () async {
    await manager.set(ConsentPurpose.crashReports, enabled: false);
    await manager.crashReporter.recordError(_Boom('x'), null);
    expect(sink.calls, isEmpty);
  });

  group('breadcrumbs follow crash consent (P-L3)', () {
    late Breadcrumbs crumbs;
    late ConsentManager m;
    final crumb = Breadcrumb.navigation(ScreenName.settings);

    setUp(() {
      crumbs = Breadcrumbs();
      m = ConsentManager(
        store: InMemoryConsentStore(),
        analytics: const NoopAnalytics(),
        crashReporter: sink,
        breadcrumbs: crumbs,
      );
    });

    test('nothing is recorded while crash consent is off', () {
      crumbs.add(crumb);
      expect(crumbs.entries, isEmpty);
    });

    test('analytics consent alone does not record them', () async {
      await m.set(ConsentPurpose.analytics, enabled: true);
      crumbs.add(crumb);
      expect(crumbs.entries, isEmpty);
    });

    test('recorded while on, cleared and stopped on withdrawal', () async {
      await m.set(ConsentPurpose.crashReports, enabled: true);
      crumbs.add(crumb);
      expect(crumbs.entries, hasLength(1));
      await m.set(ConsentPurpose.crashReports, enabled: false);
      expect(crumbs.entries, isEmpty);
      crumbs.add(crumb);
      expect(crumbs.entries, isEmpty);
    });
  });
}
