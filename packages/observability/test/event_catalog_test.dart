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
  thing_happened:
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
        'b.yaml': _ok.split('events:')[1].replaceFirst('', 'events:'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
    expect(
      () => generateCatalog({'a.yaml': _ok.replaceFirst('[a, b]', '[a, a]')}),
      throwsA(isA<EventCatalogException>()),
    );
    expect(
      () => generateCatalog({
        'a.yaml': _ok.replaceFirst('thing_happened', 'Thing'),
      }),
      throwsA(isA<EventCatalogException>()),
    );
    expect(
      () => generateCatalog({'a.yaml': _ok.replaceFirst('Something.', '')}),
      throwsA(isA<EventCatalogException>()),
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
    expect(const ScreenViewedEvent(screen: ScreenName.serversList).parameters, {
      'screen': 'servers_list',
    });
    expect(
      const ServerAddedEvent(serviceKind: ServiceKindParam.sonarr).parameters,
      {'service_kind': 'sonarr'},
    );
    expect(
      const ConnectionTestResultEvent(serviceKind: ServiceKindParam.sonarr)
          .parameters,
      {'service_kind': 'sonarr'},
    );
    expect(
      const ConnectionTestResultEvent(
        serviceKind: ServiceKindParam.qbittorrent,
        errorCategory: ErrorCategoryParam.timeout,
        majorVersion: 4,
      ).parameters,
      {
        'service_kind': 'qbittorrent',
        'error_category': 'timeout',
        'major_version': 4,
      },
    );
    expect(
      const CertificateDecisionEvent(
        decision: CertificateDecisionParam.mismatch,
      ).parameters,
      {'decision': 'mismatch'},
    );
    expect(
      const ScreenViewedEvent(screen: ScreenName.shell).name,
      'screen_viewed',
    );
  });
}
