// SPDX-License-Identifier: GPL-3.0-or-later

/// What a client calls the single-valued grouping of a torrent.
enum LabelModel {
  /// qBittorrent categories.
  category,

  /// Deluge labels (label plugin).
  label,

  /// No single-valued grouping (Transmission has tags only).
  none,
}

/// Which controls a client supports. The UI renders only what is `true`
/// (no disabled mystery buttons); a runtime `UnsupportedAction` from an older
/// server is handled separately.
class TorrentCapabilities {
  const TorrentCapabilities({
    this.alternativeSpeed = false,
    this.labelModel = LabelModel.none,
    this.tags = false,
    this.startPaused = true,
    this.distinctStop = false,
    this.availability = true,
    this.speedLimitUnit = 1,
  });

  /// The alternative speed limits toggle exists.
  final bool alternativeSpeed;

  /// Which single-valued grouping the add form offers.
  final LabelModel labelModel;

  /// Free-form tags (qBittorrent tags, Transmission labels).
  final bool tags;

  /// "Start paused" can be requested when adding.
  final bool startPaused;

  /// Newer qBittorrent reports a stopped state distinct from paused.
  final bool distinctStop;

  /// The detail overview can show distributed copies.
  final bool availability;

  /// Bytes in one unit of the client's speed limits: 1 (exact bytes, qBittorrent),
  /// 1000 (Transmission's kB/s, limits round up to a whole kB/s) or 1024
  /// (Deluge's KiB/s). A UI that shows limits in another unit tells the user
  /// the stored value may differ and should re-read the limits after applying.
  final int speedLimitUnit;

  /// Whether the add form offers a category/label field.
  bool get hasLabel => labelModel != LabelModel.none;

  TorrentCapabilities copyWith({
    bool? alternativeSpeed,
    LabelModel? labelModel,
    bool? tags,
  }) => TorrentCapabilities(
    alternativeSpeed: alternativeSpeed ?? this.alternativeSpeed,
    labelModel: labelModel ?? this.labelModel,
    tags: tags ?? this.tags,
    startPaused: startPaused,
    distinctStop: distinctStop,
    availability: availability,
    speedLimitUnit: speedLimitUnit,
  );

  @override
  bool operator ==(Object other) =>
      other is TorrentCapabilities &&
      other.alternativeSpeed == alternativeSpeed &&
      other.labelModel == labelModel &&
      other.tags == tags &&
      other.startPaused == startPaused &&
      other.distinctStop == distinctStop &&
      other.availability == availability &&
      other.speedLimitUnit == speedLimitUnit;

  @override
  int get hashCode => Object.hash(
    alternativeSpeed,
    labelModel,
    tags,
    startPaused,
    distinctStop,
    availability,
    speedLimitUnit,
  );
}
