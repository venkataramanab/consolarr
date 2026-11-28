// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/data/drift_server_repository.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/storage/pinned_markers.dart';
import 'package:consolarr/src/storage/secure_storage_reset.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';

void main() {
  late AppDatabase db;
  late InMemorySecretStore secrets;
  late DriftPinnedMarkers markers;
  late MarkedPinStore pins;

  final key = PinKey(profileId: 's1', host: 'nas.example', port: 8989);
  final print_ = CertificateFingerprint.parse('ab' * 32);

  setUp(() {
    db = AppDatabase.memory();
    secrets = InMemorySecretStore();
    markers = DriftPinnedMarkers(db);
    pins = MarkedPinStore(SecretBackedPinStore(secrets), markers);
  });
  tearDown(() => db.close());

  Future<void> pin() => pins.write(
    key,
    print_,
    UserPinConfirmation.userAccepted(key: key, fingerprint: print_),
  );

  test(
    'a server that was never pinned reads as unpinned (first use)',
    () async {
      expect(await pins.read(key), isNull);
    },
  );

  test('a pin round-trips and leaves a marker', () async {
    await pin();
    expect(await pins.read(key), print_);
    expect(await markers.isMarked(key.storageKey), isTrue);
  });

  test('the marker is written before the pin', () async {
    final order = <String>[];
    final ordered = MarkedPinStore(
      _RecordingPins(SecretBackedPinStore(secrets), order),
      _RecordingMarkers(markers, order),
    );
    await ordered.write(
      key,
      print_,
      UserPinConfirmation.userAccepted(key: key, fingerprint: print_),
    );
    expect(order, ['mark', 'pin']);
  });

  test('a failing marker store leaves no pin behind', () async {
    final failing = MarkedPinStore(
      SecretBackedPinStore(secrets),
      _RecordingMarkers(markers, [], failMark: true),
    );
    await expectLater(
      failing.write(
        key,
        print_,
        UserPinConfirmation.userAccepted(key: key, fingerprint: print_),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await SecretBackedPinStore(secrets).read(key), isNull);
  });

  test('a pin store that fails after the marker reads as a mismatch', () async {
    final failing = MarkedPinStore(
      _RecordingPins(SecretBackedPinStore(secrets), [], fail: true),
      markers,
    );
    await expectLater(
      failing.write(
        key,
        print_,
        UserPinConfirmation.userAccepted(key: key, fingerprint: print_),
      ),
      throwsA(isA<StateError>()),
    );
    final read = await pins.read(key);
    expect(
      read,
      isNotNull,
      reason: 'a marker without a pin is never first use',
    );
    expect(
      decidePin(presented: print_, pinned: read!, chainValid: true).allowed,
      isFalse,
    );
  });

  test('a pin saved before markers existed gets one on first read', () async {
    await SecretBackedPinStore(secrets).write(
      key,
      print_,
      UserPinConfirmation.userAccepted(key: key, fingerprint: print_),
    );
    expect(await markers.isMarked(key.storageKey), isFalse);
    expect(await pins.read(key), print_);
    expect(await markers.isMarked(key.storageKey), isTrue);
    secrets.simulateKeystoreLoss();
    expect(await pins.read(key), isNot(print_));
  });

  test('marker without a pin is a mismatch, never first use', () async {
    await pin();
    secrets.simulateKeystoreLoss();
    final read = await pins.read(key);
    expect(read, isNotNull);
    expect(read, isNot(print_));
    // No certificate hashes to the unmatchable value.
    expect(
      decidePin(presented: print_, pinned: read!, chainValid: true).allowed,
      isFalse,
    );
  });

  test('an unreadable store still throws (fail closed)', () async {
    await pin();
    secrets.unavailable = true;
    await expectLater(pins.read(key), throwsA(isA<SecretStoreUnavailable>()));
  });

  test('an explicit clear removes the marker too', () async {
    await pin();
    await pins.clear(
      key,
      UserPinConfirmation.userAccepted(key: key, fingerprint: print_),
    );
    expect(await pins.read(key), isNull);
    expect(await markers.isMarked(key.storageKey), isFalse);
  });

  test('deleting the server removes its marker', () async {
    final repo = DriftServerRepository(
      db: db,
      secrets: secrets,
      cache: DriftPayloadCache(db),
    );
    final saved = (await repo.save(
      const ServerDraft(
        id: 's1',
        name: 'Example',
        kind: ServiceKind.sonarr,
        address: 'https://nas.example:8989',
        pathPrefix: '',
        authMode: AuthMode.apiKey,
        allowCleartext: false,
        credentials: ServerCredentials(apiKey: 'test-key-0000'),
      ),
    )).valueOrNull!;
    await pin();
    await repo.delete(saved.profile.id);
    expect(await markers.isMarked(key.storageKey), isFalse);
  });

  group('user-confirmed reset', () {
    test(
      'clears secrets, pins and markers; servers need credentials',
      () async {
        final repo = DriftServerRepository(
          db: db,
          secrets: secrets,
          cache: DriftPayloadCache(db),
        );
        final saved = (await repo.save(
          const ServerDraft(
            id: 's1',
            name: 'Example',
            kind: ServiceKind.sonarr,
            address: 'https://nas.example:8989',
            pathPrefix: '',
            authMode: AuthMode.apiKey,
            allowCleartext: false,
            credentials: ServerCredentials(apiKey: 'test-key-0000'),
          ),
        )).valueOrNull!;
        await pin();
        expect(saved.needsCredentials, isFalse);
        final before = await repo.watchConnectionKey(ServiceKind.sonarr).first;

        await SecureStorageReset(
          secrets: secrets,
          markers: markers,
          db: db,
        ).reset();

        expect((await repo.find('s1'))!.needsCredentials, isTrue);
        expect(await secrets.read(key.storageKey), isNull);
        expect(await markers.isMarked(key.storageKey), isFalse);
        expect(await pins.read(key), isNull);
        final after = await repo.watchConnectionKey(ServiceKind.sonarr).first;
        expect(after.revision, greaterThan(before.revision));
      },
    );

    test('a failed clear keeps the markers', () async {
      await pin();
      final failing = _FailingClear();
      await expectLater(
        SecureStorageReset(secrets: failing, markers: markers, db: db).reset(),
        throwsA(isA<SecretStoreUnavailable>()),
      );
      expect(await markers.isMarked(key.storageKey), isTrue);
    });
  });
}

class _FailingClear extends InMemorySecretStore {
  @override
  Future<void> deleteAll() async => throw const SecretStoreUnavailable();
}

class _RecordingPins implements PinStore {
  _RecordingPins(this._inner, this._order, {this.fail = false});
  final PinStore _inner;
  final List<String> _order;
  final bool fail;

  @override
  Future<CertificateFingerprint?> read(PinKey key) => _inner.read(key);

  @override
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  ) async {
    _order.add('pin');
    if (fail) throw StateError('pin write failed');
    await _inner.write(key, fingerprint, confirmation);
  }

  @override
  Future<void> clear(PinKey key, UserPinConfirmation confirmation) =>
      _inner.clear(key, confirmation);
}

class _RecordingMarkers implements PinnedMarkers {
  _RecordingMarkers(this._inner, this._order, {this.failMark = false});
  final PinnedMarkers _inner;
  final List<String> _order;
  final bool failMark;

  @override
  Future<bool> isMarked(String pinKey) => _inner.isMarked(pinKey);

  @override
  Future<void> mark(String pinKey) async {
    _order.add('mark');
    if (failMark) throw StateError('marker write failed');
    await _inner.mark(pinKey);
  }

  @override
  Future<void> unmark(String pinKey) => _inner.unmark(pinKey);

  @override
  Future<void> clear() => _inner.clear();
}
