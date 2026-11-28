// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The three cards of the dashboard, in display order.
enum DashboardCard { activity, upcoming, recent }

/// Where a tap goes. A tab is switched to (`go`), a detail screen is pushed.
enum DashboardTarget { tab, detail }

/// What a tap on an item opens (for the `dashboard_card_opened` event).
enum DashboardDestination { series, movie, sonarr, radarr, torrents }

/// Where an item leads: a location plus how to get there. Plain values.
@immutable
class DashboardLink {
  const DashboardLink(this.location, this.target, this.destination);

  final String location;
  final DashboardTarget target;
  final DashboardDestination destination;

  @override
  bool operator ==(Object other) =>
      other is DashboardLink &&
      other.location == location &&
      other.target == target &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(location, target, destination);
}

/// What a download row is doing, as one small set for every service.
enum ActivityState {
  downloading,
  stalled,
  checking,
  queued,
  paused,
  importing,
  completed,
  seeding,
  attention,
}

/// One download (a queue item or a torrent) on the activity card. Server text
/// ([title]) is shown as plain text only.
@immutable
class ActivityRow {
  const ActivityRow({
    required this.id,
    required this.title,
    required this.state,
    required this.progress,
    this.sizeLeft,
    this.eta,
    this.speed,
  });

  /// Stable within a server (the queue id or the torrent hash).
  final String id;
  final String title;
  final ActivityState state;

  /// 0..1.
  final double progress;

  /// Bytes left, when known.
  final int? sizeLeft;
  final Duration? eta;

  /// Bytes per second, when known.
  final int? speed;

  @override
  bool operator ==(Object other) =>
      other is ActivityRow &&
      other.id == id &&
      other.title == title &&
      other.state == state &&
      other.progress == progress &&
      other.sizeLeft == sizeLeft &&
      other.eta == eta &&
      other.speed == speed;

  @override
  int get hashCode =>
      Object.hash(id, title, state, progress, sizeLeft, eta, speed);
}

/// What one server contributes to the activity card.
@immutable
class ActivitySummary {
  const ActivitySummary({
    required this.active,
    required this.attention,
    required this.rows,
    required this.link,
    this.downSpeed,
    this.upSpeed,
    this.speedUnavailable = false,
  });

  /// Downloads in progress.
  final int active;

  /// Failed items and items with warnings.
  final int attention;

  /// The few rows worth showing (at most [kActivityRows]).
  final List<ActivityRow> rows;

  /// Where a tap on the summary goes (the service tab).
  final DashboardLink link;

  /// Global speeds in bytes per second (torrent clients).
  final int? downSpeed;
  final int? upSpeed;

  /// The list loaded but the statistics did not.
  final bool speedUnavailable;

  /// Nothing to show: no downloads and nothing that needs attention.
  bool get isIdle => active == 0 && attention == 0 && rows.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ActivitySummary &&
      other.active == active &&
      other.attention == attention &&
      other.link == link &&
      other.downSpeed == downSpeed &&
      other.upSpeed == upSpeed &&
      other.speedUnavailable == speedUnavailable &&
      listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    active,
    attention,
    link,
    downSpeed,
    upSpeed,
    Object.hashAll(rows),
  );
}

/// Rows shown per server on the activity card.
const kActivityRows = 3;

/// Items per carousel.
const kCarouselItems = 20;

/// An episode or movie for the upcoming and recent carousels.
@immutable
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.link,
    required this.dio,
    this.artwork,
    this.season,
    this.episode,
    this.release = MovieRelease.none,
    this.day,
    this.at,
  });

  /// Stable within a server (`ep:12`, `mv:3`, `hist:9`).
  final String id;
  final String title;
  final DashboardLink link;

  /// The server's own Dio; artwork goes through it and nothing else does.
  final Dio dio;

  /// Server-relative artwork URL, never with credentials.
  final Uri? artwork;
  final int? season;
  final int? episode;

  /// Which release of a movie [day] is (upcoming only).
  final MovieRelease release;

  /// The calendar day the item comes out (upcoming): a UTC midnight that
  /// stands for the local day (episodes) or for the release date as given
  /// (movies, which never shift with the time zone).
  final DateTime? day;

  /// When the item was imported (recent).
  final DateTime? at;

  bool get isEpisode => season != null && episode != null;

  @override
  bool operator ==(Object other) =>
      other is MediaItem &&
      other.id == id &&
      other.title == title &&
      other.link == link &&
      identical(other.dio, dio) &&
      other.artwork == artwork &&
      other.season == season &&
      other.episode == episode &&
      other.release == release &&
      other.day == day &&
      other.at == at;

  @override
  int get hashCode =>
      Object.hash(id, title, link, identityHashCode(dio), artwork, day, at);
}

enum MovieRelease { none, cinemas, digital, disc }

