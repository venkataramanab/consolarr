// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:consolarr_lints/src/no_bad_certificate_callback.dart';
import 'package:consolarr_lints/src/no_print.dart';
import 'package:consolarr_lints/src/no_ui_string.dart';

/// Entry point discovered by the Dart analysis server.
final plugin = ConsolarrLintsPlugin();

/// Registers Consolarr's project-specific analysis rules.
///
/// All rules are registered as warnings so they are enabled by default for
/// every package in the workspace.
class ConsolarrLintsPlugin extends Plugin {
  @override
  String get name => 'consolarr_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(NoUiString())
      ..registerWarningRule(NoBadCertificateCallback())
      ..registerWarningRule(NoPrint());
  }
}
