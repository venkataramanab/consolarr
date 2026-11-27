// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Placeholder until the add flow is built (SON-19).
class AddSeriesScreen extends StatelessWidget {
  const AddSeriesScreen({this.initialTerm, super.key});

  /// Pre-filled search term (from the library "search to add" shortcut).
  final String? initialTerm;

  @override
  Widget build(BuildContext context) => const Scaffold();
}
