// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';

/// Keys the library can be sorted by (SON-03).
enum SeriesSortKey {
  title,
  year,
  added,
  nextAiring,
  network,
  size,
  rating,
  qualityProfile,
  genre,
}

/// Which monitored state to show.
enum MonitoredFilter { any, monitored, unmonitored }

/// The filter sheet's selection (SON-04). Empty sets mean "any".
class LibraryFilter {
  const LibraryFilter({
    this.monitored = MonitoredFilter.any,
    this.statuses = const {},
    this.types = const {},
    this.profileIds = const {},
    this.tagIds = const {},
  });

  factory LibraryFilter.fromJson(Object? json) {
    if (json is! Map) return const LibraryFilter();
    Set<T> enums<T extends Enum>(List<T> values, Object? raw) => {
      if (raw is List)
        for (final v in raw)
          for (final e in values)
            if (e.name == v) e,
    };
    Set<int> ints(Object? raw) => {
      if (raw is List)
        for (final v in raw)
          if (v is int) v,
    };
    return LibraryFilter(
      monitored: MonitoredFilter.values.firstWhere(
        (m) => m.name == json['monitored'],
        orElse: () => MonitoredFilter.any,
      ),
      statuses: enums(SeriesStatus.values, json['statuses']),
      types: enums(SeriesType.values, json['types']),
      profileIds: ints(json['profiles']),
      tagIds: ints(json['tags']),
    );
  }

  final MonitoredFilter monitored;
  final Set<SeriesStatus> statuses;
  final Set<SeriesType> types;
  final Set<int> profileIds;
  final Set<int> tagIds;

