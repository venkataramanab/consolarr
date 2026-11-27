// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_tab.dart';
import 'package:consolarr/features/sonarr/presentation/library/library_tab.dart';
import 'package:consolarr/features/sonarr/presentation/queue/queue_tab.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The route the add-server and "check settings" shortcuts open.
const _serversRoute = '/servers';

/// The Sonarr area (NAV-03): a floating top bar, a tab strip (library,
/// calendar, queue, missing) and a swipeable page per tab. Every tab keeps a
/// button alternative to the swipe (the strip).
class SonarrHomeScreen extends StatefulWidget {
  const SonarrHomeScreen({this.onOpenServers, this.tabs, super.key});

  /// Opens the servers screen. Defaults to `go('/servers')`.
  final VoidCallback? onOpenServers;

  /// Tabs to show (tests); defaults to library, calendar, queue, missing.
  final List<SonarrTab>? tabs;

  @override
  State<SonarrHomeScreen> createState() => _SonarrHomeScreenState();
}

class _SonarrHomeScreenState extends State<SonarrHomeScreen> {
  final _pages = PageController();
  int _index = 0;

  late final List<SonarrTab> _tabs =
      widget.tabs ??
      [
        buildLibraryTab(onOpenServers: _openServers),
        calendarTab,
        queueTab,
        wantedTab,
      ];

  void _openServers(BuildContext context) {
    final callback = widget.onOpenServers;
    if (callback != null) {
      callback();
    } else {
      GoRouter.maybeOf(context)?.go(_serversRoute);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    final animate = ConsolarrEffects.of(context).animate;
    if (animate) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stripHeight = MediaQuery.textScalerOf(context)
        .scale(ConsolarrSpacing.minTapTarget);
    return FloatingTopBarScaffold(
      title: l10n.sonarrTitle,
      actions: _tabs[_index].actions?.call(context) ?? const [],
      banner: _TabStrip(
        tabs: _tabs,
        selected: _index,
        height: stripHeight,
        onSelect: _select,
      ),
      bodyBuilder: (context, padding) {
        final inner = padding.copyWith(
          top: padding.top + stripHeight + ConsolarrSpacing.sm,
        );
        return PageView.builder(
          controller: _pages,
          itemCount: _tabs.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => _tabs[i].body(context, inner),
        );
      },
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selected,
    required this.height,
    required this.onSelect,
  });

  final List<SonarrTab> tabs;
  final int selected;
  final double height;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.sonarrTabsLabel,
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tabs.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: ConsolarrSpacing.sm),
          itemBuilder: (context, i) => Center(
            child: ChoiceChip(
              key: ValueKey('sonarr-tab-${tabs[i].id}'),
              avatar: Icon(tabs[i].icon, size: 18),
              label: Text(tabs[i].label(l10n)),
              selected: i == selected,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onSelect(i),
            ),
          ),
        ),
      ),
    );
  }
}
