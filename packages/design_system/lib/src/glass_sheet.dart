// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show ImageFilter;

import 'package:design_system/src/blur_levels.dart';
import 'package:design_system/src/effects.dart';
import 'package:design_system/src/motion.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

/// The two heights of a [showGlassSheet]: a peek (about half the screen) and
/// the full height. The user drags between them; the handle also toggles
/// them for anyone who cannot drag.
@immutable
class GlassSheetDetents {
  const GlassSheetDetents({
    this.peek = 0.5,
    this.full = 0.92,
    this.initialFull = false,
  }) : assert(peek > 0 && peek <= full && full <= 1);

  /// A sheet that only has its full height.
  const GlassSheetDetents.fullOnly() : this(peek: 0.92, full: 0.92);

  /// Fraction of the screen height at the peek detent.
  final double peek;

  /// Fraction of the screen height at the full detent.
  final double full;

  /// Open at [full] instead of [peek].
  final bool initialFull;

  /// Whether there is nothing to toggle between.
  bool get isSingle => peek >= full;
}

/// Shows a bottom sheet with Consolarr's conventions (NAV-11): a visible
/// drag handle plus a close button, peek/full detents, keyboard-safe, never
/// traps focus (Escape and the close button always dismiss it), frosted glass
/// with a solid fallback under reduced transparency or on low-end devices,
/// and a short interruptible rise that is skipped under reduced motion.
///
/// Parameters are already-localized strings; the design system has no l10n.
///
/// ```dart
/// final picked = await showGlassSheet<int>(
///   context: context,
///   title: l10n.sortTitle,
///   closeLabel: l10n.commonClose,
///   builder: (context) => MyOptions(onPick: (v) => Navigator.pop(context, v)),
/// );
/// ```
///
/// [toggleDetentLabel] (optional) names the handle's tap action, "Expand or
/// collapse". Content scrolls inside the sheet; do not add a scroll view of
/// your own around [builder]'s result.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required String title,
  required String closeLabel,
  required WidgetBuilder builder,
  GlassSheetDetents detents = const GlassSheetDetents(),
  String? toggleDetentLabel,
}) {
  final effects = ConsolarrEffects.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: const Color(0x00000000),
    elevation: 0,
    sheetAnimationStyle: effects.animate
        ? const AnimationStyle(
            duration: ConsolarrMotion.standard,
            reverseDuration: ConsolarrMotion.fast,
            curve: ConsolarrMotion.enterCurve,
            reverseCurve: ConsolarrMotion.exitCurve,
          )
        : AnimationStyle.noAnimation,
    builder: (sheetContext) => GlassSheet(
      title: title,
      closeLabel: closeLabel,
      detents: detents,
      toggleDetentLabel: toggleDetentLabel,
      child: Builder(builder: builder),
    ),
  );
}

/// The sheet surface used by [showGlassSheet]; exposed so tests and previews
/// can render it without a route.
class GlassSheet extends StatefulWidget {
  const GlassSheet({
    required this.title,
    required this.closeLabel,
    required this.child,
    this.detents = const GlassSheetDetents(),
    this.toggleDetentLabel,
    super.key,
  });

  final String title;
  final String closeLabel;
  final Widget child;
  final GlassSheetDetents detents;
  final String? toggleDetentLabel;

  @override
  State<GlassSheet> createState() => _GlassSheetState();
}

class _GlassSheetState extends State<GlassSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_controller.isAttached || widget.detents.isSingle) return;
    final atFull = _controller.size >= widget.detents.full - 0.01;
    final target = atFull ? widget.detents.peek : widget.detents.full;
    final animate = ConsolarrEffects.of(context).animate;
    if (animate) {
      await _controller.animateTo(
        target,
        duration: ConsolarrMotion.standard,
        curve: ConsolarrMotion.standardCurve,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final detents = widget.detents;
    final glass = ConsolarrEffects.of(context).useGlass;
    final touch = TouchTargets.of(context).minimum;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    const radius = BorderRadius.vertical(
      top: Radius.circular(ConsolarrRadii.lg),
    );

    final handle = Semantics(
      key: const ValueKey('glass-sheet-handle'),
      button: !detents.isSingle && widget.toggleDetentLabel != null,
      label: widget.toggleDetentLabel,
      excludeSemantics: true,
      onTap: detents.isSingle ? null : _toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: detents.isSingle ? null : _toggle,
        child: SizedBox(
          height: ConsolarrSpacing.xl,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: roles.textTertiary,
                borderRadius: ConsolarrRadii.chip,
              ),
              child: const SizedBox(width: 40, height: 4),
            ),
          ),
        ),
      ),
    );

    final header = Padding(
      padding: const EdgeInsetsDirectional.only(
        start: ConsolarrSpacing.lg,
        end: ConsolarrSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                widget.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: widget.closeLabel,
            constraints: BoxConstraints.tightFor(width: touch, height: touch),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );

    Widget surface(Widget child) {
      if (!glass) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: roles.raised,
            borderRadius: radius,
            border: Border.all(color: roles.track),
          ),
          child: ClipRRect(borderRadius: radius, child: child),
        );
      }
      return ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: ConsolarrBlur.medium,
            sigmaY: ConsolarrBlur.medium,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: roles.raised.withValues(
                alpha: ConsolarrBlur.barTintOpacity,
              ),
              borderRadius: radius,
              border: Border.all(color: roles.track.withValues(alpha: 0.6)),
            ),
            child: child,
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: FocusTraversalGroup(
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: widget.title,
          child: AnimatedPadding(
            duration: ConsolarrEffects.of(context).animate
                ? ConsolarrMotion.fast
                : Duration.zero,
            padding: EdgeInsets.only(bottom: keyboard),
            child: DraggableScrollableSheet(
              controller: _controller,
              expand: false,
              initialChildSize: detents.initialFull
                  ? detents.full
                  : detents.peek,
              // Dragging below the peek detent dismisses the sheet.
              minChildSize: detents.peek / 2,
              maxChildSize: detents.full,
              snap: !detents.isSingle,
              snapSizes: detents.isSingle ? null : [detents.peek, detents.full],
              builder: (context, scrollController) => surface(
                Column(
                  children: [
                    handle,
                    header,
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          ConsolarrSpacing.lg,
                          ConsolarrSpacing.sm,
                          ConsolarrSpacing.lg,
                          ConsolarrSpacing.xl,
                        ),
                        child: widget.child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
