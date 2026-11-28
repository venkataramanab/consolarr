// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:security/security.dart';

AppError typed(ErrorCategory c) {
  final key = PinKey(profileId: 'p', host: 'h.example', port: 443);
  final cert = CertificateDetails(
    fingerprint: CertificateFingerprint.parse('cd' * 32),
    subject: 'CN=x',
    issuer: 'CN=x',
    notBefore: DateTime.utc(2026),
    notAfter: DateTime.utc(2027),
  );
  return switch (c) {
    ErrorCategory.tlsUntrusted => CertificateDecisionRequired(
      key: key,
      certificate: cert,
    ),
    ErrorCategory.tlsExpired => CertificateExpired(key: key, certificate: cert),
    ErrorCategory.tlsPinMismatch => TlsPinMismatch(
      key: key,
      pinned: cert.fingerprint,
      presented: cert,
    ),
    _ => AppError(c),
  };
}

void main() {
  for (final locale in const [Locale('en'), Locale('ar'), Locale('en', 'XA')]) {
    test(
      'every category has a distinct message and a hint in $locale',
      () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final messages = <String>{};
        for (final c in ErrorCategory.values) {
          final m = connectionErrorMessage(l10n, typed(c));
          expect(m.message, isNotEmpty, reason: c.code);
          expect(m.hint, isNotEmpty, reason: c.code);
          messages.add(m.message);
        }
        expect(messages.length, ErrorCategory.values.length);
      },
    );
  }

  test(
    'a refused redirect tells the user to enter the final address',
    () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final hint = connectionErrorMessage(
        en,
        const AppError(ErrorCategory.redirectRefused),
      ).hint;
      expect(hint, contains('final address'));
      expect(hint, contains('scheme'));
      expect(hint, contains('port'));
      final arHint = connectionErrorMessage(
        ar,
        const AppError(ErrorCategory.redirectRefused),
      ).hint;
      expect(arHint, contains('العنوان النهائي'));
      expect(arHint, contains('منفذ'));
    },
  );

  test('needs-credentials and invalid-input get their own copy', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final plain = connectionErrorMessage(
      l10n,
      const AppError(ErrorCategory.authFailed),
    );
    final needs = connectionErrorMessage(
      l10n,
      const AppError(
        ErrorCategory.authFailed,
        debugDetail: needsCredentialsDetail,
      ),
    );
    expect(needs.message, isNot(plain.message));
    final bad = connectionErrorMessage(
      l10n,
      const AppError(
        ErrorCategory.parseError,
        debugDetail: 'address must not contain credentials',
      ),
    );
    final parse = connectionErrorMessage(
      l10n,
      const AppError(ErrorCategory.parseError),
    );
    expect(bad.message, isNot(parse.message));
  });

  test('invalid port and non-ascii host get dedicated copy', () async {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final l10n = await AppLocalizations.delegate.load(locale);
      final generic = connectionErrorMessage(
        l10n,
        const AppError(ErrorCategory.parseError),
      );
      final input = connectionErrorMessage(
        l10n,
        const AppError(
          ErrorCategory.parseError,
          debugDetail: 'invalid address',
        ),
      );
      final port = connectionErrorMessage(
        l10n,
        const AppError(ErrorCategory.parseError, debugDetail: 'invalid port'),
      );
      final host = connectionErrorMessage(
        l10n,
        const AppError(
          ErrorCategory.parseError,
          debugDetail: 'host must be ascii',
        ),
      );
      final all = {generic.message, input.message, port.message, host.message};
      expect(all, hasLength(4), reason: '$locale');
      expect(port.hint, isNot(host.hint));
    }
  });

  test('messages never echo debug details', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final m = connectionErrorMessage(
      l10n,
      const AppError(ErrorCategory.serverError, debugDetail: 'secret-detail'),
    );
    expect('${m.message}${m.hint}', isNot(contains('secret-detail')));
  });

  test('the generic sign-in hint never suggests a username and password '
      '(Sonarr and Radarr have none)', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final m = connectionErrorMessage(
      l10n,
      const AppError(ErrorCategory.authFailed),
    );
    expect(m.hint.toLowerCase(), isNot(contains('username')));
    expect(m.hint.toLowerCase(), isNot(contains('password')));
  });
}
