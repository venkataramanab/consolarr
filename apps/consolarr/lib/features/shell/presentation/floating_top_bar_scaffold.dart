// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Frame for a screen with a slim floating top bar over scrolling content.
///
/// The body is laid out under the bar and receives [EdgeInsets] to use as its
/// scroll padding: the measured top bar height (plus the status bar) on top
/// and `MediaQuery.paddingOf(context).bottom` at the bottom. The navigation
/// shell raises that bottom padding by the floating nav bar's height, so a
/// screen never needs to know about the nav bar. Fade edges soften the content
/// where it meets the bars.
///
/// [actions] and [title] sit in a `GlassBar` (solid when transparency is
/// reduced). Leave room in [actions] for later search/sort/filter controls.
class FloatingTopBarScaffold extends StatefulWidget {
  const FloatingTopBarScaffold({
    required this.title,
    required this.bodyBuilder,
    this.actions = const [],
    this.banner,
    super.key,
  });

  final String title;
  final List<Widget> actions;

  /// Shown directly under the bar (for example an offline banner).
  final Widget? banner;

  /// Builds the scrolling body; use the padding as the scrollable's padding.
  final Widget Function(BuildContext context, EdgeInsets contentPadding)
  bodyBuilder;

  @override
  State<FloatingTopBarScaffold> createState() => _FloatingTopBarScaffoldState();
}

class _FloatingTopBarScaffoldState extends State<FloatingTopBarScaffold> {
  final ValueNotifier<double> _barHeight = ValueNotifier<double>(56);

  @override
  void dispose() {
    _barHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final roles = context.roles;
    return Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _barHeight,
            builder: (context, height, _) {
              final top = media.padding.top + height + ConsolarrSpacing.sm;
              final padding = EdgeInsets.only(
                top: top,
                bottom: media.padding.bottom + ConsolarrSpacing.lg,
                left: ConsolarrSpacing.gutter,
                right: ConsolarrSpacing.gutter,
              );
              return widget.bodyBuilder(context, padding);
            },
          ),
        ),
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ConsolarrSpacing.md,
                ConsolarrSpacing.sm,
                ConsolarrSpacing.md,
                0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MeasuredBarHeight(
                    height: _barHeight,
                    child: GlassBar(
                      padding: const EdgeInsetsDirectional.only(
                        start: ConsolarrSpacing.lg,
                        end: ConsolarrSpacing.xs,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: ConsolarrSpacing.minTapTarget,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ),
                            ...widget.actions,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.banner != null) ...[
                    const SizedBox(height: ConsolarrSpacing.sm),
                    widget.banner!,
                  ],
                ],
              ),
            ),
          ),
        ),
        // Fade edge under the top bar region, in the page colour.
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          height: media.padding.top + 4,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [roles.page, roles.page.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
