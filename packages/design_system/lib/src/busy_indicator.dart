// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/effects.dart';
import 'package:material_ui/material_ui.dart';

/// The one indeterminate busy indicator. A spinner (or thin bar for
/// [BusyIndicator.linear]) while motion is allowed; a static hourglass icon
/// when the platform's "remove animations" flag or the app's reduce-motion
/// setting is on, so nothing loops (see `ConsolarrEffects.animate`). Raw
/// indeterminate `CircularProgressIndicator` / `LinearProgressIndicator`
/// outside this package are banned by a test.
///
/// [semanticLabel] is the caller's localized description ("Loading series").
/// It is announced once, as a live region, when the indicator first appears
/// and not again on rebuilds. Pass `null` only when text beside the indicator
/// already says what is happening (a button label); the indicator is then
/// hidden from semantics.
class BusyIndicator extends StatefulWidget {
  const BusyIndicator({
    required this.semanticLabel,
    this.size = 16,
    this.strokeWidth = 2,
    super.key,
  }) : linear = false;

  /// A full-width thin bar (a spinner under the filter chips, say).
  const BusyIndicator.linear({required this.semanticLabel, super.key})
    : linear = true,
      size = 16,
      strokeWidth = 2;

  final String? semanticLabel;

  /// Diameter of the spinner and of the static icon.
  final double size;

  final double strokeWidth;
  final bool linear;

  @override
  State<BusyIndicator> createState() => _BusyIndicatorState();
}

class _BusyIndicatorState extends State<BusyIndicator> {
  /// True for the first frame only: the live region is announced on appearing.
  bool _announce = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _announce = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final animate = ConsolarrEffects.of(context).animate;
    final Widget visual;
    if (!animate) {
      visual = Icon(Icons.hourglass_top, size: widget.size);
    } else if (widget.linear) {
      visual = const LinearProgressIndicator(minHeight: 2);
    } else {
      visual = SizedBox.square(
        dimension: widget.size,
        child: CircularProgressIndicator(strokeWidth: widget.strokeWidth),
      );
    }
    final aligned = widget.linear && !animate
        ? Align(alignment: AlignmentDirectional.centerStart, child: visual)
        : visual;
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: aligned);
    return Semantics(
      container: true,
      label: label,
      liveRegion: _announce,
      excludeSemantics: true,
      child: aligned,
    );
  }
}
