// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Flips to `true` right after the first frame has been drawn.
///
/// Anything that touches the database or the network must watch this (or a
/// provider derived from it) so no I/O starts before the first frame.
class FirstFrameDone extends Notifier<bool> {
  @override
  bool build() => false;

  void markDone() => state = true;
}

final firstFrameDoneProvider = NotifierProvider<FirstFrameDone, bool>(
  FirstFrameDone.new,
);
