// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each entry point states its own flavor', () {
    final foss = File('lib/main.dart').readAsStringSync();
    final play = File('../consolarr_play/lib/main.dart').readAsStringSync();
    expect(
      foss,
      contains('appFlavorProvider.overrideWithValue(AppFlavor.foss)'),
    );
    expect(
      play,
      contains('appFlavorProvider.overrideWithValue(AppFlavor.play)'),
    );
    expect(foss, isNot(contains('AppFlavor.play')));
    expect(play, isNot(contains('AppFlavor.foss')));
  });
}
