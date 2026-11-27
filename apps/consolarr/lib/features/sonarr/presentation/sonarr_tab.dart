// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// One tab of the Sonarr area (NAV-03): library, calendar, queue, missing.
///
/// The home screen owns the floating top bar and the tab strip; a tab only
/// supplies its body (built under the bar, using the padding it is given:
/// the measured bar height on top, the nav bar clearance at the bottom) and
/// the top bar actions for when it is selected.
class SonarrTab {
  const SonarrTab({
    required this.id,
    required this.icon,
    required this.label,
    required this.body,
    this.actions,
  });

  /// Stable id (`library`, `calendar`, `queue`, `missing`).
  final String id;
  final IconData icon;
  final String Function(AppLocalizations l10n) label;

  /// The tab body. Check `isLoading` and `hasError` before `value`.
  final Widget Function(BuildContext context, EdgeInsets padding) body;

  /// Top bar buttons while this tab is selected (a [Consumer] may be used
  /// inside to read providers).
  final List<Widget> Function(BuildContext context)? actions;
}
