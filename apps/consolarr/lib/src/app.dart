// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/providers.dart';
import 'package:consolarr/src/router.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';

/// Root widget. Must be wrapped in a `ProviderScope`.
class ConsolarrApp extends ConsumerWidget {
  const ConsolarrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ConsolarrTheme.light(),
      darkTheme: ConsolarrTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
