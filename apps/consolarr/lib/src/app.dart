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
    // Consent applies from startup, not only once the Settings tab has been
    // opened: creating the manager loads the stored choice.
    ref.listen<bool>(firstFrameDoneProvider, (_, done) {
      if (done) ref.read(consentManagerProvider);
    });
    // Only what the themes depend on rebuilds this widget; the scopes below
    // watch their own settings.
    final themes = ref.watch(appThemesProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      // The platform's own high-contrast setting is honoured as well.
      highContrastTheme: themes.highContrastLight,
      highContrastDarkTheme: themes.highContrastDark,
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appSupportedLocales,
      routerConfig: ref.watch(routerProvider),
      // Above the navigator: the lock covers routes, dialogs and sheets, and
      // the scopes below reach sheets and dialogs opened from any screen.
      builder: (context, child) => _AppScopes(
        child: AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// The four themes, built once per (high contrast, touch targets) pair.
class AppThemes {
  AppThemes({required bool highContrast, required TouchTargets touchTargets})
    : light = ConsolarrTheme.light(
        highContrast: highContrast,
        touchTargets: touchTargets,
      ),
      dark = ConsolarrTheme.dark(
        highContrast: highContrast,
        touchTargets: touchTargets,
      ),
      highContrastLight = ConsolarrTheme.light(
        highContrast: true,
        touchTargets: touchTargets,
      ),
      highContrastDark = ConsolarrTheme.dark(
        highContrast: true,
        touchTargets: touchTargets,
      );

  final ThemeData light;
  final ThemeData dark;
  final ThemeData highContrastLight;
  final ThemeData highContrastDark;
}

/// The themes follow only high contrast and the touch-target size.
final appThemesProvider = Provider<AppThemes>((ref) {
  final (highContrast, targets) = ref.watch(
    settingsProvider.select((s) => (s.highContrast, s.touchTargets)),
  );
  return AppThemes(highContrast: highContrast, touchTargets: targets);
});

/// Touch-target size and visual effects, from the settings. A widget of its
/// own so that changing one of them does not rebuild `MaterialApp`.
class _AppScopes extends ConsumerWidget {
  const _AppScopes({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(settingsProvider.select((s) => s.touchTargets));
    final motion = ref.watch(motionPreferenceProvider);
    // In-app high contrast also drops the glass (solid surfaces).
    final solid = ref.watch(
      settingsProvider.select((s) => s.highContrast || s.reduceTransparency),
    );
    return TouchTargetsScope(
      targets: targets,
      child: ConsolarrEffectsScope(
        motion: motion,
        reduceTransparency: solid,
        child: child,
      ),
    );
  }
}
