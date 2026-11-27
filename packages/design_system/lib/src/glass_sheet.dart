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
    this.peekFraction = 0.5,
    this.fullFraction = 0.92,
    this.initialFull = false,
  }) : assert(
         peekFraction > 0 && peekFraction <= fullFraction && fullFraction <= 1,
       );

  /// A sheet that only has its full height.
  const GlassSheetDetents.fullOnly() : this(peekFraction: 0.92);

  /// Opens at the peek detent (about half the screen).
  static const GlassSheetDetents peek = GlassSheetDetents();

  /// Opens at the full detent.
  static const GlassSheetDetents full = GlassSheetDetents(initialFull: true);

  /// Fraction of the screen height at the peek detent.
  final double peekFraction;

  /// Fraction of the screen height at the full detent.
  final double fullFraction;

  /// Open at [fullFraction] instead of [peekFraction].
  final bool initialFull;

  /// Whether there is nothing to toggle between.
  bool get isSingle => peekFraction >= fullFraction;
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
/// Give exactly one body:
///
/// * [builder] for a short body: it scrolls inside the sheet's own scroll
///   view (do not add one of your own);
/// * [scrollBuilder] for a long, lazy list: the body is rendered unwrapped and
///   receives the sheet's [ScrollController], so a `ListView.builder` stays
///   lazy and dragging its content still moves the sheet between detents.
///
/// [toggleDetentLabel] (optional) names the handle's tap action; it defaults
/// to the design system's own "Expand or collapse" text for the locale. The
/// sheet opens on the **root** navigator, above the floating nav bar, so it
/// survives tab switches and the bar cannot be tapped through the scrim.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required String title,
  required String closeLabel,
  WidgetBuilder? builder,
  GlassSheetScrollBuilder? scrollBuilder,
  GlassSheetDetents detents = const GlassSheetDetents(),
  String? toggleDetentLabel,
}) {
  assert(
    (builder == null) != (scrollBuilder == null),
    'Give exactly one of builder and scrollBuilder.',
  );
  final effects = ConsolarrEffects.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
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
      scrollBuilder: scrollBuilder,
      child: builder == null ? null : Builder(builder: builder),
    ),
  );
}

/// Builds a [showGlassSheet] body that scrolls with the sheet: attach
/// [ScrollController] to the list.
typedef GlassSheetScrollBuilder = Widget Function(
  BuildContext context,
  ScrollController controller,
);

/// The default handle label, in the languages the app ships. The design
/// system has no l10n; pass `toggleDetentLabel` for anything else.
String _defaultToggleLabel(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'ar'
    ? '\u062a\u0648\u0633\u064a\u0639 \u0623\u0648 \u0637\u064a \u0627\u0644\u0646\u0627\u0641\u0630\u0629'
    : 'Expand or collapse';

/// The sheet surface used by [showGlassSheet]; exposed so tests and previews
/// can render it without a route.
class GlassSheet extends StatefulWidget {
  const GlassSheet({
    required this.title,
    required this.closeLabel,
    this.child,
    this.scrollBuilder,
    this.detents = const GlassSheetDetents(),
    this.toggleDetentLabel,
    super.key,
  }) : assert(
         (child == null) != (scrollBuilder == null),
         'Give exactly one of child and scrollBuilder.',
       );

  final String title;
  final String closeLabel;

  /// A short body, scrolled by the sheet.
  final Widget? child;

  /// A long body that uses the sheet's scroll controller.
  final GlassSheetScrollBuilder? scrollBuilder;
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
    final atFull = _controller.size >= widget.detents.fullFraction - 0.01;
    final target = atFull
        ? widget.detents.peekFraction
        : widget.detents.fullFraction;
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
      button: !detents.isSingle,
      label: detents.isSingle
          ? null
          : (widget.toggleDetentLabel ?? _defaultToggleLabel(context)),
      excludeSemantics: true,
      onTap: detents.isSingle ? null : _toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: detents.isSingle ? null : _toggle,
        child: SizedBox(
          // A 48dp target around the 4dp visual handle.
          height: 48,
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
                  ? detents.fullFraction
                  : detents.peekFraction,
              // Dragging below the peek detent dismisses the sheet.
              minChildSize: detents.peekFraction / 2,
              maxChildSize: detents.fullFraction,
              snap: !detents.isSingle,
              snapSizes: detents.isSingle
                  ? null
                  : [detents.peekFraction, detents.fullFraction],
              builder: (context, scrollController) => surface(
                Column(
                  children: [
                    handle,
                    header,
                    Expanded(
                      child: widget.scrollBuilder != null
                          ? widget.scrollBuilder!(context, scrollController)
                          : SingleChildScrollView(
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
