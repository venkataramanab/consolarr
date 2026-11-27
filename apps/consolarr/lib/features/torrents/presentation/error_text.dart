// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:l10n/l10n.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// The plain-language reason for [error] (never server text): an unsupported
/// action says so, everything else uses the shared connection copy.
String torrentErrorReason(AppLocalizations l10n, AppError error) {
  if (UnsupportedAction.isIt(error)) return l10n.torActionUnsupported;
  final text = connectionErrorMessage(l10n, error);
  return '${text.message} ${text.hint}';
}
