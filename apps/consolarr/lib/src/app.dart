// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/presentation/app_lock_gate.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/images/image_cache_config.dart';
import 'package:consolarr/src/providers.dart';
import 'package:consolarr/src/router.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      configureImageCache(PaintingBinding.instance.imageCache);
      ref.read(firstFrameDoneProvider.notifier).markDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final touch = settings.touchTargets;
    final motion = ref.watch(motionPreferenceProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ConsolarrTheme.light(
        highContrast: settings.highContrast,
        touchTargets: touch,
      ),
      darkTheme: ConsolarrTheme.dark(
        highContrast: settings.highContrast,
        touchTargets: touch,
      ),
      // The platform's own high-contrast setting is honoured as well.
      highContrastTheme: ConsolarrTheme.light(
        highContrast: true,
        touchTargets: touch,
      ),
      highContrastDarkTheme: ConsolarrTheme.dark(
        highContrast: true,
        touchTargets: touch,
      ),
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appSupportedLocales,
      routerConfig: ref.watch(routerProvider),
      // Above the navigator: the lock covers routes, dialogs and sheets, and
      // the scopes below reach sheets and dialogs opened from any screen.
      builder: (context, child) => TouchTargetsScope(
        targets: touch,
        child: ConsolarrEffectsScope(
          motion: motion,
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
