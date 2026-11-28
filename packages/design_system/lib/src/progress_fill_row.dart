// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/color_roles.dart';
import 'package:design_system/src/effects.dart';
import 'package:design_system/src/motion.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/type_scale.dart';
import 'package:material_ui/material_ui.dart';

/// Visual activity of a [ProgressFillRow]. The caller supplies the matching
/// icon and text; the enum only drives dimming and the pulse.
enum ProgressRowState {
  /// Transferring: accent fill, gentle pulse (unless motion is reduced).
  active,

  /// Paused or finished: dimmed, still.
  paused,

  /// Waiting: dimmed, still.
  queued,

  /// Nothing to emphasise (for example seeding or complete).
  idle,

  /// Failed: error-toned fill.
  error,
}

/// The fill of a [ProgressFillRow] for [state] at [pulse] (0..1, only the
/// active state pulses). The strongest fill (the pulse peak) must keep the
/// secondary text tier at 4.5:1 over the card; a test checks every palette.
Color progressFillColor(
  ConsolarrColorRoles roles,
  ProgressRowState state,
  double pulse,
) => switch (state) {
  ProgressRowState.active => roles.accent.withValues(alpha: 0.2 + 0.08 * pulse),
  ProgressRowState.error => roles.error.withValues(alpha: 0.22),
  ProgressRowState.paused ||
  ProgressRowState.queued => roles.textTertiary.withValues(alpha: 0.14),
  ProgressRowState.idle => roles.accent.withValues(alpha: 0.16),
};

/// A row whose background fills from the leading edge in proportion to
/// [progress]. State is always icon plus text; the semantics label (built by
/// the caller) must state the state and the percentage.
class ProgressFillRow extends StatefulWidget {
  const ProgressFillRow({
    required this.title,
    required this.progress,
    required this.state,
    required this.stateIcon,
    required this.stateLabel,
    required this.progressLabel,
    required this.semanticsLabel,
    this.details = const [],
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final String title;

  /// 0..1 (clamped).
  final double progress;
  final ProgressRowState state;
  final IconData stateIcon;
  final String stateLabel;

  /// Formatted percentage, shown with tabular figures.
  final String progressLabel;

  /// Full spoken description: state and percentage included.
  final String semanticsLabel;

  /// Live values (speeds, ETA, ratio, size), already formatted.
  final List<String> details;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<ProgressFillRow> createState() => _ProgressFillRowState();
}

class _ProgressFillRowState extends State<ProgressFillRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  bool get _wantsPulse =>
      widget.state == ProgressRowState.active &&
      ConsolarrEffects.of(context).animate;

  void _syncPulse() {
    if (_wantsPulse) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: ConsolarrMotion.pulse,
      );
      if (!_pulse!.isAnimating) _pulse!.repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(ProgressFillRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  Color _fillColor(BuildContext context, double pulse) =>
      progressFillColor(context.roles, widget.state, pulse);

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final progress = widget.progress.isNaN
        ? 0.0
        : widget.progress.clamp(0.0, 1.0);
    final tabular = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: ConsolarrTypeScale.tabularFigures,
    );
    final content = Padding(
      padding: const EdgeInsets.all(ConsolarrSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: ConsolarrSpacing.sm),
              Text(
                widget.progressLabel,
                style: tabular?.copyWith(fontWeight: ConsolarrTypeScale.bold),
              ),
            ],
          ),
          const SizedBox(height: ConsolarrSpacing.xs),
          Row(
            children: [
              Icon(widget.stateIcon, size: 16, color: roles.textPrimary),
              const SizedBox(width: ConsolarrSpacing.xs),
              Flexible(
                child: Text(
                  widget.stateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          if (widget.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
              child: Wrap(
                spacing: ConsolarrSpacing.md,
                runSpacing: ConsolarrSpacing.xxs,
                children: [
                  for (final d in widget.details) Text(d, style: tabular),
                ],
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: widget.onTap != null,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Material(
        color: roles.card,
        borderRadius: ConsolarrRadii.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedBuilder(
                    animation: _pulse ?? const AlwaysStoppedAnimation(0.0),
                    builder: (context, _) {
                      final pulse = _pulse?.value ?? 0;
                      return FractionallySizedBox(
                        widthFactor: progress,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _fillColor(context, pulse),
                            border: BorderDirectional(
                              end: progress > 0 && progress < 1
                                  ? BorderSide(
                                      color:
                                          widget.state ==
                                              ProgressRowState.active
                                          ? roles.accent
                                          : roles.textTertiary,
                                      width: 2,
                                    )
                                  : BorderSide.none,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}
