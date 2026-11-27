// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:consolarr/src/router.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';

/// Root widget. Must be wrapped in a `ProviderScope`.
class ConsolarrApp extends ConsumerStatefulWidget {
  const ConsolarrApp({super.key});

  @override
  ConsumerState<ConsolarrApp> createState() => _ConsolarrAppState();
}

class _ConsolarrAppState extends ConsumerState<ConsolarrApp> {
  @override
  void initState() {
    super.initState();
    // Database and network work is allowed only after the first frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(firstFrameDoneProvider.notifier).markDone(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ConsolarrTheme.light(),
      darkTheme: ConsolarrTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appSupportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
