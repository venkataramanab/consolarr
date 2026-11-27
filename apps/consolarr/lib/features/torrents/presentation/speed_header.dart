// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Global throughput (TOR-03): live down/up speeds with tabular figures and a
/// short rolling graph. [onTap] is the hook for the speed-limits sheet (later).
class SpeedHeader extends StatelessWidget {
  const SpeedHeader({
    required this.history,
    required this.torrentCount,
    this.down,
    this.up,
    this.offline = false,
    this.partial = false,
    this.onTap,
    super.key,
  });

  /// `null` when the statistics are not available.
  final int? down;
  final int? up;
  final List<SpeedSample> history;
  final int torrentCount;
  final bool offline;
  final bool partial;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final unavailable = offline || down == null || up == null;
    final idle = !unavailable && down == 0 && up == 0;

    String value(int? v) {
      if (offline) return l10n.torSpeedOffline;
      if (v == null) return '–';
      return idle ? l10n.torSpeedIdle : formatSpeed(l10n, v);
    }

    final numbers = theme.textTheme.titleMedium?.copyWith(
      fontFeatures: ConsolarrTypeScale.tabularFigures,
    );
    Widget column(IconData icon, String label, int? v, Color color) {
      return Expanded(
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: ConsolarrSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(
                    value(v),
                    style: numbers,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final spoken = unavailable
        ? l10n.torSpeedOffline
        : l10n.torSpeedHeaderSemantics(
            formatSpeed(l10n, down ?? 0),
            formatSpeed(l10n, up ?? 0),
            torrentCount,
          );

    final card = Container(
      padding: const EdgeInsets.all(ConsolarrSpacing.md),
      decoration: BoxDecoration(
        color: roles.card,
        borderRadius: ConsolarrRadii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(
                Icons.arrow_downward,
                l10n.torSpeedDown,
                down,
                roles.accent,
              ),
              const SizedBox(width: ConsolarrSpacing.md),
              column(Icons.arrow_upward, l10n.torSpeedUp, up, roles.success),
            ],
          ),
          const SizedBox(height: ConsolarrSpacing.sm),
          ExcludeSemantics(
            child: SizedBox(
              height: 40,
              width: double.infinity,
              child: CustomPaint(
                painter: SpeedGraphPainter(
                  history: history,
                  downColor: roles.accent,
                  upColor: roles.success,
                  baseline: roles.track,
                  dimmed: offline,
                ),
              ),
            ),
          ),
          const SizedBox(height: ConsolarrSpacing.xs),
          Text(
            partial && !offline
                ? l10n.torSpeedPartial
                : l10n.torCount(torrentCount),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: spoken,
      hint: onTap == null ? null : l10n.torSpeedLimitsHint,
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null
          ? card
          : InkWell(
              onTap: onTap,
              borderRadius: ConsolarrRadii.card,
              child: card,
            ),
    );
  }
}

/// Draws the two rolling speed lines scaled to the window's maximum.
class SpeedGraphPainter extends CustomPainter {
  SpeedGraphPainter({
    required this.history,
    required this.downColor,
    required this.upColor,
    required this.baseline,
    this.dimmed = false,
  });

  final List<SpeedSample> history;
  final Color downColor;
  final Color upColor;
  final Color baseline;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = baseline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      base,
    );
    if (history.length < 2) return;
    var peak = 1;
    for (final s in history) {
      if (s.down > peak) peak = s.down;
      if (s.up > peak) peak = s.up;
    }
    final alpha = dimmed ? 0.4 : 1.0;
    void line(int Function(SpeedSample) pick, Color color, double width) {
      final path = Path();
      for (var i = 0; i < history.length; i++) {
        final x = size.width * i / (history.length - 1);
        final y = size.height - 2 - (size.height - 4) * pick(history[i]) / peak;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    line((s) => s.up, upColor, 1.5);
    line((s) => s.down, downColor, 2);
  }

  @override
  bool shouldRepaint(SpeedGraphPainter old) =>
      old.history != history ||
      old.dimmed != dimmed ||
      old.downColor != downColor ||
      old.upColor != upColor;
}
