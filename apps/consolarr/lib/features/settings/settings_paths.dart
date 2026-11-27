// SPDX-License-Identifier: GPL-3.0-or-later

/// Route paths of the settings area. The hub is a shell destination; the
/// sub-screens are its child routes. About and Servers are existing routes
/// owned elsewhere (`AppRoutes.about`, `ServersRoutes.list`); their paths are
/// repeated here so the settings screens do not import the router.
abstract final class SettingsPaths {
  static const hub = '/settings';
  static const lock = '/settings/lock';
  static const privacy = '/settings/privacy';
  static const language = '/settings/language';
  static const accessibility = '/settings/accessibility';
  static const diagnostics = '/settings/diagnostics';
  static const diagnosticsPreview = '/settings/diagnostics/preview';
  static const connectionCheck = '/settings/diagnostics/check';
  static const about = '/about';
  static const servers = '/servers';
}