  /// Number of active criteria (for the badge on the filter button).
  int get activeCount =>
      (monitored == MonitoredFilter.any ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (types.isEmpty ? 0 : 1) +
      (profileIds.isEmpty ? 0 : 1) +
      (tagIds.isEmpty ? 0 : 1);

  bool get isEmpty => activeCount == 0;

  bool matches(SonarrSeries s) {
    if (monitored == MonitoredFilter.monitored && !s.monitored) return false;
    if (monitored == MonitoredFilter.unmonitored && s.monitored) return false;
    if (statuses.isNotEmpty && !statuses.contains(s.status)) return false;
    if (types.isNotEmpty && !types.contains(s.seriesType)) return false;
    if (profileIds.isNotEmpty && !profileIds.contains(s.qualityProfileId)) {
      return false;
    }
    if (tagIds.isNotEmpty && !s.tags.any(tagIds.contains)) return false;
    return true;
  }

  Map<String, Object?> toJson() => {
    'monitored': monitored.name,
    'statuses': [for (final s in statuses) s.name],
    'types': [for (final t in types) t.name],
    'profiles': profileIds.toList(),
    'tags': tagIds.toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      other.monitored == monitored &&
      _setEq(other.statuses, statuses) &&
      _setEq(other.types, types) &&
      _setEq(other.profileIds, profileIds) &&
      _setEq(other.tagIds, tagIds);

  @override
  int get hashCode => Object.hash(
    monitored,
    Object.hashAllUnordered(statuses),
    Object.hashAllUnordered(types),
    Object.hashAllUnordered(profileIds),
    Object.hashAllUnordered(tagIds),
  );
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

/// Search text, sort and filter of the library list.
class LibraryQuery {
  const LibraryQuery({
    this.search = '',
    // Newest additions first: the built-in view shows what was just added. A
    // saved "save as default" replaces it (see `LibraryQueryNotifier`).
    this.sortKey = SeriesSortKey.added,
    this.ascending = false,
    this.filter = const LibraryFilter(),
    this.restored = true,
  });

  final String search;
  final SeriesSortKey sortKey;
  final bool ascending;
  final LibraryFilter filter;

  /// The saved per-server default has been read (or there is none). Until
  /// then the library list is held back, so it never shows in the built-in
  /// order first and re-sorts when the saved one arrives.
  final bool restored;

  bool get isDefaultView => search.trim().isEmpty && filter.isEmpty;

  LibraryQuery copyWith({
    String? search,
    SeriesSortKey? sortKey,
    bool? ascending,
    LibraryFilter? filter,
    bool? restored,
  }) => LibraryQuery(
    search: search ?? this.search,
    sortKey: sortKey ?? this.sortKey,
    ascending: ascending ?? this.ascending,
    filter: filter ?? this.filter,
    restored: restored ?? this.restored,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.search == search &&
      other.sortKey == sortKey &&
      other.ascending == ascending &&
      other.filter == filter &&
      other.restored == restored;

  @override
  int get hashCode => Object.hash(search, sortKey, ascending, filter, restored);
}

/// Saved sort default as stored (`library.sort`).
String encodeSort(SeriesSortKey key, {required bool ascending}) =>
    jsonEncode({'key': key.name, 'asc': ascending});

(SeriesSortKey, bool)? decodeSort(String? raw) {
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return null;
    for (final k in SeriesSortKey.values) {
      if (k.name == m['key']) return (k, m['asc'] != false);
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// What a group header stands for; the screen turns it into text.
sealed class GroupKey {
  const GroupKey();
}

final class GroupText extends GroupKey {
  const GroupText(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is GroupText && other.text == text;
  @override
  int get hashCode => text.hashCode;
}

final class GroupUnknown extends GroupKey {
  const GroupUnknown();
  @override
  bool operator ==(Object other) => other is GroupUnknown;
  @override
  int get hashCode => 0;
}

/// Next airing scheduled (true) or not.
final class GroupScheduled extends GroupKey {
  const GroupScheduled(this.scheduled);
  final bool scheduled;
  @override
  bool operator ==(Object other) =>
      other is GroupScheduled && other.scheduled == scheduled;
  @override
  int get hashCode => scheduled.hashCode;
}

/// Size bucket: 0 small (under 10 GB), 1 medium (under 50 GB), 2 large.
final class GroupSize extends GroupKey {
  const GroupSize(this.bucket);
  final int bucket;
  @override
  bool operator ==(Object other) =>
      other is GroupSize && other.bucket == bucket;
  @override
  int get hashCode => bucket;
}

/// Rating floor (for example 8 for 8.0..8.9).
final class GroupRating extends GroupKey {
  const GroupRating(this.floor);
  final int floor;
  @override
  bool operator ==(Object other) =>
      other is GroupRating && other.floor == floor;
  @override
  int get hashCode => floor;
}

const _gb = 1024 * 1024 * 1024;

/// The group of [s] for sorting by [key]; [profileNames] resolves profiles.
GroupKey groupKeyOf(
  SonarrSeries s,
  SeriesSortKey key,
  Map<int, String> profileNames,
) {
  switch (key) {
    case SeriesSortKey.title:
      final t = s.sortTitle.trim();
      if (t.isEmpty) return const GroupUnknown();
      final first = String.fromCharCode(t.runes.first).toUpperCase();
      return RegExp(r'\p{L}', unicode: true).hasMatch(first)
          ? GroupText(first)
          : const GroupText('#');
    case SeriesSortKey.year:
      return s.year == null ? const GroupUnknown() : GroupText('${s.year}');
    case SeriesSortKey.added:
      final d = s.added?.toLocal();
      return d == null ? const GroupUnknown() : GroupText('${d.year}');
    case SeriesSortKey.nextAiring:
      return GroupScheduled(s.nextAiring != null);
    case SeriesSortKey.network:
      final n = s.network?.trim();
      return n == null || n.isEmpty ? const GroupUnknown() : GroupText(n);
    case SeriesSortKey.size:
      final b = s.statistics.sizeOnDisk;
      return GroupSize(b < 10 * _gb ? 0 : (b < 50 * _gb ? 1 : 2));
    case SeriesSortKey.rating:
      return s.rating <= 0
          ? const GroupUnknown()
          : GroupRating(s.rating.floor());
    case SeriesSortKey.qualityProfile:
      final name = profileNames[s.qualityProfileId];
      return name == null ? const GroupUnknown() : GroupText(name);
    case SeriesSortKey.genre:
      return s.genres.isEmpty
          ? const GroupUnknown()
          : GroupText(s.genres.first);
  }
}

int _cmpNullsLast<T extends Comparable<Object>>(T? a, T? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

/// Filters, searches and sorts [all]. Pure and top level, so it can run on
/// another isolate for big libraries. Missing values sort last in either
/// direction; ties break on the title.
List<SonarrSeries> applyLibraryQuery(
  List<SonarrSeries> all,
  LibraryQuery q,
  Map<int, String> profileNames,
) {
  final needle = q.search.trim().toLowerCase();
  final rows = [
    for (final s in all)
      if (q.filter.matches(s) &&
          (needle.isEmpty || s.title.toLowerCase().contains(needle)))
        s,
  ];
  int byKey(SonarrSeries a, SonarrSeries b) => switch (q.sortKey) {
    SeriesSortKey.title => a.sortTitle.compareTo(b.sortTitle),
    SeriesSortKey.year => _cmpNullsLast(a.year, b.year),
    SeriesSortKey.added => _cmpNullsLast(a.added, b.added),
    SeriesSortKey.nextAiring => _cmpNullsLast(a.nextAiring, b.nextAiring),
    SeriesSortKey.network => _cmpNullsLast(
      a.network?.toLowerCase(),
      b.network?.toLowerCase(),
    ),
    SeriesSortKey.size => a.statistics.sizeOnDisk.compareTo(
      b.statistics.sizeOnDisk,
    ),
    SeriesSortKey.rating => a.rating.compareTo(b.rating),
    SeriesSortKey.qualityProfile => _cmpNullsLast(
      profileNames[a.qualityProfileId]?.toLowerCase(),
      profileNames[b.qualityProfileId]?.toLowerCase(),
    ),
    SeriesSortKey.genre => _cmpNullsLast(
      a.genres.isEmpty ? null : a.genres.first.toLowerCase(),
      b.genres.isEmpty ? null : b.genres.first.toLowerCase(),
    ),
  };
  // Keys whose missing values must stay last whichever way the list runs.
  final nullable = {
    SeriesSortKey.year,
    SeriesSortKey.added,
    SeriesSortKey.nextAiring,
    SeriesSortKey.network,
    SeriesSortKey.qualityProfile,
    SeriesSortKey.genre,
  }.contains(q.sortKey);
  bool missing(SonarrSeries s) => switch (q.sortKey) {
    SeriesSortKey.year => s.year == null,
    SeriesSortKey.added => s.added == null,
    SeriesSortKey.nextAiring => s.nextAiring == null,
    SeriesSortKey.network => s.network == null,
    SeriesSortKey.qualityProfile => profileNames[s.qualityProfileId] == null,
    SeriesSortKey.genre => s.genres.isEmpty,
    _ => false,
  };
  rows.sort((a, b) {
    if (nullable) {
      final ma = missing(a);
      final mb = missing(b);
      if (ma != mb) return ma ? 1 : -1;
    }
    var c = byKey(a, b);
    if (!q.ascending) c = -c;
    return c != 0 ? c : a.sortTitle.compareTo(b.sortTitle);
  });
  return rows;
}

/// A run of consecutive series sharing a group.
class SeriesGroup {
  const SeriesGroup(this.key, this.series);
  final GroupKey key;
  final List<SonarrSeries> series;
}

/// Splits sorted [rows] into groups for the sticky headers.
List<SeriesGroup> groupSeries(
  List<SonarrSeries> rows,
  SeriesSortKey key,
  Map<int, String> profileNames,
) {
  final groups = <SeriesGroup>[];
  GroupKey? current;
  var bucket = <SonarrSeries>[];
  for (final s in rows) {
    final k = groupKeyOf(s, key, profileNames);
    if (current != k) {
      if (current != null) groups.add(SeriesGroup(current, bucket));
      current = k;
      bucket = [];
    }
    bucket.add(s);
  }
  if (current != null) groups.add(SeriesGroup(current, bucket));
  return groups;
}

/// The saved filter as stored (`library.filter`).
String encodeFilter(LibraryFilter filter) => jsonEncode(filter.toJson());

/// Decodes JSON text; throws [FormatException] when it is not JSON.
Object? jsonDecodeLoose(String raw) => jsonDecode(raw);
