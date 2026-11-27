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
