// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/src/pin_key.dart';
import 'package:security/src/pin_policy.dart';
import 'package:security/src/pin_store.dart';

/// Creates every HTTP client the app uses to talk to user servers (and to
/// load their images), so all traffic obeys one trust policy.
///
/// Contract for implementations (W3):
///  * platform trust by default; hostname verification always on;
///  * self-signed support only via trust-on-first-use pinning with a visible
///    fingerprint, mismatch blocking (`tls_pin_mismatch`) and explicit
///    re-trust (SRV-06). The pin contract:
///      - pins are keyed by [PinKey] (profile id, normalised host, explicit
///        port) and **checked on every TLS connection**, not only when the
///        platform rejects the chain (the bad-certificate callback alone would
///        miss a CA-signed impersonation of a pinned server; also hook the
///        connection-established path). Use [decidePin];
///      - with no pin and an untrusted chain the callback returns **false**;
///        the UI may then offer the TOFU dialog;
///      - a pin is only written through `PinStore.write` with a
///        [UserPinConfirmation] covering that exact key and fingerprint;
///  * refuse plain http unless [ServerProfile.allowCleartext] (see
///    `CleartextPolicy`), failing with `cleartext_refused`;
///  * same-host, same-scheme redirects only, stripping auth otherwise.
///
/// This file is the ONLY place allowed to use `badCertificateCallback`
/// (enforced by the `consolarr_bad_certificate_callback` lint). The interface
/// itself needs none; the TOFU implementation will live here.
abstract interface class SecureHttpClientFactory {
  /// Returns a [Dio] configured for [profile].
  ///
  /// Credentials are attached by the caller from the `SecretStore`, never
  /// embedded in the URL.
  Dio create(ServerProfile profile);
}
