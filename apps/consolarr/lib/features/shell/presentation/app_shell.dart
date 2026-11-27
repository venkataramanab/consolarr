// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/server_switcher_sheet.dart';
import 'package:consolarr/features/shell/presentation/shell_chrome.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:consolarr/src/providers.dart';
import 'package:observability/observability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Frame for all primary areas (NAV-01): content under a floating bottom bar.
///
/// Destinations appear only for configured services. Content gets the bar's
/// measured height through `MediaQuery.padding.bottom`, so screens pad their
/// scrollables without knowing about the bar. System back from any other
/// destination returns to Home first (NAV-04); sheets dismiss before screens
/// because they are routes above the shell.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final ValueNotifier<double> _barHeight = ValueNotifier<double>(72);

  int? _trackedIndex;

  void _trackBranch(int index) {
    if (_trackedIndex == index) return;
    _trackedIndex = index;
    final screen = switch (ShellDestination.values[index]) {
      ShellDestination.sonarr => ScreenName.sonarrLibrary,
      ShellDestination.torrents => ScreenName.torrentList,
      _ => null,
    };
    if (screen != null) {
      ref.read(eventTrackerProvider).track(ScreenViewedEvent(screen: screen));
    }
  }

  @override
  void dispose() {
    _barHeight.dispose();
    super.dispose();
  }

  static IconData _icon(ShellDestination d, {required bool selected}) =>
      switch (d) {
        ShellDestination.home => selected ? Icons.home : Icons.home_outlined,
        ShellDestination.sonarr => selected ? Icons.tv : Icons.tv_outlined,
        ShellDestination.torrents =>
          selected ? Icons.download : Icons.download_outlined,
        ShellDestination.servers => selected ? Icons.dns : Icons.dns_outlined,
      };

  static String _label(AppLocalizations l10n, ShellDestination d) =>
      switch (d) {
        ShellDestination.home => l10n.navHome,
        ShellDestination.sonarr => l10n.navSonarr,
        ShellDestination.torrents => l10n.navTorrents,
        ShellDestination.servers => l10n.navServers,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = ref.watch(visibleDestinationsProvider);
    final shell = widget.navigationShell;
    // Branch order is fixed: home, sonarr, torrents, servers.
    final current = ShellDestination.values[shell.currentIndex];
    var selected = destinations.indexOf(current);
    if (selected < 0) selected = 0;
    final media = MediaQuery.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _trackBranch(shell.currentIndex),
    );

    final switcherKind = switch (current) {
      ShellDestination.sonarr => ServiceKind.sonarr,
      ShellDestination.torrents => ServiceKind.qbittorrent,
      _ => null,
    };

    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _barHeight,
              builder: (context, height, child) => MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + height + ConsolarrSpacing.md,
                  ),
                ),
                child: child!,
              ),
              child: ShellChrome(
                switcher: switcherKind == null
                    ? null
                    : ServerSwitcherButton(kind: switcherKind),
                child: shell,
              ),
            ),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: media.padding.bottom,
              child: MeasuredBarHeight(
                height: _barHeight,
                child: FloatingNavBar(
                  selectedIndex: selected,
                  destinations: [
                    for (final d in destinations)
                      FloatingNavDestination(
                        icon: _icon(d, selected: false),
                        selectedIcon: _icon(d, selected: true),
                        label: _label(l10n, d),
                        semanticsHint: l10n.navSelectedHint,
                      ),
                  ],
                  onSelected: (i) {
                    final index = ShellDestination.values.indexOf(
                      destinations[i],
                    );
                    shell.goBranch(
                      index,
                      initialLocation: index == shell.currentIndex,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
