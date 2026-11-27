// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The heights a sheet can rest at (stand-in for W4d's `GlassSheetDetents`).
class GlassSheetDetents {
  const GlassSheetDetents({this.initial = 0.6, this.max = 0.95});

  /// Fraction of the screen height the sheet opens at.
  final double initial;

  /// Fraction it can be dragged to.
  final double max;

  static const peek = GlassSheetDetents();
  static const full = GlassSheetDetents(initial: 0.95);
}

/// A bottom sheet with a visible handle, a title, a close button and
/// keyboard-safe content (NAV-11).
///
/// TODO(w4d): replace with `showGlassSheet` from `design_system` once W4d has
/// merged; the name and parameters follow its contract.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required String title,
  required String closeLabel,
  required Widget Function(BuildContext context) builder,
  GlassSheetDetents detents = GlassSheetDetents.peek,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _SheetFrame(
      title: title,
      closeLabel: closeLabel,
      detents: detents,
      child: builder(sheetContext),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.closeLabel,
    required this.detents,
    required this.child,
  });

  final String title;
  final String closeLabel;
  final GlassSheetDetents detents;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    // Keyboard-safe: the content scrolls above the keyboard.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * detents.max),
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: ConsolarrSpacing.gutter,
                end: ConsolarrSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                  ),
                  IconButton(
                    tooltip: closeLabel,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
