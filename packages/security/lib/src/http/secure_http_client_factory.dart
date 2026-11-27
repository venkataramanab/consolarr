// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:security/src/certificate.dart';
import 'package:security/src/http/http_limits.dart';
import 'package:security/src/http/redirect_policy.dart';
import 'package:security/src/pin_key.dart';
import 'package:security/src/pin_policy.dart';
import 'package:security/src/pin_store.dart';

/// Creates every HTTP client the app uses to talk to user servers (and to
/// load their images), so all traffic obeys one trust policy.
///
/// Contract for implementations:
///  * platform trust by default; hostname verification always on;
///  * self-signed support only via trust-on-first-use pinning with a visible
///    fingerprint, mismatch blocking (`tls_pin_mismatch`) and explicit
///    re-trust (SRV-06). Pins are keyed by [PinKey] and **checked on every
///    TLS connection, before any request bytes are sent**;
///  * refuse plain http unless [ServerProfile.allowCleartext] (see
///    `CleartextPolicy`), failing with `cleartext_refused`;
///  * same-origin redirects only keep credentials (SRV-08).
///
/// This file is the ONLY place allowed to use `badCertificateCallback`
/// (enforced by the `consolarr_bad_certificate_callback` lint).
abstract interface class SecureHttpClientFactory {
  /// Returns a [Dio] configured for [profile].
  ///
  /// Credentials are attached by the caller from the `SecretStore`, never
  /// embedded in the URL.
  Dio create(ServerProfile profile);
}

