// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/server_switcher_sheet.dart';
import 'package:consolarr/features/shell/presentation/shell_chrome.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/navigation/destinations.dart';
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
    final screen = appDestinations[index].screen;
    if (screen != null) {
      ref.read(eventTrackerProvider).track(ScreenViewedEvent(screen: screen));
    }
  }

  @override
  void dispose() {
    _barHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shell = widget.navigationShell;
    final current = shell.currentIndex;
    final servers = ref.watch(uiServersProvider).value ?? const <ServerEntry>[];
    // Indices into appDestinations; the open branch is always among them.
    final visible = visibleDestinationIndices(servers, currentIndex: current);
    final selected = visible.indexOf(current);
    final media = MediaQuery.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _trackBranch(current));

    final switcherKinds = appDestinations[current].effectiveSwitcherKinds;

    return PopScope(
      canPop: current == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // A pushed child route pops first; only the branch root goes Home.
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
        } else {
          shell.goBranch(0);
        }
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
                switcher: switcherKinds.isEmpty
                    ? null
                    : ServerSwitcherButton(
                        kinds: switcherKinds,
                        selectionKey: selectedKindKeyFor(
                          appDestinations[current].id,
                        ),
                      ),
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
                    for (final i in visible)
                      FloatingNavDestination(
                        icon: appDestinations[i].icon,
                        selectedIcon: appDestinations[i].selectedIcon,
                        label: appDestinations[i].label(l10n),
                        semanticsHint: l10n.navSelectedHint,
                      ),
                  ],
                  onSelected: (position) {
                    final index = visible[position];
                    shell.goBranch(index, initialLocation: index == current);
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
