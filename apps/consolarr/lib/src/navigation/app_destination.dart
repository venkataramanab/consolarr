// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// One primary destination of the app (a tab of the floating bar and a
/// branch of the shell router). Features contribute their own descriptors
/// (`features/<feature>/<feature>_routes.dart`); `appDestinations` lists them
/// and the router and the bar are both built from that list, so nothing is
/// coupled by position or by an enum.
class AppDestination {
  const AppDestination({
    required this.id,
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.builder,
    this.kinds,
    this.screen,
    this.switcherKind,
  });

  /// Stable identifier (`home`, `sonarr`, ...), for tests and diagnostics.
  final String id;

  /// The branch's route path (`/sonarr`).
  final String route;

  final IconData icon;
  final IconData selectedIcon;

  /// The localized label: the ARB accessor for this destination's label key
  /// (for example `(l10n) => l10n.navSonarr`), checked at compile time.
  final String Function(AppLocalizations l10n) label;

  /// The branch's screen.
  final Widget Function(BuildContext context, GoRouterState state) builder;

  /// The destination is offered once a server of any of these kinds exists;
  /// `null` means always offered (Home, Servers). The destination of the
  /// branch that is currently open is always shown, so the bar never
  /// highlights another tab for the screen the user is on.
  final Set<ServiceKind>? kinds;

  /// Reported as `screen_viewed` when the branch becomes visible.
  final ScreenName? screen;

  /// The service kind whose servers the top bar's switcher offers here.
  final ServiceKind? switcherKind;

  /// Whether this destination serves servers of [kind].
  bool servesKind(ServiceKind kind) => kinds?.contains(kind) ?? false;
}
