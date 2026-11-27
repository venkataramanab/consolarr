// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/src/app_error.dart';
import 'package:core/src/result.dart';
import 'package:core/src/server_profile.dart';

/// Decides whether a request to a server may use the connection scheme.
///
/// Cleartext (http) is allowed only for servers the user explicitly opted in
/// for (SRV-07). The platform-level manifest flag cannot express this because
/// Dart's own sockets do not consult Android's network policy, so the check
/// lives here and every HTTP client factory must call it.
abstract final class CleartextPolicy {
  /// `Ok` when [profile] may be contacted over its configured scheme.
  static Result<void> check(ServerProfile profile) {
    if (profile.isSecure || profile.allowCleartext) {
      return const Result.ok(null);
    }
    return const Result.err(AppError(ErrorCategory.cleartextRefused));
  }

  /// Whether a redirect from [from] to [to] may be followed (SRV-08):
  /// same host, same scheme, and never secure -> cleartext.
  static bool isRedirectAllowed(Uri from, Uri to) =>
      from.scheme == to.scheme &&
      from.host.toLowerCase() == to.host.toLowerCase() &&
      from.port == to.port;
}
