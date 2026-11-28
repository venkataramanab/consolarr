// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// What is wrong with one field. The widgets map these to localized text.
enum FieldIssue {
  nameRequired,
  addressRequired,
  addressInvalid,
  addressCredentials,
  addressQuery,
  addressPort,
  addressNonAscii,
  prefixInvalid,
  headerInvalid,
  secretsReenter,

  /// Sonarr and Radarr need their API key.
  apiKeyRequired,

  /// The reverse-proxy login is on but incomplete.
  proxyLoginRequired,
}

/// All current problems of the form (empty map = valid).
class FormIssues {
  const FormIssues({
    this.name,
    this.address,
    this.prefix,
    this.headers,
    this.secrets,
    this.apiKey,
    this.proxyLogin,
  });

  final FieldIssue? name;
  final FieldIssue? address;
  final FieldIssue? prefix;
  final FieldIssue? headers;

  /// The origin changed but the secrets were not entered again.
  final FieldIssue? secrets;

  /// Sonarr or Radarr without an API key (typed or stored).
  final FieldIssue? apiKey;

  /// Reverse-proxy login switched on without a username or password.
  final FieldIssue? proxyLogin;

  bool get isValid =>
      name == null &&
      address == null &&
      prefix == null &&
      headers == null &&
      secrets == null &&
      apiKey == null &&
      proxyLogin == null;
}

/// One custom header row.
class HeaderField {
  HeaderField({String name = ''})
    : name = TextEditingController(text: name),
      value = TextEditingController();

  final TextEditingController name;
  final TextEditingController value;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

/// State of the server form shared by the editor and onboarding.
///
/// Secrets are never prefilled when editing: an empty secret field keeps the
/// stored value (see [toDraft]). The controller owns its text controllers.
class ServerFormController extends ChangeNotifier {
  ServerFormController({ServiceKind? kind, ServerEntry? existing})
    : _existing = existing,
      draftId = existing?.profile.id ?? _newDraftId(),
      kind = existing?.profile.kind ?? kind ?? supportedServiceKinds.first,
      authMode = _initialAuthMode(existing, kind),
      proxyLogin = existing?.proxyLogin ?? false,
      allowCleartext = existing?.profile.allowCleartext ?? false,
      name = TextEditingController(text: existing?.profile.name),
      address = TextEditingController(
        text: existing?.profile.address.toString(),
      ),
      pathPrefix = TextEditingController(text: existing?.profile.pathPrefix) {
    for (final h in existing?.profile.headerNames ?? const <String>[]) {
      headers.add(HeaderField(name: h));
    }
    for (final c in [name, address, pathPrefix, apiKey, username, password]) {
      c.addListener(_changed);
    }
    _baseline = _fingerprint();
  }

  /// Sonarr and Radarr profiles saved in the old `basic` or `none` mode open
  /// as `apiKey` (the only arr mode); [hasLegacyArrAuth] explains why.
  static AuthMode _initialAuthMode(ServerEntry? existing, ServiceKind? kind) {
    final stored = existing?.profile;
    if (stored == null) {
      return defaultAuthModeFor(kind ?? supportedServiceKinds.first);
    }
    return authModesFor(stored.kind).contains(stored.authMode)
        ? stored.authMode
        : defaultAuthModeFor(stored.kind);
  }

  static String _newDraftId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  final ServerEntry? _existing;

  /// Id of the server being edited, or the id a new server will get. Fixing it
  /// up front lets a certificate pin made during the connection test belong
  /// to the server that is saved afterwards.
  final String draftId;

  bool get isEditing => _existing != null;
  ServerEntry? get existing => _existing;

  ServiceKind kind;
  AuthMode authMode;
  bool allowCleartext;

  /// Sonarr/Radarr only: send the typed username and password as HTTP Basic
  /// to a reverse proxy, in addition to the API key.
  bool proxyLogin;

  /// The server was saved by an older version in a mode the API cannot use
  /// (username and password, or none): the editor says the key is required.
  bool get hasLegacyArrAuth => _existing?.isLegacyArrAuth ?? false;

