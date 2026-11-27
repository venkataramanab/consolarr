// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

// TODO(w4d): replace with `showGlassSheet` from design_system once W4d has
// merged. Same name and named parameters as the W4d contract (detents are
// not modelled here).

/// A bottom sheet with a visible handle, a title and a close button (NAV-11).
/// Keyboard-safe, scrollable and dismissible by back, drag, scrim or button.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required String title,
  required String closeLabel,
  required Widget Function(BuildContext context) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _SheetFrame(
      title: title,
      closeLabel: closeLabel,
      child: builder(sheetContext),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.closeLabel,
    required this.child,
  });

  final String title;
  final String closeLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
    );
  }
}
