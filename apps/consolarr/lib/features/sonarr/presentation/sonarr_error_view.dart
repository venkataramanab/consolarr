// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Error and no-server states shared by the calendar and missing tabs: the
/// cause and hint come from `connectionErrorMessage`, the headline from the
/// screen, with retry and (for credential/TLS problems) a settings shortcut.
class SonarrErrorView extends StatelessWidget {
  const SonarrErrorView({
    required this.title,
    required this.error,
    required this.onRetry,
    this.onOpenServers,
    super.key,
  }) : _noServer = false;

  /// An unexpected, non-[AppError] failure.
  const SonarrErrorView.unexpected({
    required this.title,
    required this.onRetry,
    super.key,
  }) : error = null,
       onOpenServers = null,
       _noServer = false;

  /// No Sonarr server is configured.
  const SonarrErrorView.noServer({required this.onOpenServers, super.key})
    : title = '',
      error = null,
      onRetry = null,
      _noServer = true;

  final String title;
  final AppError? error;
  final Future<void> Function()? onRetry;
  final VoidCallback? onOpenServers;
  final bool _noServer;

  /// Categories whose fix lives in the server settings.
  static bool _fixedInSettings(AppError e) => switch (e.category) {
    ErrorCategory.authFailed ||
    ErrorCategory.notFound ||
    ErrorCategory.tlsUntrusted ||
    ErrorCategory.tlsExpired ||
    ErrorCategory.tlsPinMismatch ||
    ErrorCategory.cleartextRefused => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_noServer) {
      return EmptyState(
        icon: Icons.dns_outlined,
        headline: l10n.sonarrNoServerHeadline,
        message: l10n.sonarrNoServerMessage,
        actionLabel: l10n.sonarrNoServerAction,
        onAction: onOpenServers,
      );
    }
    final e = error;
    final copy = e == null ? null : connectionErrorMessage(l10n, e);
    final settings = e != null && _fixedInSettings(e) && onOpenServers != null;
    return ErrorState(
      headline: title,
      message: copy?.message ?? l10n.sonarrErrorGenericMessage,
      hint: copy?.hint ?? l10n.sonarrErrorGenericHint,
      retryLabel: l10n.sonarrRetry,
      onRetry: onRetry,
      secondaryLabel: settings ? l10n.sonarrOpenServers : null,
      onSecondary: settings ? onOpenServers : null,
    );
  }
}
