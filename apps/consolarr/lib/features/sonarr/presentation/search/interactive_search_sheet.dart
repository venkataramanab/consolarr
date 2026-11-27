// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/stand_ins/glass_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// What an interactive release search looks for (SON-18).
@immutable
class InteractiveSearchTarget {
  const InteractiveSearchTarget.episode(int this.episodeId)
    : seriesId = null,
      seasonNumber = null;

  const InteractiveSearchTarget.season({
    required int this.seriesId,
    required int this.seasonNumber,
  }) : episodeId = null;

  final int? episodeId;
  final int? seriesId;
  final int? seasonNumber;

  @override
  bool operator ==(Object other) =>
      other is InteractiveSearchTarget &&
      other.episodeId == episodeId &&
      other.seriesId == seriesId &&
      other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(episodeId, seriesId, seasonNumber);
}

/// Opens the large release-search sheet for [target]; [title] is the
/// (plain text) heading, for example the episode label.
Future<void> showInteractiveSearch({
  required BuildContext context,
  required InteractiveSearchTarget target,
  required String title,
}) => showGlassSheet<void>(
  context: context,
  title: title,
  closeLabel: context.l10n.commonClose,
  detents: GlassSheetDetents.full,
  builder: (context, controller) => const SizedBox.shrink(),
);
