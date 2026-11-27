// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:design_system/src/effects.dart';
import 'package:design_system/src/motion.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

/// One entry of a [NestedMenu]: a leaf with [onSelected] or a parent with
/// [children] (opened in place; the first row of the sub-menu goes back).
///
/// A disabled item stays focusable and announced, and [disabledReason] says
/// why it is disabled (shown under the label and spoken as a hint).
@immutable
class NestedMenuItem {
  const NestedMenuItem({
    required this.label,
    this.icon,
    this.onSelected,
    this.children = const [],
    this.destructive = false,
    this.enabled = true,
    this.disabledReason,
  });

  final String label;
  final IconData? icon;

  /// Called after the menu has closed, for a leaf item.
  final VoidCallback? onSelected;

  /// Sub-menu entries; a non-empty list makes this item a parent.
  final List<NestedMenuItem> children;

  /// Marks a destructive action (error colour **and** the label is spoken as
  /// is; pair with a confirmation in the handler).
  final bool destructive;
  final bool enabled;
  final String? disabledReason;

  bool get hasChildren => children.isNotEmpty;
}

/// A menu with sub-menus. Works without long-press or hover: every item is a
/// focusable, labelled `menuitem` with enabled/expanded state, arrow keys
/// move between items, the "next" arrow (right in LTR, left in RTL) opens a
/// sub-menu, the opposite arrow or Escape goes back and closes.
///
/// Use [showNestedMenu] to present it next to an anchor, or embed it.
class NestedMenu extends StatefulWidget {
  const NestedMenu({
    required this.items,
    required this.semanticsLabel,
    this.onClose,
    super.key,
  });

  final List<NestedMenuItem> items;

  /// Accessible name of the whole menu.
  final String semanticsLabel;

  /// Called to close the menu (Escape, or after a leaf was chosen).
  final VoidCallback? onClose;

  @override
  State<NestedMenu> createState() => _NestedMenuState();
}

class _NestedMenuState extends State<NestedMenu> {
  final List<NestedMenuItem> _path = [];

  List<NestedMenuItem> get _current =>
      _path.isEmpty ? widget.items : _path.last.children;

  void _open(NestedMenuItem parent) => setState(() => _path.add(parent));

  void _back() {
    if (_path.isEmpty) {
      widget.onClose?.call();
    } else {
      setState(_path.removeLast);
    }
  }

