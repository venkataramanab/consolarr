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
}

/// All current problems of the form (empty map = valid).
class FormIssues {
  const FormIssues({this.name, this.address, this.prefix, this.headers});

  final FieldIssue? name;
  final FieldIssue? address;
  final FieldIssue? prefix;
  final FieldIssue? headers;

  bool get isValid =>
      name == null && address == null && prefix == null && headers == null;
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
      authMode =
          existing?.profile.authMode ??
          defaultAuthModeFor(kind ?? supportedServiceKinds.first),
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

  /// Whether the address is plain http.
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
    );
  }

  String? _secret(TextEditingController c) => c.text.isEmpty ? null : c.text;

  /// The values to save. Empty secret fields are `null` (keep what is stored);
  /// header values left empty for an existing header name are filled from
  /// [storedHeaders] so they are kept too.
  ServerDraft toDraft({List<HeaderEntry> storedHeaders = const []}) {
    final stored = {
      for (final h in storedHeaders) h.name.toLowerCase(): h.value,
    };
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
        username: authMode == AuthMode.basic ? _secret(username) : null,
        password: authMode == AuthMode.basic ? _secret(password) : null,
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
  bool get hasStoredSecrets => _existing != null && !_existing.needsCredentials;

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
