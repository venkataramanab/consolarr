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
      c.address.text = 'https://sonarr.example';
      c.pathPrefix.text = '/a/../b';
      expect(c.validate().prefix, FieldIssue.prefixInvalid);
      c.pathPrefix.text = '/sonarr';
      c.name.text = 'Example';
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
      c.setAuthMode(AuthMode.none);
      expect(c.toDraft().credentials.apiKey, isNull);
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