  void _select(NestedMenuItem item) {
    widget.onClose?.call();
    item.onSelected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final forward = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final backward = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    return Semantics(
      role: SemanticsRole.menu,
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: widget.semanticsLabel,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _back,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              FocusScope.of(context).nextFocus(),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              FocusScope.of(context).previousFocus(),
          SingleActivator(backward): () {
            if (_path.isNotEmpty) _back();
          },
        },
        child: FocusTraversalGroup(
          child: Material(
            color: roles.raised,
            borderRadius: ConsolarrRadii.card,
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: ConsolarrRadii.card,
                border: Border.all(color: roles.track),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_path.isNotEmpty) ...[
                      _MenuRow(
                        key: ValueKey('back-${_path.length}'),
                        label: _path.last.label,
                        icon: Icons.arrow_back,
                        isBack: true,
                        autofocus: true,
                        onActivate: _back,
                        forwardKey: forward,
                      ),
                      Divider(height: 1, color: roles.track),
                    ],
                    for (final item in _current)
                      _MenuRow(
                        key: ValueKey('${_path.length}-${item.label}'),
                        label: item.label,
                        icon: item.icon,
                        destructive: item.destructive,
                        enabled: item.enabled,
                        disabledReason: item.disabledReason,
                        expandable: item.hasChildren,
                        onActivate: item.hasChildren
                            ? () => _open(item)
                            : () => _select(item),
                        forwardKey: forward,
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

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.onActivate,
    required this.forwardKey,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.disabledReason,
    this.expandable = false,
    this.isBack = false,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool destructive;
  final bool enabled;
  final String? disabledReason;
  final bool expandable;
  final bool isBack;
  final bool autofocus;
  final VoidCallback onActivate;
  final LogicalKeyboardKey forwardKey;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final color = !enabled
        ? roles.textTertiary
        : destructive
        ? roles.error
        : roles.textPrimary;
    final reason = enabled ? null : disabledReason;
    return Semantics(
      role: SemanticsRole.menuItem,
      button: true,
      enabled: enabled,
      expanded: expandable ? false : null,
      label: label,
      hint: reason,
      excludeSemantics: true,
      onTap: enabled ? onActivate : null,
      child: Focus(
        onKeyEvent: (node, event) {
          if (enabled &&
              expandable &&
              event is KeyDownEvent &&
              event.logicalKey == forwardKey) {
            onActivate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        skipTraversal: true,
        child: InkWell(
          autofocus: autofocus,
          onTap: enabled ? onActivate : null,
          canRequestFocus: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: TouchTargets.of(context).minimum,
              minWidth: 200,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.lg,
                vertical: ConsolarrSpacing.sm,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: ConsolarrSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: color,
                          ),
                        ),
                        if (reason != null)
                          Text(reason, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (expandable) ...[
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Icon(
                      Icons.chevron_right,
                      color: roles.textSecondary,
                      textDirection: Directionality.of(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a [NestedMenu] next to [anchor] (a rectangle in global
/// coordinates, for example from [anchorRectOf]). The menu opens below the
/// anchor, aligned to its start edge, and is kept on screen. Escape, a tap
/// outside or choosing a leaf closes it.
///
/// ```dart
/// final button = Builder(builder: (context) => IconButton(
///   tooltip: l10n.moreActions,
///   icon: const Icon(Icons.more_vert),
///   onPressed: () => showNestedMenu(
///     context,
///     anchorRectOf(context),
///     [NestedMenuItem(label: 'Refresh', onSelected: refresh)],
///     l10n.moreActions,
///   ),
/// ));
/// ```
Future<void> showNestedMenu(
  BuildContext context,
  Rect anchor,
  List<NestedMenuItem> items,
  String semanticsLabel,
) {
  final animate = ConsolarrEffects.of(context).animate;
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: semanticsLabel,
    barrierColor: const Color(0x00000000),
    transitionDuration: animate ? ConsolarrMotion.fast : Duration.zero,
    pageBuilder: (dialogContext, _, _) => themes.wrap(
      SafeArea(
        child: CustomSingleChildLayout(
          delegate: _MenuLayout(
            anchor: anchor,
            textDirection: Directionality.of(dialogContext),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: NestedMenu(
              items: items,
              semanticsLabel: semanticsLabel,
              onClose: () => Navigator.of(dialogContext).maybePop(),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// The global rectangle of the widget behind [context], for [showNestedMenu].
Rect anchorRectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.anchor, required this.textDirection});

  final Rect anchor;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: constraints.maxWidth - 2 * ConsolarrSpacing.sm,
        maxHeight: math.max(0, constraints.maxHeight - 2 * ConsolarrSpacing.sm),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final startAligned = textDirection == TextDirection.ltr
        ? anchor.left
        : anchor.right - childSize.width;
    final double x = startAligned
        .clamp(
          ConsolarrSpacing.sm,
          math.max(ConsolarrSpacing.sm, size.width - childSize.width - 8),
        )
        .toDouble();
    var y = anchor.bottom + ConsolarrSpacing.xs;
    if (y + childSize.height > size.height - ConsolarrSpacing.sm) {
      final above = anchor.top - ConsolarrSpacing.xs - childSize.height;
      y = above >= ConsolarrSpacing.sm
          ? above
          : math.max(
              ConsolarrSpacing.sm,
              size.height - childSize.height - ConsolarrSpacing.sm,
            );
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      old.anchor != anchor || old.textDirection != textDirection;
}
