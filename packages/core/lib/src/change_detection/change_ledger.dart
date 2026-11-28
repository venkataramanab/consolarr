// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';

import 'change_event.dart';

/// Remembers which items have already fired. Only [InMemoryChangeStore] ships:
/// persisting the ledger across launches is deferred (with the notifications
/// that need it), so after a restart an item may fire once more.
abstract interface class ChangeStore {
  bool contains(String key);
  void add(String key);
}

/// A bounded in-memory [ChangeStore]; the oldest entry is dropped first.
///
/// Known limit: once [capacity] other keys have been added, an evicted key is
/// forgotten, so its item can fire again. Consumers get "at least once", not
/// "exactly once" (see docs/patterns.md).
class InMemoryChangeStore implements ChangeStore {
  InMemoryChangeStore({this.capacity = 512}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashSet<String> _keys = LinkedHashSet();

  int get length => _keys.length;

  @override
  bool contains(String key) => _keys.contains(key);

  @override
  void add(String key) {
    _keys.add(key);
    while (_keys.length > capacity) {
      _keys.remove(_keys.first);
    }
  }
}

/// Lets each (server, item key) fire once while the store remembers it.
///
/// Delivery is at least once, never exactly once: the bounded store evicts its
/// oldest entries, and an item whose entry was evicted can fire again if it
/// transitions again (docs/patterns.md, section 15).
class ChangeLedger {
  ChangeLedger(this._store);

  final ChangeStore _store;

  /// The events that have not fired before; they are recorded as fired.
  List<ChangeEvent> admit(Iterable<ChangeEvent> events) {
    final fresh = <ChangeEvent>[];
    for (final e in events) {
      final key = '${e.serverId}\u0000${e.itemKey}';
      if (_store.contains(key)) continue;
      _store.add(key);
      fresh.add(e);
    }
    return fresh;
  }
}