/// One server's share of a card: its items, or why it has none.
@immutable
sealed class CardSlice<T> {
  const CardSlice({
    required this.serverId,
    required this.serverName,
    required this.kind,
  });

  final String serverId;
  final String serverName;
  final ServiceKind kind;
}

/// The server answered.
final class SliceData<T> extends CardSlice<T> {
  const SliceData({
    required super.serverId,
    required super.serverName,
    required super.kind,
    required this.value,
    this.cachedAt,
  });

  final T value;

  /// Set when [value] is the last good copy because the server could not be
  /// reached. Never set after `auth_failed`, TLS or version errors.
  final DateTime? cachedAt;

  @override
  bool operator ==(Object other) =>
      other is SliceData<T> &&
      other.serverId == serverId &&
      other.kind == kind &&
      other.serverName == serverName &&
      other.cachedAt == cachedAt &&
      _valueEquals(other.value, value);

  @override
  int get hashCode => Object.hash(serverId, kind, cachedAt, _valueHash(value));
}

/// The server failed; the rest of the card is unaffected.
final class SliceFailed<T> extends CardSlice<T> {
  const SliceFailed({
    required super.serverId,
    required super.serverName,
    required super.kind,
    required this.error,
  });

  final AppError error;

  /// A Deluge web interface that needs its daemon host chosen first.
  bool get needsHostChoice => error is HostChoiceRequired;

  @override
  bool operator ==(Object other) =>
      other is SliceFailed<T> &&
      other.serverId == serverId &&
      other.kind == kind &&
      other.serverName == serverName &&
      other.error == error;

  @override
  int get hashCode => Object.hash(serverId, kind, error);
}

/// The server has not answered yet (first load only; a refresh keeps the
/// previous slice on screen).
final class SliceLoading<T> extends CardSlice<T> {
  const SliceLoading({
    required super.serverId,
    required super.serverName,
    required super.kind,
  });

  @override
  bool operator ==(Object other) =>
      other is SliceLoading<T> &&
      other.serverId == serverId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(serverId, kind);
}

/// The Deluge client says "choose the daemon host first". The source maps its
/// typed error to this one, so the UI needs no torrent type and the host list
/// (addresses) never reaches the card.
class HostChoiceRequired extends AppError {
  const HostChoiceRequired() : super(ErrorCategory.notFound);
}

bool _valueEquals(Object? a, Object? b) {
  if (a is List && b is List) return listEquals(a, b);
  return a == b;
}

int _valueHash(Object? v) => v is List ? Object.hashAll(v) : v.hashCode;

/// What one card shows (sealed, like every feature state).
@immutable
sealed class CardState<T> {
  const CardState();
}

/// Nothing has answered yet.
final class CardLoading<T> extends CardState<T> {
  const CardLoading();

  @override
  bool operator ==(Object other) => other is CardLoading<T>;

  @override
  int get hashCode => 1;
}

/// No server of any kind this card reads from is configured.
final class CardNotConfigured<T> extends CardState<T> {
  const CardNotConfigured();

  @override
  bool operator ==(Object other) => other is CardNotConfigured<T>;

  @override
  int get hashCode => 2;
}

/// Every server answered and there is nothing to show.
final class CardEmpty<T> extends CardState<T> {
  const CardEmpty();

  @override
  bool operator ==(Object other) => other is CardEmpty<T>;

  @override
  int get hashCode => 3;
}

/// At least one server contributes content, a failure or a skeleton. Slices
/// that answered with nothing are already left out.
final class CardData<T> extends CardState<T> {
  const CardData(this.slices);

  final List<CardSlice<T>> slices;

  @override
  bool operator ==(Object other) =>
      other is CardData<T> && listEquals(other.slices, slices);

  @override
  int get hashCode => Object.hashAll(slices);
}

/// Every server of the card failed.
final class CardError<T> extends CardState<T> {
  const CardError(this.slices);

  final List<SliceFailed<T>> slices;

  @override
  bool operator ==(Object other) =>
      other is CardError<T> && listEquals(other.slices, slices);

  @override
  int get hashCode => Object.hashAll(slices);
}

/// The three cards at once. Value equality: an unchanged poll gives an equal
/// snapshot and each card's `select` stays quiet.
@immutable
class DashboardSnapshot {
  const DashboardSnapshot({
    this.activity = const CardLoading(),
    this.upcoming = const CardLoading(),
    this.recent = const CardLoading(),
  });

  final CardState<ActivitySummary> activity;
  final CardState<List<MediaItem>> upcoming;
  final CardState<List<MediaItem>> recent;

  @override
  bool operator ==(Object other) =>
      other is DashboardSnapshot &&
      other.activity == activity &&
      other.upcoming == upcoming &&
      other.recent == recent;

  @override
  int get hashCode => Object.hash(activity, upcoming, recent);
}
