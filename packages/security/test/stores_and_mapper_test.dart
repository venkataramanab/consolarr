// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';

final _fp1 = CertificateFingerprint.parse('11' * 32);
final _fp2 = CertificateFingerprint.parse('22' * 32);
final _key1 = PinKey(profileId: 'a', host: 'nas.example', port: 443);
final _key2 = PinKey(profileId: 'b', host: 'nas.example', port: 443);

UserPinConfirmation _c(PinKey k, CertificateFingerprint f) =>
    UserPinConfirmation.userAccepted(key: k, fingerprint: f);

DioException _dio(DioExceptionType t, {Object? error, int? status}) =>
    DioException(
      requestOptions: RequestOptions(path: '/'),
      type: t,
      error: error,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: status,
            ),
    );

void main() {
  group('InMemorySecretStore', () {
    test('read/write/delete/deleteAll and keystore loss', () async {
      final s = InMemorySecretStore({'a': '1'});
      expect(await s.read('a'), '1');
      await s.write('b', '2');
      await s.delete('a');
      expect(await s.read('a'), isNull);
      s.simulateKeystoreLoss();
      expect(await s.read('b'), isNull);
      await s.write('c', '3');
      await s.deleteAll();
      expect(await s.read('c'), isNull);
    });
  });

  for (final (name, make) in <(String, PinStore Function())>[
    ('InMemoryPinStore', InMemoryPinStore.new),
    ('SecretBackedPinStore', () => SecretBackedPinStore(InMemorySecretStore())),
  ]) {
    group(name, () {
      test('write then read; keys are independent', () async {
        final s = make();
        expect(await s.read(_key1), isNull);
        await s.write(_key1, _fp1, _c(_key1, _fp1));
        expect(await s.read(_key1), _fp1);
        expect(await s.read(_key2), isNull);
      });

      test('write requires a confirmation covering key and fingerprint',
          () async {
        final s = make();
        expect(
          () => s.write(_key1, _fp1, _c(_key2, _fp1)),
          throwsArgumentError,
        );
        expect(
          () => s.write(_key1, _fp1, _c(_key1, _fp2)),
          throwsArgumentError,
        );
        expect(await s.read(_key1), isNull);
      });

      test('replacing a pin also needs a covering confirmation', () async {
        final s = make();
        await s.write(_key1, _fp1, _c(_key1, _fp1));
        expect(
          () => s.write(_key1, _fp2, _c(_key1, _fp1)),
          throwsArgumentError,
        );
        expect(await s.read(_key1), _fp1);
        await s.write(_key1, _fp2, _c(_key1, _fp2));
        expect(await s.read(_key1), _fp2);
      });

      test('clear requires a confirmation for the key', () async {
        final s = make();
        await s.write(_key1, _fp1, _c(_key1, _fp1));
        expect(() => s.clear(_key1, _c(_key2, _fp1)), throwsArgumentError);
        expect(await s.read(_key1), _fp1);
        await s.clear(_key1, _c(_key1, _fp2));
        expect(await s.read(_key1), isNull);
      });
    });
  }

  test('SecretBackedPinStore: a corrupt entry blocks instead of unpinning',
      () async {
    final secrets = InMemorySecretStore({_key1.storageKey: 'not-a-hash'});
    final stored = await SecretBackedPinStore(secrets).read(_key1);
    expect(stored, isNotNull);
    expect(stored, isNot(_fp1));
  });

  test('SecretBackedPinStore stores only the hex under the storage key',
      () async {
    final secrets = InMemorySecretStore();
    await SecretBackedPinStore(secrets).write(_key1, _fp1, _c(_key1, _fp1));
    expect(await secrets.read(_key1.storageKey), _fp1.hex);
  });

  group('appErrorFromDio', () {
    test('passes typed errors through (plain and wrapped)', () {
      const typed = AppError(ErrorCategory.cleartextRefused);
      expect(appErrorFromDio(typed), same(typed));
      expect(
        appErrorFromDio(_dio(DioExceptionType.unknown, error: typed)),
        same(typed),
      );
    });

    test('timeouts', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        expect(appErrorFromDio(_dio(t)).category, ErrorCategory.timeout);
      }
    });

    test('statuses', () {
      for (final (status, cat) in [
        (401, ErrorCategory.authFailed),
        (403, ErrorCategory.authFailed),
        (404, ErrorCategory.notFound),
        (500, ErrorCategory.serverError),
        (null, ErrorCategory.serverError),
      ]) {
        expect(
          appErrorFromDio(_dio(DioExceptionType.badResponse, status: status))
              .category,
          cat,
        );
      }
    });

    test('connection failures and TLS', () {
      expect(
        appErrorFromDio(
          _dio(
            DioExceptionType.connectionError,
            error: const SocketException('x'),
          ),
        ).category,
        ErrorCategory.networkUnreachable,
      );
      expect(
        appErrorFromDio(
          _dio(DioExceptionType.unknown, error: const HandshakeException('x')),
        ).category,
        ErrorCategory.tlsUntrusted,
      );
      expect(
        appErrorFromDio(_dio(DioExceptionType.badCertificate)).category,
        ErrorCategory.tlsUntrusted,
      );
      expect(
        appErrorFromDio(_dio(DioExceptionType.cancel)).category,
        ErrorCategory.networkUnreachable,
      );
      expect(
        appErrorFromDio(StateError('x')).category,
        ErrorCategory.networkUnreachable,
      );
    });
  });
}
