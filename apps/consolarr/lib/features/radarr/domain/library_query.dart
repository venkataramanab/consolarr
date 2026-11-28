// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';

/// Sort keys of the movie library (RAD-03).
enum MovieSortKey {
  title,
  year,
  added,
  downloaded,
  theatrical,
  digital,
  size,
  rating,
  popularity,
  qualityProfile,
  genre,
}

enum MonitoredFilter { any, monitored, unmonitored }

enum FileFilter { any, downloaded, missing }

/// Active filters (RAD-04). Empty sets and `any` mean "no restriction".
class MovieFilter {
  const MovieFilter({
    this.monitored = MonitoredFilter.any,
    this.file = FileFilter.any,
    this.availability = const {},
    this.qualityProfiles = const {},
    this.tags = const {},
    this.collections = const {},
  });

  final MonitoredFilter monitored;
  final FileFilter file;
  final Set<MinimumAvailability> availability;
  final Set<int> qualityProfiles;
  final Set<int> tags;
  final Set<String> collections;

  static const none = MovieFilter();

  /// Number of restricted dimensions, for the "N active" indicator.
  int get activeCount =>
      (monitored != MonitoredFilter.any ? 1 : 0) +
      (file != FileFilter.any ? 1 : 0) +
      (availability.isNotEmpty ? 1 : 0) +
      (qualityProfiles.isNotEmpty ? 1 : 0) +
      (tags.isNotEmpty ? 1 : 0) +
      (collections.isNotEmpty ? 1 : 0);

  bool get isActive => activeCount > 0;

