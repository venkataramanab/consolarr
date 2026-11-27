// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Stand-in with the contract name of W4d's `showGlassSheet`.
///
/// TODO(w4d): replace with `design_system`'s `showGlassSheet` and
/// `GlassSheetDetents` once W4d has merged (same name and parameters; the
/// `builder` receives the sheet's scroll controller).
class GlassSheetDetents {
  const GlassSheetDetents({
    this.initial = 0.6,
    this.min = 0.35,
    this.max = 0.95,
  });

  /// Peek (partial) height as a fraction of the screen.
  static const peek = GlassSheetDetents();

  /// Opens (nearly) full height; for large sheets such as release search.
  static const full = GlassSheetDetents(initial: 0.95, min: 0.5, max: 0.95);

  final double initial;
  final double min;
  final double max;
}

/// Opens a bottom sheet with a visible handle, a title and a close button
/// (NAV-11). Keyboard-safe; focus is never trapped (the sheet dismisses on
/// back, scrim tap, drag or the close button).
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required String title,
  required String closeLabel,
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
  GlassSheetDetents detents = GlassSheetDetents.peek,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: detents.initial,
      minChildSize: detents.min,
      maxChildSize: detents.max,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
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
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: closeLabel,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            Expanded(child: builder(context, controller)),
          ],
        ),
      ),
    ),
  );
}
