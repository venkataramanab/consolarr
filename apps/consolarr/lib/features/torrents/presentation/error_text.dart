// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:l10n/l10n.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// The message and fix hint for [error] in the torrents screens: the shared
/// connection copy, except for a Transmission 403, where the host whitelist is
/// the likely cause and is named.
ErrorMessage torrentErrorMessage(AppLocalizations l10n, AppError error) {
  if (error.category == ErrorCategory.authFailed &&
      error.debugDetail == transmissionHostNotAllowedDetail) {
    return ErrorMessage(message: l10n.torHostNotAllowedMessage, hint: '');
  }
  return connectionErrorMessage(l10n, error);
}

/// The plain-language reason for [error] (never server text): an unsupported
/// action says so, a partial failure counts the torrents that failed,
/// everything else uses the shared connection copy.
String torrentErrorReason(AppLocalizations l10n, AppError error) {
  if (UnsupportedAction.isIt(error)) return l10n.torActionUnsupported;
  if (error is PartialActionFailure) {
    return l10n.torActionPartialFailed(error.failed.length, error.total);
  }
  final text = torrentErrorMessage(l10n, error);
  return '${text.message} ${text.hint}'.trim();
}
