// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// Shell-provided chrome that screens inside a branch pick up automatically:
/// today the server switcher button (NAV-02), which
/// `FloatingTopBarScaffold` prepends to its actions.
class ShellChrome extends InheritedWidget {
  const ShellChrome({required this.switcher, required super.child, super.key});

  final Widget? switcher;

  static ShellChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellChrome>();

  @override
  bool updateShouldNotify(ShellChrome oldWidget) =>
      oldWidget.switcher != switcher;
}
