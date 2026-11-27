// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appends without mutating the input', () {
    const a = [SpeedSample(down: 1, up: 2)];
    final b = appendSpeedSample(a, const SpeedSample(down: 3, up: 4));
    expect(a, hasLength(1));
    expect(b, hasLength(2));
    expect(b.last, const SpeedSample(down: 3, up: 4));
  });

  test('keeps only the newest samples within the window', () {
    var h = <SpeedSample>[];
    for (var i = 0; i < speedHistoryLength + 25; i++) {
      h = appendSpeedSample(h, SpeedSample(down: i, up: 0));
    }
    expect(h, hasLength(speedHistoryLength));
    expect(h.first.down, 25);
    expect(h.last.down, speedHistoryLength + 24);
  });

  test('custom window length', () {
    var h = <SpeedSample>[];
    for (var i = 0; i < 10; i++) {
      h = appendSpeedSample(h, SpeedSample(down: i, up: i), maxLength: 3);
    }
    expect(h.map((s) => s.down), [7, 8, 9]);
  });
}