  final TextEditingController name;
  final TextEditingController address;
  final TextEditingController pathPrefix;
  final TextEditingController apiKey = TextEditingController();
  final TextEditingController username = TextEditingController();
  final TextEditingController password = TextEditingController();
  final List<HeaderField> headers = [];

  /// Fields the user has touched (validation errors show for these, or for all
  /// after [showAllErrors]).
  final Set<String> touched = {};
  bool _showAll = false;
  late String _baseline;

  void _changed() => notifyListeners();

  String _fingerprint() => [
    kind.name,
    authMode.name,
    proxyLogin,
    allowCleartext,
    name.text,
    address.text,
    pathPrefix.text,
    apiKey.text,
    username.text,
    password.text,
    for (final h in headers) '${h.name.text}=${h.value.text}',
  ].join('\u0000');

  /// Whether anything changed since creation (drives the discard dialog).
  bool get isDirty => _fingerprint() != _baseline;

  void markSaved() => _baseline = _fingerprint();

  void setKind(ServiceKind value) {
    kind = value;
    if (!authModesFor(value).contains(authMode)) {
      authMode = defaultAuthModeFor(value);
    }
    if (!value.isArr) proxyLogin = false;
    notifyListeners();
  }

  void setProxyLogin(bool value) {
    proxyLogin = value && kind.isArr;
    notifyListeners();
  }

  void setAuthMode(AuthMode value) {
    authMode = value;
    notifyListeners();
  }

  void setAllowCleartext(bool value) {
    allowCleartext = value;
    notifyListeners();
  }

  void addHeader() {
    if (headers.length >= ServerProfile.maxHeaders) return;
    headers.add(HeaderField());
    notifyListeners();
  }

  void removeHeader(int index) {
    headers.removeAt(index).dispose();
    notifyListeners();
  }

  void touch(String field) {
    if (touched.add(field)) notifyListeners();
  }

  void showAllErrors() {
    _showAll = true;
    notifyListeners();
  }

  bool shows(String field) => _showAll || touched.contains(field);

  /// Whether the typed address has a different origin (scheme, host or port)
  /// than the stored server. Stored secrets must then be entered again: they
  /// are never sent to a changed origin, so they are neither kept nor reused
  /// (not by save, and not by the connection test).
  bool get originChanged {
    final old = _existing?.profile.address;
    final typed = Uri.tryParse(address.text.trim());
    if (old == null || typed == null || !typed.hasAuthority) return false;
    return typed.scheme.toLowerCase() != old.scheme ||
        typed.host.toLowerCase() != old.host.toLowerCase() ||
        typed.port != old.port;
  }

  /// Whether the typed address is plain http.
  bool get addressIsHttp =>
      Uri.tryParse(address.text.trim())?.scheme.toLowerCase() == 'http';

  /// Validates the form with the same rules the repository applies.
  FormIssues validate() {
    final nameIssue = name.text.trim().isEmpty ? FieldIssue.nameRequired : null;
    FieldIssue? addressIssue;
    FieldIssue? prefixIssue;
    FieldIssue? headerIssue;
    if (address.text.trim().isEmpty) {
      addressIssue = FieldIssue.addressRequired;
    } else {
      final r = ServerProfile.parse(
        id: draftId,
        name: 'x',
        kind: kind,
        address: address.text,
        pathPrefix: pathPrefix.text,
        headerNames: [for (final h in headers) h.name.text.trim()],
      );
      final detail = r.errorOrNull?.debugDetail;
      switch (detail) {
        case 'invalid address':
          addressIssue = FieldIssue.addressInvalid;
        case 'address must not contain credentials':
          addressIssue = FieldIssue.addressCredentials;
        case 'address must not contain a query string':
          addressIssue = FieldIssue.addressQuery;
        case 'invalid port':
          addressIssue = FieldIssue.addressPort;
        case 'host must be ascii':
          addressIssue = FieldIssue.addressNonAscii;
        case 'invalid path prefix':
          prefixIssue = FieldIssue.prefixInvalid;
        case 'invalid headers':
          headerIssue = FieldIssue.headerInvalid;
      }
    }
    return FormIssues(
      name: nameIssue,
      address: addressIssue,
      prefix: prefixIssue,
      headers: headerIssue,
      secrets: addressIssue == null && _missingSecretsAfterOriginChange
          ? FieldIssue.secretsReenter
          : null,
      apiKey: _apiKeyMissing ? FieldIssue.apiKeyRequired : null,
      proxyLogin: _proxyLoginIncomplete ? FieldIssue.proxyLoginRequired : null,
    );
  }

