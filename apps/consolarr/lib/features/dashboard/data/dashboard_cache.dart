// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:dio/dio.dart';

/// The last good upcoming and recent items per `(serverId, card)`. Only those
/// two cards are cached: the activity card is live and never kept. The rows
/// live in the app's payload cache (excluded from backups) under
/// `dashboard.<card>`.
class DashboardCache {
  DashboardCache(this._cache);

  final PayloadCache _cache;

  static String keyFor(DashboardCard card) => 'dashboard.${card.name}';

  Future<void> write(
    String serverId,
    DashboardCard card,
    List<MediaItem> items,
    DateTime now,
  ) => _cache.write(serverId, keyFor(card), _encode(items), now);

  /// Removes the copy of one card.
  Future<void> delete(String serverId, DashboardCard card) =>
      _cache.delete(serverId, keyFor(card));

  /// Removes both cards of a server.
  Future<void> deleteServer(String serverId) async {
    for (final card in [DashboardCard.upcoming, DashboardCard.recent]) {
      await delete(serverId, card);
    }
  }

  /// Removes the rows of every server that is not in [serverIds].
  Future<void> prune(Set<String> serverIds) =>
      _cache.pruneKeys('dashboard.', serverIds);

  /// The cached items of [card] bound to [dio], with the time they were
  /// stored; `null` when there is none or it cannot be read. With [today] (a
  /// UTC midnight, see `calendarDay`) items of a day that has passed are
  /// dropped: they would read "today".
  Future<({List<MediaItem> items, DateTime at})?> read(
    String serverId,
    DashboardCard card,
    Dio dio, {
    DateTime? today,
  }) async {
    try {
      final row = await _cache.read(serverId, keyFor(card));
      if (row == null) return null;
      var items = _decode(row.json, dio);
      if (items != null && today != null) {
        items = [
          for (final i in items)
            if (i.day == null || !i.day!.isBefore(today)) i,
        ];
      }
      return items == null ? null : (items: items, at: row.fetchedAt);
    } on Object {
      return null;
    }
  }
}

String _encode(List<MediaItem> items) => jsonEncode({
  'v': 1,
  'items': [
    for (final i in items)
      {
        'id': i.id,
        'title': i.title,
        'loc': i.link.location,
        'target': i.link.target.name,
        'dest': i.link.destination.name,
        'art': i.artwork?.toString(),
        'season': i.season,
        'episode': i.episode,
        'release': i.release.name,
        'day': i.day?.millisecondsSinceEpoch,
        'at': i.at?.millisecondsSinceEpoch,
      },
  ],
});

List<MediaItem>? _decode(String json, Dio dio) {
  final decoded = jsonDecode(json);
  if (decoded is! Map || decoded['v'] != 1 || decoded['items'] is! List) {
    return null;
  }
  final out = <MediaItem>[];
  for (final raw in decoded['items'] as List) {
    if (raw is! Map) continue;
    final id = raw['id'];
    final title = raw['title'];
    final loc = raw['loc'];
    if (id is! String || title is! String || loc is! String) continue;
    final target = DashboardTarget.values.asNameMap()[raw['target']];
    final dest = DashboardDestination.values.asNameMap()[raw['dest']];
    if (target == null || dest == null) continue;
    final art = raw['art'];
    final day = raw['day'];
    final at = raw['at'];
    out.add(
      MediaItem(
        id: id,
        title: title,
        link: DashboardLink(loc, target, dest),
        dio: dio,
        artwork: art is String ? Uri.tryParse(art) : null,
        season: raw['season'] is int ? raw['season'] as int : null,
        episode: raw['episode'] is int ? raw['episode'] as int : null,
        release:
            MovieRelease.values.asNameMap()[raw['release']] ??
            MovieRelease.none,
        day: day is int
            ? DateTime.fromMillisecondsSinceEpoch(day, isUtc: true)
            : null,
        at: at is int
            ? DateTime.fromMillisecondsSinceEpoch(at, isUtc: true)
            : null,
      ),
    );
  }
  return out;
}