  bool matches(RadarrMovie m) {
    if (monitored == MonitoredFilter.monitored && !m.monitored) return false;
    if (monitored == MonitoredFilter.unmonitored && m.monitored) return false;
    if (file == FileFilter.downloaded && !m.hasFile) return false;
    if (file == FileFilter.missing && m.hasFile) return false;
    if (availability.isNotEmpty &&
        !availability.contains(m.minimumAvailability)) {
      return false;
    }
    if (qualityProfiles.isNotEmpty &&
        !qualityProfiles.contains(m.qualityProfileId)) {
      return false;
    }
    if (tags.isNotEmpty && !m.tags.any(tags.contains)) return false;
    if (collections.isNotEmpty && !collections.contains(m.collectionTitle)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'monitored': monitored.name,
    'file': file.name,
    'availability': [for (final a in availability) a.name],
    'profiles': qualityProfiles.toList(),
    'tags': tags.toList(),
    'collections': collections.toList(),
  };

  factory MovieFilter.fromJson(Map<String, Object?> json) {
    T pick<T extends Enum>(List<T> values, Object? v, T fallback) {
      for (final e in values) {
        if (e.name == v) return e;
      }
      return fallback;
    }

    List<T> list<T>(Object? v) => v is List ? v.whereType<T>().toList() : [];
    return MovieFilter(
      monitored: pick(
        MonitoredFilter.values,
        json['monitored'],
        MonitoredFilter.any,
      ),
      file: pick(FileFilter.values, json['file'], FileFilter.any),
      availability: {
        for (final n in list<String>(json['availability']))
          pick(MinimumAvailability.values, n, MinimumAvailability.unknown),
      }..remove(MinimumAvailability.unknown),
      qualityProfiles: list<int>(json['profiles']).toSet(),
      tags: list<int>(json['tags']).toSet(),
      collections: list<String>(json['collections']).toSet(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MovieFilter &&
      other.monitored == monitored &&
      other.file == file &&
      _setEq(other.availability, availability) &&
      _setEq(other.qualityProfiles, qualityProfiles) &&
      _setEq(other.tags, tags) &&
      _setEq(other.collections, collections);

  @override
  int get hashCode => Object.hash(
    monitored,
    file,
    Object.hashAllUnordered(availability),
    Object.hashAllUnordered(qualityProfiles),
    Object.hashAllUnordered(tags),
    Object.hashAllUnordered(collections),
  );
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

/// How the library is ordered, filtered and searched.
class MovieQuery {
  const MovieQuery({
    // Newest additions first: the built-in view shows what was just added. A
    // saved "save as default" replaces it (see `LibraryQueryNotifier`).
    this.sort = MovieSortKey.added,
    this.ascending = false,
    this.filter = MovieFilter.none,
    this.search = '',
  });

  final MovieSortKey sort;
  final bool ascending;
  final MovieFilter filter;
  final String search;

  MovieQuery copyWith({
    MovieSortKey? sort,
    bool? ascending,
    MovieFilter? filter,
    String? search,
  }) => MovieQuery(
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    filter: filter ?? this.filter,
    search: search ?? this.search,
  );

  @override
  bool operator ==(Object other) =>
      other is MovieQuery &&
      other.sort == sort &&
      other.ascending == ascending &&
      other.filter == filter &&
      other.search == search;

  @override
  int get hashCode => Object.hash(sort, ascending, filter, search);
}

/// Sort/filter/search (RAD-02..04). Movies without a value for the sort key
/// always go last, in either direction; ties break on title then id.
List<RadarrMovie> applyQuery(
  List<RadarrMovie> movies,
  MovieQuery query, {
  Map<int, String> profileNames = const {},
}) {
  final needle = query.search.trim().toLowerCase();
  final rows = [
    for (final m in movies)
      if (query.filter.matches(m) &&
          (needle.isEmpty || m.title.toLowerCase().contains(needle)))
        m,
  ];
  final dir = query.ascending ? 1 : -1;
  int byTitle(RadarrMovie a, RadarrMovie b) {
    final c = a.sortTitle.compareTo(b.sortTitle);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  int cmp<T extends Comparable<Object>>(
    T? a,
    T? b,
    RadarrMovie x,
    RadarrMovie y,
  ) {
    if (a == null && b == null) return byTitle(x, y);
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.compareTo(b);
    return c != 0 ? c * dir : byTitle(x, y);
  }

  rows.sort(
    (a, b) => switch (query.sort) {
      MovieSortKey.title => byTitle(a, b) * dir,
      MovieSortKey.year => cmp<num>(a.year, b.year, a, b),
      MovieSortKey.added => cmp<DateTime>(a.added, b.added, a, b),
      MovieSortKey.downloaded => cmp<DateTime>(
        a.movieFile?.dateAdded,
        b.movieFile?.dateAdded,
        a,
        b,
      ),
      MovieSortKey.theatrical => cmp<DateTime>(a.inCinemas, b.inCinemas, a, b),
      MovieSortKey.digital => cmp<DateTime>(
        a.digitalRelease,
        b.digitalRelease,
        a,
        b,
      ),
      MovieSortKey.size => cmp<num>(
        a.sizeOnDisk > 0 ? a.sizeOnDisk : null,
        b.sizeOnDisk > 0 ? b.sizeOnDisk : null,
        a,
        b,
      ),
      MovieSortKey.rating => cmp<num>(a.rating, b.rating, a, b),
      MovieSortKey.popularity => cmp<num>(a.popularity, b.popularity, a, b),
      MovieSortKey.qualityProfile => cmp<String>(
        profileNames[a.qualityProfileId]?.toLowerCase(),
        profileNames[b.qualityProfileId]?.toLowerCase(),
        a,
        b,
      ),
      MovieSortKey.genre => cmp<String>(
        a.genres.isEmpty ? null : a.genres.first.toLowerCase(),
        b.genres.isEmpty ? null : b.genres.first.toLowerCase(),
        a,
        b,
      ),
    },
  );
  return rows;
}

/// The group a movie falls in under [key], or null when the key has no
/// groups (group headers and the jump control only exist for title and year).
String? groupOf(RadarrMovie m, MovieSortKey key) => switch (key) {
  MovieSortKey.title => _letter(m.sortTitle.isEmpty ? m.title : m.sortTitle),
  MovieSortKey.year => m.year?.toString() ?? '',
  _ => null,
};

String _letter(String s) {
  final first = s.trimLeft().isEmpty ? '' : s.trimLeft().substring(0, 1);
  final upper = first.toUpperCase();
  return RegExp(r'^\p{L}$', unicode: true).hasMatch(upper) ? upper : '#';
}

/// Consecutive runs of [rows] that share a group.
class MovieGroup {
  const MovieGroup(this.label, this.movies);

  /// Empty for "no group" (unknown year).
  final String label;
  final List<RadarrMovie> movies;
}

List<MovieGroup> groupMovies(List<RadarrMovie> rows, MovieSortKey key) {
  final out = <MovieGroup>[];
  String? current;
  var bucket = <RadarrMovie>[];
  for (final m in rows) {
    final g = groupOf(m, key);
    if (g == null) return [MovieGroup('', rows)];
    if (g != current && bucket.isNotEmpty) {
      out.add(MovieGroup(current!, bucket));
      bucket = [];
    }
    current = g;
    bucket.add(m);
  }
  if (bucket.isNotEmpty) out.add(MovieGroup(current!, bucket));
  return out;
}

/// Ids of the removable chips of [f], in display order: `monitored`, `file`,
/// `availability:<name>`, `profile:<id>`, `tag:<id>`, `collection:<name>`.
List<String> activeFilterIds(MovieFilter f) => [
  if (f.monitored != MonitoredFilter.any) 'monitored',
  if (f.file != FileFilter.any) 'file',
  for (final a in f.availability) 'availability:${a.name}',
  for (final p in f.qualityProfiles) 'profile:$p',
  for (final t in f.tags) 'tag:$t',
  for (final c in f.collections) 'collection:$c',
];

/// [f] without the criterion behind chip [id] (see [activeFilterIds]).
MovieFilter removeFilter(MovieFilter f, String id) {
  final colon = id.indexOf(':');
  final kind = colon < 0 ? id : id.substring(0, colon);
  final value = colon < 0 ? '' : id.substring(colon + 1);
  return MovieFilter(
    monitored: kind == 'monitored' ? MonitoredFilter.any : f.monitored,
    file: kind == 'file' ? FileFilter.any : f.file,
    availability: kind == 'availability'
        ? {
            for (final a in f.availability)
              if (a.name != value) a,
          }
        : f.availability,
    qualityProfiles: kind == 'profile'
        ? {
            for (final p in f.qualityProfiles)
              if ('$p' != value) p,
          }
        : f.qualityProfiles,
    tags: kind == 'tag'
        ? {
            for (final t in f.tags)
              if ('$t' != value) t,
          }
        : f.tags,
    collections: kind == 'collection'
        ? {
            for (final c in f.collections)
              if (c != value) c,
          }
        : f.collections,
  );
}