  /// The stored secrets stay usable (no origin change).
  ServerEntry? get _usableStored => originChanged ? null : _existing;

  /// Whether Sonarr/Radarr would be saved or tested without any API key. A
  /// stored key counts; a legacy `basic`/`none` profile has none stored.
  bool get _apiKeyMissing =>
      kind.isArr &&
      apiKey.text.isEmpty &&
      (_usableStored?.needsCredentials ?? true);

  bool get _proxyLoginIncomplete =>
      kind.isArr &&
      proxyLogin &&
      !(_usableStored?.proxyLogin ?? false) &&
      (username.text.isEmpty || password.text.isEmpty);

  bool get _missingSecretsAfterOriginChange {
    if (!originChanged) return false;
    final missing =
        switch (authMode) {
          AuthMode.none => false,
          AuthMode.apiKey => apiKey.text.isEmpty,
          AuthMode.basic => username.text.isEmpty || password.text.isEmpty,
        } ||
        (kind.isArr &&
            proxyLogin &&
            (username.text.isEmpty || password.text.isEmpty));
    return missing ||
        headers.any(
          (h) => h.name.text.trim().isNotEmpty && h.value.text.isEmpty,
        );
  }

  String? _secret(TextEditingController c) => c.text.isEmpty ? null : c.text;

  /// The values to save. Empty secret fields are `null` (keep what is stored);
  /// header values left empty for an existing header name are filled from
  /// [storedHeaders] so they are kept too.
  ServerDraft toDraft({List<HeaderEntry> storedHeaders = const []}) {
    // Never carry stored header values over to a changed origin.
    final stored = originChanged
        ? const <String, String>{}
        : {for (final h in storedHeaders) h.name.toLowerCase(): h.value};
    return ServerDraft(
      id: draftId,
      name: name.text.trim(),
      kind: kind,
      address: address.text.trim(),
      pathPrefix: pathPrefix.text.trim(),
      authMode: authMode,
      allowCleartext: allowCleartext,
      credentials: ServerCredentials(
        apiKey: authMode == AuthMode.apiKey ? _secret(apiKey) : null,
        // Arr: the proxy login is optional; switching it off deletes it ('').
        username: kind.isArr
            ? (proxyLogin ? _secret(username) : '')
            : authMode == AuthMode.basic
            ? _secret(username)
            : null,
        password: kind.isArr
            ? (proxyLogin ? _secret(password) : '')
            : authMode == AuthMode.basic
            ? _secret(password)
            : null,
        headers: [
          for (final h in headers)
            if (h.name.text.trim().isNotEmpty)
              HeaderEntry(
                name: h.name.text.trim(),
                value: h.value.text.isNotEmpty
                    ? h.value.text
                    : stored[h.name.text.trim().toLowerCase()] ?? '',
              ),
        ],
      ),
    );
  }

  /// Whether a stored secret exists the user may leave untouched.
  bool get hasStoredSecrets =>
      _existing != null && !_existing.needsCredentials && !originChanged;

  @override
  void dispose() {
    for (final c in [name, address, pathPrefix, apiKey, username, password]) {
      c.removeListener(_changed);
      c.dispose();
    }
    for (final h in headers) {
      h.dispose();
    }
    super.dispose();
  }
}
