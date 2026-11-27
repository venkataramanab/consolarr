// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';

enum ReleaseSortKey { bestMatch, age, size, seeders, indexer, quality }

enum ReleaseAcceptance { all, accepted, rejected }

/// Filters of the interactive search (SON-18 behaviour, RAD-13).
class ReleaseFilter {
  const ReleaseFilter({
    this.acceptance = ReleaseAcceptance.all,
    this.protocol,
    this.resolution,
    this.text = '',
  });

  final ReleaseAcceptance acceptance;

  /// `torrent` or `usenet`; null for any.
  final String? protocol;

  /// 2160, 1080, 720, ... ; null for any.
  final int? resolution;
  final String text;

  ReleaseFilter copyWith({
    ReleaseAcceptance? acceptance,
    Object? protocol = _keep,
    Object? resolution = _keep,
    String? text,
  }) => ReleaseFilter(
    acceptance: acceptance ?? this.acceptance,
    protocol: identical(protocol, _keep) ? this.protocol : protocol as String?,
    resolution: identical(resolution, _keep)
        ? this.resolution
        : resolution as int?,
    text: text ?? this.text,
  );

  bool get isActive =>
      acceptance != ReleaseAcceptance.all ||
      protocol != null ||
      resolution != null ||
      text.trim().isNotEmpty;

  bool matches(RadarrRelease r) {
    if (acceptance == ReleaseAcceptance.accepted && r.rejected) return false;
    if (acceptance == ReleaseAcceptance.rejected && !r.rejected) return false;
    if (protocol != null && r.protocol != protocol) return false;
    if (resolution != null && r.resolution != resolution) return false;
    final t = text.trim().toLowerCase();
    if (t.isNotEmpty && !r.title.toLowerCase().contains(t)) return false;
    return true;
  }
}

const Object _keep = Object();

/// Filters then sorts. "Best match" keeps accepted releases first, then the
/// server's own ranking, then seeders. Ties break on the release name.
List<RadarrRelease> applyReleaseQuery(
  List<RadarrRelease> releases,
  ReleaseSortKey sort,
  ReleaseFilter filter, {
  bool ascending = false,
}) {
  final rows = [
    for (final r in releases)
      if (filter.matches(r)) r,
  ];
  int byName(RadarrRelease a, RadarrRelease b) => a.title.compareTo(b.title);
  int dir(int c) => ascending ? c : -c;
  rows.sort((a, b) {
    final c = switch (sort) {
      ReleaseSortKey.bestMatch => () {
        if (a.rejected != b.rejected) return a.rejected ? 1 : -1;
        final s = b.score.compareTo(a.score);
        if (s != 0) return s;
        return (b.seeders ?? -1).compareTo(a.seeders ?? -1);
      }(),
      ReleaseSortKey.age =>
        ascending
            ? b.ageHours.compareTo(a.ageHours)
            : a.ageHours.compareTo(b.ageHours),
      ReleaseSortKey.size => dir(a.size.compareTo(b.size)),
      ReleaseSortKey.seeders => dir(
        (a.seeders ?? -1).compareTo(b.seeders ?? -1),
      ),
      ReleaseSortKey.indexer =>
        ascending
            ? (a.indexer ?? '').compareTo(b.indexer ?? '')
            : (b.indexer ?? '').compareTo(a.indexer ?? ''),
      ReleaseSortKey.quality => dir(
        (a.resolution ?? 0).compareTo(b.resolution ?? 0),
      ),
    };
    return c != 0 ? c : byName(a, b);
  });
  return rows;
}
