// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/reveal_tracker.dart';
import 'package:consolarr/features/servers/presentation/server_form_controller.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerFormController', () {
    late ServerFormController c;
    setUp(() => c = ServerFormController(kind: ServiceKind.sonarr));
    tearDown(() => c.dispose());

    test('validation maps each local problem to a field issue', () {
      expect(c.validate().name, FieldIssue.nameRequired);
      expect(c.validate().address, FieldIssue.addressRequired);
      c.address.text = 'not a url';
      expect(c.validate().address, FieldIssue.addressInvalid);
      c.address.text = 'https://user:pw@sonarr.example';
      expect(c.validate().address, FieldIssue.addressCredentials);
      c.address.text = 'https://sonarr.example/?apikey=abc';
      expect(c.validate().address, FieldIssue.addressQuery);
      for (final bad in ['https://sonarr.example:99999', 'https://h:0']) {
        c.address.text = bad;
        expect(c.validate().address, FieldIssue.addressPort, reason: bad);
      }
      c.address.text = 'https://münchen.example';
      expect(c.validate().address, FieldIssue.addressNonAscii);
      c.address.text = r'https://evil.example\@sonarr.example';
      expect(c.validate().address, FieldIssue.addressInvalid);
      c.address.text = 'https://sonarr.example';
      c.pathPrefix.text = '/a/../b';
      expect(c.validate().prefix, FieldIssue.prefixInvalid);
      c.pathPrefix.text = '/sonarr';
      c.name.text = 'Example';
      c.apiKey.text = 'test-key-0000';
      expect(c.validate().isValid, isTrue);
    });

    test('invalid or duplicate header names are reported', () {
      c
        ..name.text = 'Example'
        ..address.text = 'https://sonarr.example'
        ..addHeader()
        ..addHeader();
      c.headers[0].name.text = 'X-Gateway';
      c.headers[1].name.text = 'x-gateway';
      expect(c.validate().headers, FieldIssue.headerInvalid);
      c.headers[1].name.text = 'bad name';
      expect(c.validate().headers, FieldIssue.headerInvalid);
      c.headers[1].name.text = 'X-Other';
      expect(c.validate().headers, isNull);
    });

    test('headers are capped', () {
      for (var i = 0; i < 30; i++) {
        c.addHeader();
      }
      expect(c.headers.length, ServerProfile.maxHeaders);
    });

    test('empty secrets are null (keep), typed ones replace', () {
      c
        ..name.text = 'Example'
        ..address.text = 'https://sonarr.example';
      expect(c.toDraft().credentials.apiKey, isNull);
      c.apiKey.text = 'test-key-0000';
      expect(c.toDraft().credentials.apiKey, 'test-key-0000');
    });

    test('empty header values for existing names keep the stored value', () {
      final existing = existingWithHeader();
      final e = ServerFormController(existing: existing);
      addTearDown(e.dispose);
      final draft = e.toDraft(
        storedHeaders: const [HeaderEntry(name: 'x-gw', value: 'stored')],
      );
      expect(draft.credentials.headers.single.value, 'stored');
      e.headers.single.value.text = 'new';
      expect(e.toDraft().credentials.headers.single.value, 'new');
    });

    group('changing the origin of an existing server', () {
      ServerFormController editing() {
        final e = ServerFormController(
          existing: ServerEntry(
            profile: ServerProfile.parse(
              id: 's1',
              name: 'Example',
              kind: ServiceKind.sonarr,
              address: 'https://sonarr.example',
            ).valueOrNull!,
            sortOrder: 0,
          ),
        );
        addTearDown(e.dispose);
        return e;
      }

      test('is detected for scheme, host and port, not for path or case', () {
        final e = editing();
        expect(e.originChanged, isFalse);
        e.address.text = 'https://SONARR.example/tv';
        expect(e.originChanged, isFalse);
        for (final changed in [
          'http://sonarr.example',
          'https://other.example',
          'https://sonarr.example:8443',
        ]) {
          e.address.text = changed;
          expect(e.originChanged, isTrue, reason: changed);
        }
      });

      test('requires the secrets again and forgets the stored ones', () {
        final e = editing()..address.text = 'https://other.example';
        expect(e.hasStoredSecrets, isFalse);
        expect(e.validate().secrets, FieldIssue.secretsReenter);
        expect(e.validate().isValid, isFalse);
        e.apiKey.text = 'test-key-0000';
        expect(e.validate().secrets, isNull);
        expect(e.validate().isValid, isTrue);
      });

      test('stored header values are not carried to the new origin', () {
        final e = ServerFormController(existing: existingWithHeader())
          ..address.text = 'https://other.example'
          ..apiKey.text = 'test-key-0000';
        final draft = e.toDraft(
          storedHeaders: const [HeaderEntry(name: 'x-gw', value: 'stored')],
        );
        expect(draft.credentials.headers.single.value, isEmpty);
        expect(e.validate().secrets, FieldIssue.secretsReenter);
        addTearDown(e.dispose);
      });

      test('a new server never needs re-entry', () {
        c
          ..name.text = 'Example'
          ..address.text = 'https://sonarr.example';
        expect(c.originChanged, isFalse);
        expect(c.validate().secrets, isNull);
      });
    });

    group('Sonarr and Radarr credentials', () {
      ServerEntry stored(
        ServiceKind kind, {
        AuthMode mode = AuthMode.apiKey,
        bool needsCredentials = false,
        bool proxyLogin = false,
      }) => ServerEntry(
        profile: ServerProfile.parse(
          id: 's1',
          name: 'Example',
          kind: kind,
          address: 'https://host.example',
          authMode: mode,
        ).valueOrNull!,
        sortOrder: 0,
        needsCredentials: needsCredentials,
        proxyLogin: proxyLogin,
      );

      for (final kind in [ServiceKind.sonarr, ServiceKind.radarr]) {
        test('$kind offers the API key as its only auth mode', () {
          expect(authModesFor(kind), [AuthMode.apiKey]);
        });

        test('$kind: the API key is required before save and test', () {
          final f = ServerFormController(kind: kind)
            ..name.text = 'Example'
            ..address.text = 'https://host.example';
          addTearDown(f.dispose);
          expect(f.validate().apiKey, FieldIssue.apiKeyRequired);
          expect(f.validate().isValid, isFalse);
          f.apiKey.text = 'test-key-0000';
          expect(f.validate().apiKey, isNull);
          expect(f.validate().isValid, isTrue);
        });
      }

      test('a stored key may stay untouched when editing', () {
        final f = ServerFormController(existing: stored(ServiceKind.radarr));
        addTearDown(f.dispose);
        expect(f.validate().apiKey, isNull);
        expect(f.toDraft().credentials.apiKey, isNull);
      });

      test('torrent kinds never need an API key', () {
        final f = ServerFormController(kind: ServiceKind.qbittorrent)
          ..name.text = 'Example'
          ..address.text = 'https://host.example';
        addTearDown(f.dispose);
        expect(f.validate().apiKey, isNull);
        expect(f.validate().isValid, isTrue);
      });

      test('proxy login is off by default and deletes any stored login', () {
        final f = ServerFormController(kind: ServiceKind.sonarr)
          ..apiKey.text = 'test-key-0000';
        addTearDown(f.dispose);
        expect(f.proxyLogin, isFalse);
        final creds = f.toDraft().credentials;
        expect(creds.apiKey, 'test-key-0000');
        expect(creds.username, isEmpty);
        expect(creds.password, isEmpty);
      });

      test('proxy login is additive: key and login are both saved', () {
        final f = ServerFormController(kind: ServiceKind.radarr)
          ..apiKey.text = 'test-key-0000'
          ..setProxyLogin(true);
        addTearDown(f.dispose);
        expect(f.validate().proxyLogin, FieldIssue.proxyLoginRequired);
        f
          ..username.text = 'user'
          ..password.text = 'pw';
        expect(f.validate().proxyLogin, isNull);
        final draft = f.toDraft();
        expect(draft.authMode, AuthMode.apiKey);
        expect(draft.credentials.apiKey, 'test-key-0000');
        expect(draft.credentials.username, 'user');
        expect(draft.credentials.password, 'pw');
      });

      test('proxy login is arr only', () {
        final f = ServerFormController(kind: ServiceKind.deluge)
          ..setProxyLogin(true);
        addTearDown(f.dispose);
        expect(f.proxyLogin, isFalse);
      });

      test('an existing proxy login is kept when its fields stay empty', () {
        final f = ServerFormController(
          existing: stored(ServiceKind.sonarr, proxyLogin: true),
        );
        addTearDown(f.dispose);
        expect(f.proxyLogin, isTrue);
        expect(f.validate().proxyLogin, isNull);
        final creds = f.toDraft().credentials;
        expect(creds.username, isNull);
        expect(creds.password, isNull);
      });

      for (final mode in [AuthMode.basic, AuthMode.none]) {
        test('an old $mode profile opens as apiKey with the key required', () {
          final f = ServerFormController(
            existing: stored(
              ServiceKind.radarr,
              mode: mode,
              needsCredentials: true,
              proxyLogin: mode == AuthMode.basic,
            ),
          );
          addTearDown(f.dispose);
          expect(f.authMode, AuthMode.apiKey);
          expect(f.hasLegacyArrAuth, isTrue);
          expect(f.proxyLogin, mode == AuthMode.basic);
          expect(f.validate().apiKey, FieldIssue.apiKeyRequired);
          f.apiKey.text = 'test-key-0000';
          expect(f.validate().isValid, isTrue);
          final draft = f.toDraft();
          expect(draft.authMode, AuthMode.apiKey);
          expect(draft.credentials.apiKey, 'test-key-0000');
        });
      }

      test('a current arr profile shows no legacy notice', () {
        final f = ServerFormController(existing: stored(ServiceKind.sonarr));
        addTearDown(f.dispose);
        expect(f.hasLegacyArrAuth, isFalse);
      });

      test('a changed origin requires key and proxy login again', () {
        final f = ServerFormController(
          existing: stored(ServiceKind.sonarr, proxyLogin: true),
        )..address.text = 'https://other.example';
        addTearDown(f.dispose);
        expect(f.validate().apiKey, FieldIssue.apiKeyRequired);
        expect(f.validate().proxyLogin, FieldIssue.proxyLoginRequired);
        expect(f.validate().secrets, FieldIssue.secretsReenter);
      });
    });

    test('dirty tracking and markSaved', () {
      expect(c.isDirty, isFalse);
      c.name.text = 'x';
      expect(c.isDirty, isTrue);
      c.markSaved();
      expect(c.isDirty, isFalse);
    });

    test('a new server gets a stable pre-assigned id', () {
      expect(c.draftId, hasLength(32));
      expect(c.toDraft().id, c.draftId);
    });

    test('changing kind keeps a valid auth mode', () {
      c.setKind(ServiceKind.qbittorrent);
      expect(authModesFor(ServiceKind.qbittorrent), contains(c.authMode));
    });
  });

  group('RevealTracker', () {
    test('secure while any field is revealed, cleared on dispose', () {
      final screen = RecordingSecureScreen();
      final t = RevealTracker(screen);
      final a = Object();
      final b = Object();
      t.update(a, true);
      t.update(b, true);
      t.update(a, false);
      expect(screen.calls, [true]);
      t.update(b, false);
      expect(screen.calls, [true, false]);
      t.update(a, true);
      t.dispose();
      expect(screen.calls, [true, false, true, false]);
      expect(t.isSecure, isFalse);
    });
  });
}

ServerEntry existingWithHeader() => ServerEntry(
  profile: ServerProfile.parse(
    id: 's1',
    name: 'Example',
    kind: ServiceKind.sonarr,
    address: 'https://sonarr.example',
    headerNames: ['x-gw'],
  ).valueOrNull!,
  sortOrder: 0,
);
