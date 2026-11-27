// SPDX-License-Identifier: GPL-3.0-or-later

/// One reading of the global transfer speeds (bytes per second).
class SpeedSample {
  const SpeedSample({required this.down, required this.up});

  final int down;
  final int up;

  @override
  bool operator ==(Object other) =>
      other is SpeedSample && other.down == down && other.up == up;

  @override
  int get hashCode => Object.hash(down, up);
}

/// How many samples the rolling graph keeps (about three minutes at the
/// default 3 second poll).
const speedHistoryLength = 60;

/// Returns [history] plus [sample], dropping the oldest entries beyond
/// [maxLength]. Never mutates [history].
List<SpeedSample> appendSpeedSample(
  List<SpeedSample> history,
  SpeedSample sample, {
  int maxLength = speedHistoryLength,
}) {
  final next = [...history, sample];
  return next.length <= maxLength
      ? next
      : next.sublist(next.length - maxLength);
}

/// Where the combined speed is heading across the window.
enum SpeedTrend { rising, falling, steady }

/// Compares the average combined speed of the newest quarter of [history]
/// (at least two samples) with the rest: more than 25% apart is a trend.
SpeedTrend speedTrend(List<SpeedSample> history) {
  if (history.length < 4) return SpeedTrend.steady;
  final recentCount = history.length ~/ 4 < 2 ? 2 : history.length ~/ 4;
  final split = history.length - recentCount;
  double avg(Iterable<SpeedSample> xs) =>
      xs.fold<int>(0, (a, s) => a + s.down + s.up) / xs.length;
  final earlier = avg(history.take(split));
  final recent = avg(history.skip(split));
  if (recent > earlier * 1.25) return SpeedTrend.rising;
  if (recent < earlier * 0.75) return SpeedTrend.falling;
  return SpeedTrend.steady;
}

/// The highest download and upload speeds in [history].
({int down, int up}) speedPeaks(List<SpeedSample> history) {
  var down = 0;
  var up = 0;
  for (final s in history) {
    if (s.down > down) down = s.down;
    if (s.up > up) up = s.up;
  }
  return (down: down, up: up);
}
