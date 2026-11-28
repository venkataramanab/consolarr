// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

import '../tool/src/event_generator.dart';

Map<String, String> _yamls() => {
  for (final f in Directory('events').listSync())
    if (f is File && f.path.endsWith('.yaml'))
      f.uri.pathSegments.last: f.readAsStringSync(),
};

String _gen(Map<String, String> y) => formatWithDart(
  generateCatalog(y),
  scratchDir: Directory.systemTemp.createTempSync('gen').path,
);

const _ok = '''
enums:
  e:
    dart: E
    values: [a, b]
events:
  a_thing_happened:
    description: Something.
    params:
      kind: {type: e}
''';

void main() {
  test('generated catalog equals generator output (run melos run codegen)', () {
    final committed = File('lib/src/events/catalog.dart').readAsStringSync();
    expect(_gen(_yamls()), committed);
  });

  test('generator output is deterministic regardless of map order', () {
    final y = _yamls();
    final reversed = {for (final k in y.keys.toList().reversed) k: y[k]!};
    expect(_gen(reversed), _gen(y));
  });

  test('rejects free-text and unknown parameter types', () {
    for (final type in ['String', 'string', 'text', 'double', 'Object']) {
      final y = _ok.replaceFirst('{type: e}', '{type: $type}');
      expect(
        () => generateCatalog({'a.yaml': y}),
        throwsA(isA<EventCatalogException>()),
        reason: type,
      );
    }
  });

  test('rejects duplicate events, duplicate enum values, bad names', () {
    expect(
      () => generateCatalog({
        'a.yaml': _ok,
        // `a_thing.yaml` also accepts the prefix `a_thing_`, so the same name
        // is declared twice.
        'a_thing.yaml': _ok.split('events:')[1].replaceFirst('', 'events:'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
    expect(
      () => generateCatalog({'a.yaml': _ok.replaceFirst('[a, b]', '[a, a]')}),
      throwsA(isA<EventCatalogException>()),
    );
    expect(
      () => generateCatalog({
        'a.yaml': _ok.replaceFirst('a_thing_happened', 'A_Thing'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
    expect(
      () => generateCatalog({'a.yaml': _ok.replaceFirst('Something.', '')}),
      throwsA(isA<EventCatalogException>()),
    );
  });

  test('an event name must start with its file prefix (P-L1)', () {
    // `a_thing_happened` in a file that is not `a.yaml`.
    expect(
      () => generateCatalog({'other.yaml': _ok}),
      throwsA(
        isA<EventCatalogException>().having(
          (e) => e.message,
          'message',
          contains('must start with "other_"'),
        ),
      ),
    );
    // No prefix at all.
    expect(
      () => generateCatalog({
        'a.yaml': _ok.replaceFirst('a_thing_happened', 'thing_happened'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
    // The prefix alone, without a name after it, is not enough.
    expect(
      () => generateCatalog({
        'a.yaml': _ok.replaceFirst('a_thing_happened', 'a_'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
    // polling.yaml uses the established `poll_` prefix.
    expect(
      generateCatalog({
        'polling.yaml': _ok.replaceFirst('a_thing_happened', 'poll_x'),
      }),
      contains('PollXEvent'),
    );
    expect(
      () => generateCatalog({
        'polling.yaml': _ok.replaceFirst('a_thing_happened', 'polling_x'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
  });

  test('every catalog event carries its area prefix', () {
    const prefixes = {
      'dashboard': 'dashboard',
      'polling': 'poll',
      'radarr': 'radarr',
      'servers': 'servers',
      'settings': 'settings',
      'sonarr': 'sonarr',
      'torrents': 'torrents',
    };
    final y = _yamls();
    expect(
      y.keys.map((k) => k.replaceAll('.yaml', '')).toSet(),
      prefixes.keys.toSet(),
    );
  });

  test('enums merge across files; conflicting dart names are rejected', () {
    final out = generateCatalog({
      'a.yaml': _ok,
      'b.yaml': 'enums:\n  e:\n    values: [c]\n',
    });
    expect(out, contains("c('c')"));
    expect(
      () => generateCatalog({
        'a.yaml': _ok,
        'b.yaml': 'enums:\n  e:\n    dart: Other\n    values: [c]\n',
      }),
      throwsA(isA<EventCatalogException>()),
    );
  });

  test('catalog has no String-typed parameters (closed types only)', () {
    final src = File('lib/src/events/catalog.dart').readAsStringSync();
    final fields = RegExp(r'^\s+final (\S+) \w+;$', multiLine: true);
    final allowed = {
      'int', 'int?', 'bool', 'bool?', 'String', // enum `code` fields only
    };
    final enumNames = RegExp(
      r'^enum (\w+) \{',
      multiLine: true,
    ).allMatches(src).map((m) => m[1]!).toSet();
    // Event classes: every field type is int/bool or a generated enum.
    final eventBlocks = src.split('final class ').skip(1);
    for (final block in eventBlocks) {
      for (final m in fields.allMatches(block)) {
        final t = m[1]!.replaceAll('?', '');
        expect(
          t == 'int' || t == 'bool' || enumNames.contains(t),
          isTrue,
          reason: 'event field type $t',
        );
      }
    }
    expect(allowed, contains('String'));
  });

  test('wire codes: fromCode round-trips and names are snake_case', () {
    for (final s in ScreenName.values) {
      expect(ScreenName.fromCode(s.code), s);
    }
    expect(ScreenName.fromCode('nope'), isNull);
    expect(
      ErrorCategoryParam.values.map((e) => e.code),
      containsAll([
        'auth_failed',
        'timeout',
        'tls_pin_mismatch',
        'cleartext_refused',
        'unsupported_version',
        'not_found',
        'server_error',
        'network_unreachable',
        'parse_error',
        'tls_untrusted',
        'tls_expired',
        'redirect_refused',
        'response_too_large',
        'request_too_large',
      ]),
    );
    expect(ErrorCategoryParam.values, hasLength(14));
  });

  test('MVP events produce the documented parameters', () {
    expect(
      const ServersScreenViewedEvent(screen: ScreenName.serversList).parameters,
      {'screen': 'servers_list'},
    );
    expect(
      const ServersAddedEvent(serviceKind: ServiceKindParam.sonarr).parameters,
      {'service_kind': 'sonarr'},
    );
    expect(
      const ServersConnectionTestResultEvent(
        serviceKind: ServiceKindParam.sonarr,
      ).parameters,
      {'service_kind': 'sonarr'},
    );
    expect(
      const ServersConnectionTestResultEvent(
        serviceKind: ServiceKindParam.qbittorrent,
        errorCategory: ErrorCategoryParam.timeout,
        majorVersion: MajorVersionParam.v4,
      ).parameters,
      {
        'service_kind': 'qbittorrent',
        'error_category': 'timeout',
        'major_version': 'v4',
      },
    );
    expect(
      const ServersCertificateDecisionEvent(
        decision: CertificateDecisionParam.mismatch,
      ).parameters,
      {'decision': 'mismatch'},
    );
    expect(
      const ServersScreenViewedEvent(screen: ScreenName.shell).name,
      'servers_screen_viewed',
    );
  });
}