/// The production [SecureHttpClientFactory].
///
/// ## TLS mechanism
///
/// `dart:io` only calls `badCertificateCallback` for chains the platform
/// rejects, so a callback alone would miss a CA-signed impersonation of a
/// pinned server. Instead the adapter keeps one `HttpClient` per *pin state*
/// and picks it per request, after reading the [PinStore]:
///
///  * **pinned**: a client with an *empty* trust set
///    (`withTrustedRoots: false`). Every handshake therefore reaches
///    `badCertificateCallback`, which compares the SHA-256 of the presented
///    DER with the pin ([decidePin]). Only the exact pinned certificate
///    completes the handshake; anything else (self-signed or CA-valid) aborts
///    it before a single HTTP byte, so API keys never reach an impersonator.
///    The exact certificate stands in for host-name verification.
///  * **unpinned**: platform roots (plus [additionalTrustedRootsPem], for
///    tests and custom CAs). `dart:io` verifies the chain, validity and host
///    name. If it rejects, the callback only *records* the presented
///    certificate and returns `false`; the adapter then reports
///    [CertificateDecisionRequired] (or [CertificateExpired]).
///
/// Because the client is chosen per request, a pin written after the user
/// accepts applies to the next request without recreating the [Dio]; and a
/// pooled keep-alive connection can never outlive the pin state it was
/// verified under.
///
/// Typed errors are delivered in `DioException.error`; map them with
/// `appErrorFromDio`.
class DefaultSecureHttpClientFactory implements SecureHttpClientFactory {
  DefaultSecureHttpClientFactory({
    required this.pins,
    this.limits = const HttpLimits(),
    this.additionalTrustedRootsPem,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PinStore pins;
  final HttpLimits limits;

  /// PEM bytes of extra trust anchors for *unpinned* servers. The app passes
  /// nothing; tests use it for a local CA.
  final List<int>? additionalTrustedRootsPem;
  final DateTime Function() _clock;

  @override
  Dio create(ServerProfile profile) {
    final dio = Dio(
      BaseOptions(
        baseUrl: profile.baseUri.toString(),
        connectTimeout: limits.connectTimeout,
        sendTimeout: limits.sendTimeout,
        receiveTimeout: limits.receiveTimeout,
      ),
    );
    dio.httpClientAdapter = _SecureAdapter(
      profile: profile,
      pins: pins,
      limits: limits,
      roots: additionalTrustedRootsPem,
      clock: _clock,
    );
    return dio;
  }
}

const _redirectStatuses = {301, 302, 303, 307, 308};

DioException _fail(RequestOptions options, AppError error) => DioException(
  requestOptions: options,
  error: error,
  type: DioExceptionType.unknown,
  message: error.category.code,
);

/// The total time budget of one request (all redirect hops and the body).
class _Deadline {
  _Deadline(this.budget) : _start = Stopwatch()..start();

  final Duration budget;
  final Stopwatch _start;

  Duration get remaining {
    final left = budget - _start.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  DioException error(RequestOptions options) => _fail(
    options,
    const AppError(
      ErrorCategory.timeout,
      debugDetail: 'request deadline exceeded',
    ),
  );
}

class _SecureAdapter implements HttpClientAdapter {
  _SecureAdapter({
    required this.profile,
    required this.pins,
    required this.limits,
    required this.roots,
    required this.clock,
  });

  final ServerProfile profile;
  final PinStore pins;
  final HttpLimits limits;
  final List<int>? roots;
  final DateTime Function() clock;

  final Map<String, IOHttpClientAdapter> _adapters = {};

  /// Last certificate presented per `host:port`, written by the callback.
  final Map<String, CertificateDetails> _presented = {};

  late final Set<String> _origins = {
    for (final u in [profile.address, profile.alternateAddress])
      if (u != null) _hostPort(u.host, u.port),
  };

  static String _hostPort(String host, int port) =>
      '${host.toLowerCase()}:$port';

  static CertificateDetails _details(X509Certificate cert) =>
      CertificateDetails(
        fingerprint: CertificateFingerprint.parse(
          sha256.convert(cert.der).toString(),
        ),
        subject: cert.subject,
        issuer: cert.issuer,
        notBefore: cert.startValidity,
        notAfter: cert.endValidity,
      );

  IOHttpClientAdapter _adapterFor(CertificateFingerprint? pinned) =>
      _adapters.putIfAbsent(
        pinned?.hex ?? '-',
        () => IOHttpClientAdapter(createHttpClient: () => _newClient(pinned)),
      );

  HttpClient _newClient(CertificateFingerprint? pinned) {
    final context = SecurityContext(withTrustedRoots: pinned == null);
    if (pinned == null && roots != null) {
      context.setTrustedCertificatesBytes(roots!);
    }
    final client = HttpClient(context: context);
    client.badCertificateCallback = (cert, host, port) {
      final details = _details(cert);
      _presented[_hostPort(host, port)] = details;
      if (pinned == null) return false;
      return decidePin(
        presented: details.fingerprint,
        pinned: pinned,
        chainValid: false,
      ).allowed;
    };
    return client;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final maxBytes =
        options.extra[maxResponseBytesKey] as int? ?? limits.maxResponseBytes;
    // One deadline for the whole request: every hop and the body stream.
    final deadline = _Deadline(limits.requestDeadline);
    var current = options.copyWith(followRedirects: false);
    var stream = requestStream;
    var hops = 0;

    while (true) {
      final uri = current.uri;
      if (hops == 0) _checkFirstHop(current, uri);

      final response = await _send(current, uri, stream, cancelFuture).timeout(
        deadline.remaining,
        onTimeout: () => throw deadline.error(current),
      );
      final status = response.statusCode;
      final location = response.headers['location']?.firstOrNull;
      if (!_redirectStatuses.contains(status) || location == null) {
        return _limited(response, current, maxBytes, deadline);
      }

      unawaited(response.stream.listen((_) {}).cancel());
      if (++hops > limits.maxRedirects) {
        throw _fail(current, const AppError(ErrorCategory.redirectRefused));
      }
      final Uri target;
      try {
        target = uri.resolve(location);
      } on FormatException {
        throw _fail(current, const AppError(ErrorCategory.redirectRefused));
      }
      final decision = decideRedirect(
        from: uri,
        to: target,
        status: status,
        method: current.method,
        profileHost: profile.address.host,
        allowCleartext: profile.allowCleartext,
      );
      switch (decision) {
        case RedirectRefuse(:final error):
          throw _fail(current, error);
        case RedirectFollow(:final keepHeaders, :final toGet):
          final headers = keepHeaders
              ? {...current.headers}
              : stripUnsafeHeaders(current.headers);
          if (toGet) {
            headers
              ..removeWhere((k, _) => k.toLowerCase() == 'content-type')
              ..removeWhere((k, _) => k.toLowerCase() == 'content-length');
          }
          current = current.copyWith(
            path: target.toString(),
            queryParameters: <String, dynamic>{},
            method: toGet ? 'GET' : current.method,
            headers: headers,
          );
          if (toGet) {
            current.data = null;
            stream = null;
          }
      }
    }
  }

  void _checkFirstHop(RequestOptions options, Uri uri) {
    if (!_origins.contains(_hostPort(uri.host, uri.port))) {
      throw _fail(
        options,
        const AppError(
          ErrorCategory.redirectRefused,
          debugDetail: 'request to an origin other than the server',
        ),
      );
    }
    if (uri.scheme == 'http' && !profile.allowCleartext) {
      throw _fail(options, const AppError(ErrorCategory.cleartextRefused));
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw _fail(options, const AppError(ErrorCategory.parseError));
    }
  }

  Future<ResponseBody> _send(
    RequestOptions options,
    Uri uri,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = PinKey(profileId: profile.id, host: uri.host, port: uri.port);
    CertificateFingerprint? pinned;
    try {
      pinned = uri.scheme == 'https' ? await pins.read(key) : null;
    } on Object {
      throw _fail(
        options,
        const AppError(
          ErrorCategory.networkUnreachable,
          debugDetail: 'pin store unavailable',
        ),
      );
    }
    final hostPort = _hostPort(uri.host, uri.port);
    _presented.remove(hostPort);
    try {
      return await _adapterFor(pinned)
          .fetch(options, requestStream, cancelFuture);
    } on Object catch (e) {
      final cause = e is DioException ? e.error : e;
      if (cause is HandshakeException || cause is TlsException) {
        throw _fail(options, _tlsError(key, pinned, _presented[hostPort]));
      }
      rethrow;
    }
  }

  AppError _tlsError(
    PinKey key,
    CertificateFingerprint? pinned,
    CertificateDetails? presented,
  ) {
    if (presented == null) {
      return const AppError(
        ErrorCategory.tlsUntrusted,
        debugDetail: 'TLS handshake failed',
      );
    }
    if (pinned != null) {
      return TlsPinMismatch(key: key, pinned: pinned, presented: presented);
    }
    final now = clock();
    if (presented.isExpiredAt(now) || presented.isNotYetValidAt(now)) {
      return CertificateExpired(key: key, certificate: presented);
    }
    return CertificateDecisionRequired(key: key, certificate: presented);
  }

  ResponseBody _limited(
    ResponseBody response,
    RequestOptions options,
    int maxBytes,
    _Deadline deadline,
  ) {
    final declared = int.tryParse(
      response.headers[Headers.contentLengthHeader]?.firstOrNull ?? '',
    );
    final tooLarge = _fail(
      options,
      const AppError(ErrorCategory.responseTooLarge),
    );
    if (declared != null && declared > maxBytes) {
      unawaited(response.stream.listen((_) {}).cancel());
      throw tooLarge;
    }

    // Counts bytes and enforces the total deadline while the body streams (a
    // slow drip keeps resetting the per-chunk receive timeout).
    final controller = StreamController<Uint8List>();
    StreamSubscription<Uint8List>? subscription;
    Timer? timer;
    void abort(Object error) {
      timer?.cancel();
      final sub = subscription;
      subscription = null;
      if (sub != null) unawaited(sub.cancel());
      if (!controller.isClosed) {
        controller.addError(error);
        unawaited(controller.close());
      }
    }

    controller.onListen = () {
      var total = 0;
      timer = Timer(deadline.remaining, () => abort(deadline.error(options)));
      subscription = response.stream.listen(
        (chunk) {
          total += chunk.length;
          if (total > maxBytes) {
            abort(tooLarge);
          } else if (!controller.isClosed) {
            controller.add(chunk);
          }
        },
        onError: (Object e, StackTrace st) {
          timer?.cancel();
          if (!controller.isClosed) controller.addError(e, st);
        },
        onDone: () {
          timer?.cancel();
          if (!controller.isClosed) unawaited(controller.close());
        },
      );
    };
    controller.onPause = () {
      subscription?.pause();
    };
    controller.onResume = () {
      subscription?.resume();
    };
    controller.onCancel = () {
      timer?.cancel();
      return subscription?.cancel();
    };

    return ResponseBody(
      controller.stream,
      response.statusCode,
      headers: response.headers,
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
    );
  }

  @override
  void close({bool force = false}) {
    for (final a in _adapters.values) {
      a.close(force: force);
    }
  }
}
