// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/features/radarr/presentation/library_page.dart';
import 'package:consolarr/features/radarr/presentation/missing_page.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/queue_page.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

enum RadarrSection { library, calendar, queue, missing }

/// The Radarr tab: sub-navigation between library, calendar, queue and
/// missing (NAV-03). Tabs are buttons; swiping between them also works.
class RadarrScreen extends ConsumerStatefulWidget {
  const RadarrScreen({super.key});

  @override
  ConsumerState<RadarrScreen> createState() => _RadarrScreenState();
}

class _RadarrScreenState extends ConsumerState<RadarrScreen> {
  final _pages = PageController();
  RadarrSection _section = RadarrSection.library;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(RadarrSection s) {
    setState(() => _section = s);
    if (_pages.hasClients) _pages.jumpToPage(s.index);
  }

  String _label(AppLocalizations l10n, RadarrSection s) => switch (s) {
    RadarrSection.library => l10n.radarrTabLibrary,
    RadarrSection.calendar => l10n.radarrTabCalendar,
    RadarrSection.queue => l10n.radarrTabQueue,
    RadarrSection.missing => l10n.radarrTabMissing,
  };

  IconData _icon(RadarrSection s) => switch (s) {
    RadarrSection.library => Icons.movie_outlined,
    RadarrSection.calendar => Icons.calendar_month_outlined,
    RadarrSection.queue => Icons.downloading_outlined,
    RadarrSection.missing => Icons.search,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RadarrScreenView(
      screen: ScreenName.radarrLibrary,
      child: FloatingTopBarScaffold(
        title: l10n.radarrTitle,
        actions: [
          IconButton(
            tooltip: l10n.radarrAddMovie,
            icon: const Icon(Icons.add),
            onPressed: () => openAddMovie(context),
          ),
        ],
        bodyBuilder: (context, padding) => Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              SizedBox(height: padding.top),
              _Tabs(
                section: _section,
                label: (s) => _label(l10n, s),
                icon: _icon,
                onSelect: _select,
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) =>
                      setState(() => _section = RadarrSection.values[i]),
                  children: [
                    for (final s in RadarrSection.values)
                      _page(s, padding.copyWith(top: ConsolarrSpacing.sm)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page(RadarrSection s, EdgeInsets padding) => switch (s) {
    RadarrSection.library => LibraryPage(padding: padding),
    RadarrSection.calendar => CalendarPage(padding: padding),
    RadarrSection.queue => QueuePage(
      padding: padding,
      active: _section == RadarrSection.queue,
    ),
    RadarrSection.missing => MissingPage(padding: padding),
  };
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.section,
    required this.label,
    required this.icon,
    required this.onSelect,
  });

  final RadarrSection section;
  final String Function(RadarrSection) label;
  final IconData Function(RadarrSection) icon;
  final void Function(RadarrSection) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: ConsolarrSpacing.gutter),
      child: Row(
        children: [
          for (final s in RadarrSection.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                end: ConsolarrSpacing.sm,
              ),
              child: ChoiceChip(
                avatar: Icon(icon(s), size: 18),
                label: Text(label(s)),
                selected: s == section,
                onSelected: (_) => onSelect(s),
              ),
            ),
        ],
      ),
    );
  }
}
