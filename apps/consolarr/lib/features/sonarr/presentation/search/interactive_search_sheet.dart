// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/stand_ins/glass_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';


/// Opens the large release-search sheet for [target]; [title] is the
/// (plain text) heading, for example the episode label.
Future<void> showInteractiveSearch({
  required BuildContext context,
  required InteractiveSearchTarget target,
  required String title,
}) => showGlassSheet<void>(
  context: context,
  title: title,
  closeLabel: context.l10n.sonarrReleaseClose,
  detents: GlassSheetDetents.full,
  builder: (context, controller) => const SizedBox.shrink(),
);
