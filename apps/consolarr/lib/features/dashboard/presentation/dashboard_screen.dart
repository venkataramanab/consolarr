// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/presentation/activity_card.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_widgets.dart';
import 'package:consolarr/features/dashboard/presentation/media_carousel.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/shared/polling/poll_scheduler.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/router.dart' show AppRoutes;
import 'package:design_system/design_system.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The home screen (DSH-01): activity, upcoming and recent downloads, always
/// in that order. Read-only; never writes to a server.
///
/// One scheduler ticks about every 15 seconds while the screen is visible
/// (resumed, in the selected tab, on top, unlocked) and cancels its timer
/// otherwise.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  late final PollScheduler _scheduler;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduler = PollScheduler(
      interval: ref.read(dashboardPollIntervalProvider),
      isVisible: () =>
          mounted &&
          _resumed &&
          TickerMode.valuesOf(context).enabled &&
          (ModalRoute.isCurrentOf(context) ?? true) &&
          !ref.read(appLockedProvider),
      tick: () => ref.read(firstFrameDoneProvider)
          ? ref.read(dashboardProvider.notifier).refresh(DashboardTrigger.poll)
          : Future.value(true),
    )..start();
    // Unlocking resumes polling; locking is picked up by the next tick.
    ref.listenManual(
      appLockedProvider,
      (_, _) => _scheduler.visibilityChanged(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A tab switch (TickerMode) or a route popped back to this screen
    // (ModalRoute) changes visibility.
    TickerMode.valuesOf(context);
    ModalRoute.isCurrentOf(context);
    if (mounted) _scheduler.visibilityChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && ref.read(firstFrameDoneProvider)) {
      // Coming back refreshes everything (pollNow checks visibility itself).
      if (_scheduler.isVisible()) {
        unawaited(
          ref.read(dashboardProvider.notifier).refresh(DashboardTrigger.resume),
        );
      }
      unawaited(_scheduler.pollNow());
    }
  }

  @override
  void dispose() {
    _scheduler.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pull to refresh: keeps the content, announces the result once.
  Future<void> _pull() async {
    final notifier = ref.read(dashboardProvider.notifier);
    await notifier.refresh(DashboardTrigger.pull);
    if (!mounted) return;
    final l10n = context.l10n;
    final failed = _failedServers(ref.read(dashboardProvider));
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        failed == 0
            ? l10n.dashboardRefreshedAnnouncement
            : l10n.dashboardRefreshedPartial(failed),
        Directionality.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = ref.watch(firstFrameDoneProvider);
    final servers = ref.watch(uiServersProvider);
    final noServers =
        ready && servers.hasValue && (servers.value?.isEmpty ?? false);
    return FloatingTopBarScaffold(
      title: l10n.dashboardTitle,
      actions: [
        IconButton(
          tooltip: l10n.dashboardAboutTooltip,
          icon: const Icon(Icons.info_outline),
          onPressed: () => GoRouter.maybeOf(context)?.push(AppRoutes.about),
        ),
      ],
      bodyBuilder: (context, padding) {
        if (noServers) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: true,
                child: Padding(
                  padding: padding,
                  child: Center(
                    child: EmptyState(
                      icon: Icons.dns_outlined,
                      headline: l10n.dashboardEmptyHeading,
                      message: l10n.dashboardEmptyBody,
                      actionLabel: l10n.dashboardSetupCta,
                      onAction: () => openSetup(context),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return RefreshIndicator(
          edgeOffset: padding.top,
          onRefresh: ready ? _pull : () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: SliverList.list(
                  children: ready
                      ? const [
                          SizedBox(height: ConsolarrSpacing.md),
                          ActivityCard(),
                          SizedBox(height: ConsolarrSpacing.section),
                          UpcomingCard(),
                          SizedBox(height: ConsolarrSpacing.section),
                          RecentCard(),
                        ]
                      : [
                          const SizedBox(height: ConsolarrSpacing.md),
                          _BeforeFirstFrame(
                            heading: l10n.dashboardActivityHeading,
                            carousel: false,
                          ),
                          const SizedBox(height: ConsolarrSpacing.section),
                          _BeforeFirstFrame(
                            heading: l10n.dashboardUpcomingHeading,
                            carousel: true,
                          ),
                          const SizedBox(height: ConsolarrSpacing.section),
                          _BeforeFirstFrame(
                            heading: l10n.dashboardRecentHeading,
                            carousel: true,
                          ),
                        ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A card's skeleton for the very first frame: it touches no provider.
class _BeforeFirstFrame extends StatelessWidget {
  const _BeforeFirstFrame({required this.heading, required this.carousel});

  final String heading;
  final bool carousel;

  @override
  Widget build(BuildContext context) => DashboardCardFrame(
    heading: heading,
    child: DashboardSkeleton(carousel: carousel),
  );
}

/// Servers that failed in any card (each server counted once).
int _failedServers(DashboardSnapshot snapshot) {
  final failed = <String>{};
  void collect<T>(CardState<T> state) {
    final slices = switch (state) {
      CardData<T>(:final slices) => slices,
      CardError<T>(:final slices) => slices,
      _ => const <CardSlice<Object?>>[],
    };
    for (final s in slices) {
      if (s is SliceFailed) failed.add('${s.kind.name}:${s.serverId}');
    }
  }

  collect(snapshot.activity);
  collect(snapshot.upcoming);
  collect(snapshot.recent);
  return failed.length;
}
