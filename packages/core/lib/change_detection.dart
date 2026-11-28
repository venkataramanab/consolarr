// SPDX-License-Identifier: GPL-3.0-or-later

/// Change detection for polled server state (notifications-ready, nothing
/// ships): tracked items, snapshots, the diff, the ledger and the poll cycle.
///
/// Pure Dart, so it runs under plain `dart test`. It is a separate library
/// from `package:core/core.dart` on purpose: the rest of the app must not get
/// these names by importing the common domain models.
library;

export 'src/change_detection/change_event.dart';
export 'src/change_detection/change_ledger.dart';
export 'src/change_detection/diff.dart';
export 'src/change_detection/poll_cycle.dart';
export 'src/change_detection/tracked_item.dart';
