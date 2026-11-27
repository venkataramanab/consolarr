// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/library_query.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs a computation, possibly on another isolate. Tests inject an inline
/// version.
typedef LibraryRunner = Future<T> Function<T>(T Function() computation);

final libraryRunnerProvider = Provider<LibraryRunner>(
  (ref) =>
      <T>(T Function() computation) => Isolate.run(computation),
);

/// Lists up to this size are filtered on the UI isolate (well under a frame);
/// bigger ones go to another isolate.
const librarySyncLimit = 1500;

const _sortPref = 'library.sort';
const _filterPref = 'library.filter';

/// Search, sort and filter of the library list. Starts from the per-server
/// saved defaults (restored right after the first read) and follows a server
/// switch.
final libraryQueryProvider =
    NotifierProvider<LibraryQueryNotifier, LibraryQuery>(
      LibraryQueryNotifier.new,
    );

class LibraryQueryNotifier extends Notifier<LibraryQuery> {
  String? _serverId;

  @override
  LibraryQuery build() {
    final session = ref.watch(sonarrSessionProvider).value;
    _serverId = session?.serverId;
    if (_serverId != null) Future<void>.microtask(_restore);
    return const LibraryQuery();
  }

  Future<void> _restore() async {
    final id = _serverId;
    if (id == null) return;
    try {
      final store = ref.read(sonarrPrefsStoreProvider);
      final sort = decodeSort(await store.read(id, _sortPref));
      final rawFilter = await store.read(id, _filterPref);
      if (!ref.mounted || id != _serverId) return;
      var next = state;
      if (sort != null)
        next = next.copyWith(sortKey: sort.$1, ascending: sort.$2);
      if (rawFilter != null) {
        next = next.copyWith(filter: _decodeFilter(rawFilter));
      }
      if (next != state) state = next;
    } on Object {
      // Defaults are optional; keep the built-in ones.
    }
  }

  LibraryFilter _decodeFilter(String raw) {
    try {
      return LibraryFilter.fromJson(jsonDecodeLoose(raw));
    } on FormatException {
      return const LibraryFilter();
    }
  }

  void setSearch(String text) => state = state.copyWith(search: text);

  Future<void> applySort(
    SeriesSortKey key, {
    required bool ascending,
    bool saveAsDefault = false,
  }) async {
    state = state.copyWith(sortKey: key, ascending: ascending);
    if (saveAsDefault) {
      await _save(_sortPref, encodeSort(key, ascending: ascending));
    }
  }

  Future<void> applyFilter(
    LibraryFilter filter, {
    bool saveAsDefault = false,
  }) async {
    state = state.copyWith(filter: filter);
    if (saveAsDefault) await _save(_filterPref, encodeFilter(filter));
  }

  void clearFilter() => state = state.copyWith(filter: const LibraryFilter());

  /// Clears the search text and the filter (not the sort).
  void clearAll() =>
      state = state.copyWith(search: '', filter: const LibraryFilter());

  Future<void> _save(String name, String value) async {
    final id = _serverId;
    if (id == null) return;
    try {
      await ref.read(sonarrPrefsStoreProvider).write(id, name, value);
    } on Object {
      // The choice still applies for this session.
    }
  }
}

/// Quality profiles and tags for names in the filter sheet and groups.
class LibraryLookups {
  const LibraryLookups({this.profiles = const [], this.tags = const []});
  final List<ArrQualityProfile> profiles;
  final List<ArrTag> tags;

  Map<int, String> get profileNames => {for (final p in profiles) p.id: p.name};
}

/// Loaded once per server; failures just mean no names (the library itself
/// does not depend on them).
final libraryLookupsProvider = FutureProvider<LibraryLookups>(
  retry: (_, _) => null,
  (ref) async {
    final session = await ref.watch(sonarrSessionProvider.future);
    if (session == null) return const LibraryLookups();
    final profiles = await session.api.qualityProfiles();
    final tags = await session.api.tags();
    return LibraryLookups(
      profiles: profiles.valueOrNull ?? const [],
      tags: tags.valueOrNull ?? const [],
    );
  },
);

/// The list the screen shows: filtered, searched, sorted and grouped.
class VisibleSeries {
  const VisibleSeries({
    this.groups = const [],
    this.count = 0,
    this.computing = false,
  });

  final List<SeriesGroup> groups;
  final int count;

  /// A big list is being recomputed; [groups] is the previous result.
  final bool computing;
}

/// Filters off the UI isolate for big libraries; the previous result stays
/// visible while a new one is computed, and a stale result is dropped.
final visibleSeriesProvider =
    NotifierProvider<VisibleSeriesNotifier, VisibleSeries>(
      VisibleSeriesNotifier.new,
    );

class VisibleSeriesNotifier extends Notifier<VisibleSeries> {
  int _generation = 0;
  VisibleSeries _last = const VisibleSeries();

  @override
  VisibleSeries build() {
    final library = ref.watch(seriesLibraryProvider);
    final query = ref.watch(libraryQueryProvider);
    final names =
        ref.watch(libraryLookupsProvider).value?.profileNames ??
        const <int, String>{};
    final runner = ref.read(libraryRunnerProvider);
    final generation = ++_generation;
    // While loading or failed the value belongs to another state or server.
    if (library.isLoading || library.hasError) {
      return _last = const VisibleSeries();
    }
    final data = library.value;
    if (data is! LibraryData) return _last = const VisibleSeries();
    final all = data.snapshot.series;

    VisibleSeries compute() {
      final rows = applyLibraryQuery(all, query, names);
      return VisibleSeries(
        groups: groupSeries(rows, query.sortKey, names),
        count: rows.length,
      );
    }

    if (all.length <= librarySyncLimit) return _last = compute();
    unawaited(
      _computeVisible(runner, all, query, names).then((result) {
        if (!ref.mounted || generation != _generation) return;
        state = _last = result;
      }),
    );
    return VisibleSeries(
      groups: _last.groups,
      count: _last.count,
      computing: true,
    );
  }
}

/// Runs the query through [runner]. A function of its own so the closure sent
/// to another isolate captures only plain data, never the notifier.
Future<VisibleSeries> _computeVisible(
  LibraryRunner runner,
  List<SonarrSeries> all,
  LibraryQuery query,
  Map<int, String> names,
) => runner(() {
  final rows = applyLibraryQuery(all, query, names);
  return VisibleSeries(
    groups: groupSeries(rows, query.sortKey, names),
    count: rows.length,
  );
});
