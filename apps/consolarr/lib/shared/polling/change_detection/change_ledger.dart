// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';

import 'package:consolarr/shared/polling/change_detection/change_event.dart';

/// Remembers which items have already fired. Only [InMemoryChangeStore] ships:
/// persisting the ledger across launches is deferred (with the notifications
/// that need it), so after a restart an item may fire once more.
abstract interface class ChangeStore {
  bool contains(String key);
  void add(String key);
}

/// A bounded in-memory [ChangeStore]; the oldest entry is dropped first.
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

/// Lets each (server, item key) fire at most once.
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
