// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

const dot = ' · ';

/// The servers screen, for "check server settings" shortcuts.
const serversRoute = '/servers';

/// "just now", "5 minutes ago", ... for the offline banner.
String ageText(AppLocalizations l10n, Duration age) {
  if (age.inMinutes < 1) return l10n.radarrAgeJustNow;
  if (age.inHours < 1) return l10n.radarrAgeMinutes(age.inMinutes);
  if (age.inDays < 1) return l10n.radarrAgeHours(age.inHours);
  return l10n.radarrAgeDays(age.inDays);
}

/// Size with one decimal and a unit; digits localize through the ARB format.
String sizeText(AppLocalizations l10n, int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  const tb = 1024 * gb;
  if (bytes >= tb) return l10n.radarrSizeTb(bytes / tb);
  if (bytes >= gb) return l10n.radarrSizeGb(bytes / gb);
  return l10n.radarrSizeMb(bytes / mb);
}

String availabilityText(AppLocalizations l10n, Availability a) => switch (a) {
  Availability.unannounced => l10n.radarrAvailabilityUnannounced,
  Availability.comingSoon => l10n.radarrAvailabilityComingSoon,
  Availability.inCinemas => l10n.radarrAvailabilityInCinemas,
  Availability.releasedDigital => l10n.radarrAvailabilityDigital,
  Availability.releasedPhysical => l10n.radarrAvailabilityPhysical,
};

(IconData, StatusTone) availabilityStyle(Availability a) => switch (a) {
  Availability.unannounced => (Icons.help_outline, StatusTone.neutral),
  Availability.comingSoon => (Icons.schedule, StatusTone.info),
  Availability.inCinemas => (Icons.theaters_outlined, StatusTone.info),
  Availability.releasedDigital => (
    Icons.cloud_done_outlined,
    StatusTone.success,
  ),
  Availability.releasedPhysical => (Icons.album_outlined, StatusTone.success),
};

String minimumAvailabilityText(AppLocalizations l10n, MinimumAvailability m) =>
    switch (m) {
      MinimumAvailability.announced => l10n.radarrMinAnnounced,
      MinimumAvailability.inCinemas => l10n.radarrMinInCinemas,
      MinimumAvailability.released => l10n.radarrMinReleased,
      MinimumAvailability.unknown => l10n.radarrMinUnknown,
    };

String releaseTypeText(AppLocalizations l10n, ReleaseType t) => switch (t) {
  ReleaseType.cinema => l10n.radarrTypeCinema,
  ReleaseType.digital => l10n.radarrTypeDigital,
  ReleaseType.physical => l10n.radarrTypePhysical,
};

IconData releaseTypeIcon(ReleaseType t) => switch (t) {
  ReleaseType.cinema => Icons.theaters_outlined,
  ReleaseType.digital => Icons.cloud_outlined,
  ReleaseType.physical => Icons.album_outlined,
};

/// Whether the fix for [error] lives in the server settings.
bool fixedInServerSettings(AppError error) => switch (error.category) {
  ErrorCategory.authFailed ||
  ErrorCategory.notFound ||
  ErrorCategory.tlsUntrusted ||
  ErrorCategory.tlsExpired ||
  ErrorCategory.tlsPinMismatch ||
  ErrorCategory.cleartextRefused => true,
  _ => false,
};

/// Error view for [error]: cause, fix hint, retry and (when it helps) a
/// shortcut to the server settings.
Widget radarrErrorView(
  BuildContext context,
  AppError error, {
  required VoidCallback onRetry,
}) {
  final l10n = context.l10n;
  final copy = connectionErrorMessage(l10n, error);
  final fix = fixedInServerSettings(error);
  return ErrorState(
    headline: error.category == ErrorCategory.unsupportedVersion
        ? l10n.radarrErrorVersionTitle
        : l10n.radarrErrorTitle,
    message: copy.message,
    hint: copy.hint,
    retryLabel: l10n.radarrRetry,
    onRetry: onRetry,
    secondaryLabel: fix ? l10n.radarrOpenServers : null,
    onSecondary: fix ? () => GoRouter.maybeOf(context)?.go(serversRoute) : null,
  );
}

Widget radarrNoServerView(BuildContext context) {
  final l10n = context.l10n;
  return EmptyState(
    icon: Icons.dns_outlined,
    headline: l10n.radarrNoServerHeadline,
    message: l10n.radarrNoServerMessage,
    actionLabel: l10n.radarrNoServerAction,
    onAction: () => GoRouter.maybeOf(context)?.go(serversRoute),
  );
}

/// Skeleton of a vertical list (loading state of queue, calendar, ...).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({required this.padding, this.rows = 8, super.key});

  final EdgeInsets padding;
  final int rows;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.radarrLoadingLabel,
    liveRegion: true,
    child: ExcludeSemantics(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: rows,
        itemBuilder: (context, i) => const Padding(
          padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
          child: SkeletonBox(height: 72, borderRadius: ConsolarrRadii.card),
        ),
      ),
    ),
  );
}

/// The offline banner shared by every cached screen: age and reason. Writes
/// are disabled while it shows, which the banner states.
Widget offlineBanner(
  BuildContext context, {
  required DateTime fetchedAt,
  required DateTime now,
  required VoidCallback onRetry,
}) {
  final l10n = context.l10n;
  return OfflineBanner(
    message: l10n.radarrOfflineMessage,
    ageText: l10n.radarrUpdatedAgo(ageText(l10n, now.difference(fetchedAt))),
    retryLabel: l10n.radarrRetry,
    onRetry: onRetry,
  );
}

/// Tells the user why a write is unavailable (offline cached view).
void showOfflineWritesSnack(BuildContext context) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(context.l10n.radarrWritesDisabled)));
}

/// Whether the cached/offline view is showing for any Radarr data.
bool isOffline(RadarrState<Object?>? s) => s is RadarrData && s.isOffline;

/// Watches [provider] respecting the reload rule: loading and error first.
extension SafeValue<T> on AsyncValue<T> {
  /// The value only when it is current (not loading, no error).
  T? get current => isLoading || hasError ? null : value;
}

typedef RadarrRef = WidgetRef;
