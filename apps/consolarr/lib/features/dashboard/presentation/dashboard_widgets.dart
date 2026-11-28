// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_format.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:consolarr/features/torrents/torrents_routes.dart'
    show torrentsRoute;
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/src/providers.dart';
import 'package:consolarr/src/router.dart' show AppRoutes;
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// "Sonarr (Living room)", or the bare service when the name is unknown.
String serviceTitle(AppLocalizations l10n, ServiceKind kind, String name) {
  final service = serviceKindLabel(l10n, kind);
  return name.isEmpty ? service : l10n.dashboardServiceName(service, name);
}

/// The service on one line and the server's own name below it, so a long or
/// right-to-left name wraps by itself instead of inside one joined string.
class ServiceHeading extends StatelessWidget {
  const ServiceHeading({required this.kind, required this.name, super.key});

  final ServiceKind kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          serviceKindLabel(context.l10n, kind),
          style: theme.textTheme.titleSmall,
        ),
        if (name.isNotEmpty) Text(name, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Opens [link] and reports it (the card and the kind of destination only).
void openDashboardLink(
  BuildContext context,
  WidgetRef ref,
  DashboardCard card,
  DashboardLink link,
) {
  ref
      .read(eventTrackerProvider)
      .track(
        DashboardCardOpenedEvent(
          card: dashboardCardParam(card),
          destination: dashboardDestinationParam(link.destination),
        ),
      );
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  switch (link.target) {
    case DashboardTarget.tab:
      router.go(link.location);
    case DashboardTarget.detail:
      router.push(link.location);
  }
}

/// Opens server setup (NAV-01).
void openSetup(BuildContext context) =>
    GoRouter.maybeOf(context)?.push(AppRoutes.onboarding);

/// One card of the dashboard: a single heading and its content.
class DashboardCardFrame extends StatelessWidget {
  const DashboardCardFrame({
    required this.heading,
    required this.child,
    super.key,
  });

  final String heading;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        container: true,
        child: Text(heading, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: ConsolarrSpacing.sm),
      child,
    ],
  );
}

/// An icon, a line of text and an optional action, for the empty and the not
/// configured states of a card. Static text: nothing a poll updates is a live
/// region.
class DashboardCardMessage extends StatelessWidget {
  const DashboardCardMessage({
    required this.icon,
    required this.headline,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String headline;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: roles.card,
        borderRadius: ConsolarrRadii.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 32, color: roles.textTertiary),
            ),
            const SizedBox(width: ConsolarrSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline, style: theme.textTheme.titleSmall),
                  if (message != null) ...[
                    const SizedBox(height: ConsolarrSpacing.xs),
                    Text(message!, style: theme.textTheme.bodyMedium),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: ConsolarrSpacing.sm),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(
                          ConsolarrSpacing.minTapTarget,
                          ConsolarrSpacing.minTapTarget,
                        ),
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A failed server inside a card: names the service, says what went wrong (the
/// copy of its category) and offers what helps: retry, the Torrents tab for a
/// Deluge host, the server editor for missing credentials. The other servers
/// of the card stay as they are.
class DashboardSliceError extends ConsumerWidget {
  const DashboardSliceError({
    required this.slice,
    required this.card,
    super.key,
  });

  final SliceFailed<Object?> slice;
  final DashboardCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final roles = context.roles;
    final theme = Theme.of(context);
    final service = serviceTitle(l10n, slice.kind, slice.serverName);
    final copy = connectionErrorMessage(l10n, slice.error, kind: slice.kind);
    final hostChoice = slice.needsHostChoice;
    final needsCredentials =
        slice.error.category == ErrorCategory.authFailed &&
        slice.error.debugDetail == needsCredentialsDetail;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: roles.card,
        borderRadius: ConsolarrRadii.card,
        border: Border.all(color: roles.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.error_outline, color: roles.error),
                ),
                const SizedBox(width: ConsolarrSpacing.sm),
                Expanded(
                  child: ServiceHeading(
                    kind: slice.kind,
                    name: slice.serverName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ConsolarrSpacing.xs),
            Text(
              hostChoice ? l10n.dashboardDelugeHostHint : copy.message,
              style: theme.textTheme.bodyMedium,
            ),
            if (!hostChoice) ...[
              const SizedBox(height: ConsolarrSpacing.xxs),
              Text(copy.hint, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: ConsolarrSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: hostChoice
                  ? TextButton(
                      style: _tapTarget,
                      onPressed: () =>
                          GoRouter.maybeOf(context)?.go(torrentsRoute),
                      child: Text(l10n.dashboardOpenTorrents),
                    )
                  : needsCredentials
                  ? TextButton(
                      style: _tapTarget,
                      onPressed: () =>
                          GoRouter.maybeOf(context)
                              ?.push(_editServerLocation(slice)),
                      child: Semantics(
                        label: l10n.dashboardSpokenJoin(
                          l10n.dashboardEditServer,
                          service,
                        ),
                        excludeSemantics: true,
                        child: Text(l10n.dashboardEditServer),
                      ),
                    )
                  : TextButton(
                      style: _tapTarget,
                      onPressed: () =>
                          ref.read(dashboardProvider.notifier).retry(card),
                      child: Semantics(
                        label: l10n.dashboardRetryFor(service),
                        excludeSemantics: true,
                        child: Text(l10n.dashboardRetry),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The editor of the failed server; the server list while the server is not
/// known yet (its id arrives with the server list).
String _editServerLocation(SliceFailed<Object?> slice) =>
    slice.serverName.isEmpty
    ? AppRoutes.servers
    : AppRoutes.serverEdit(slice.serverId);

final ButtonStyle _tapTarget = TextButton.styleFrom(
  minimumSize: const Size(
    ConsolarrSpacing.minTapTarget,
    ConsolarrSpacing.minTapTarget,
  ),
);

/// "Showing saved data ... Saved 5 minutes ago". Not a live region: a poll
/// may bring it up and it must not be announced again and again.
class DashboardCachedBanner extends StatelessWidget {
  const DashboardCachedBanner({
    required this.cachedAt,
    required this.now,
    super.key,
  });

  final DateTime cachedAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final roles = context.roles;
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: roles.raised,
          borderRadius: ConsolarrRadii.card,
          border: Border.all(color: roles.warning),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ConsolarrSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(Icons.cloud_off_outlined, color: roles.warning),
              ),
              const SizedBox(width: ConsolarrSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dashboardCachedMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      l10n.dashboardCachedAge(ageText(l10n, cachedAt, now)),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static placeholders in the shape of the content (no spinner; the shimmer
/// of [SkeletonBox] stops under reduced motion).
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({required this.carousel, super.key});

  /// Poster-shaped boxes in a row, or two row-shaped boxes.
  final bool carousel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = posterWidth(context);
    return Semantics(
      container: true,
      label: l10n.dashboardLoading,
      child: ExcludeSemantics(
        child: carousel
            ? SizedBox(
                height: width * 1.5,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  itemBuilder: (context, _) => Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: ConsolarrSpacing.sm,
                    ),
                    child: SkeletonBox(width: width, height: width * 1.5),
                  ),
                ),
              )
            : const Column(
                children: [
                  SkeletonBox(height: 72),
                  SizedBox(height: ConsolarrSpacing.sm),
                  SkeletonBox(height: 72),
                ],
              ),
      ),
    );
  }
}

/// A poster's width: it grows with the text size, up to one and a half times.
double posterWidth(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return 128 * scale.clamp(1.0, 1.5);
}
