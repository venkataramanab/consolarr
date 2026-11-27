// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Turn the app lock on or off and choose when it triggers (SET-02).
class LockSettingsScreen extends ConsumerStatefulWidget {
  const LockSettingsScreen({super.key});

  @override
  ConsumerState<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends ConsumerState<LockSettingsScreen> {
  String? _message;

  String _delayLabel(AppLocalizations l10n, LockDelay d) => switch (d) {
    LockDelay.immediately => l10n.lockDelayImmediately,
    LockDelay.oneMinute => l10n.lockDelayMinutes(1),
    LockDelay.fiveMinutes => l10n.lockDelayMinutes(5),
    LockDelay.fifteenMinutes => l10n.lockDelayMinutes(15),
  };

  Future<void> _toggle(bool on) async {
    final l10n = context.l10n;
    final controller = ref.read(appLockStateProvider.notifier);
    setState(() => _message = null);
    if (on) {
      final reason = l10n.lockReasonEnable;
      final result = await controller.enable(reason: reason);
      if (!mounted) return;
      setState(() {
        _message = switch (result) {
          EnableLockResult.enabled => null,
          EnableLockResult.noSecureLock => l10n.lockNoSecureLock,
          EnableLockResult.notConfirmed => l10n.lockEnableNotConfirmed,
        };
      });
    } else {
      final reason = l10n.lockReasonDisable;
      final ok = await controller.disable(reason: reason);
      if (!mounted) return;
      setState(() => _message = ok ? null : l10n.lockDisableNotConfirmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final support = ref.watch(deviceAuthSupportProvider);

    // Loading and error first, then the value (a reload keeps the previous
    // value in Riverpod, which must not be shown as current).
    final Widget body;
    if (support.isLoading) {
      body = const _Skeleton();
    } else if (support.hasError) {
      body = _Body(
        settings: settings,
        canEnable: false,
        message: l10n.lockNoSecureLock,
        delayLabel: (d) => _delayLabel(l10n, d),
        onToggle: _toggle,
      );
    } else {
      final canEnable = support.value == DeviceAuthSupport.available;
      body = _Body(
        settings: settings,
        canEnable: canEnable,
        message:
            _message ??
            (!canEnable && !settings.lockEnabled
                ? l10n.lockNoSecureLock
                : null),
        delayLabel: (d) => _delayLabel(l10n, d),
        onToggle: _toggle,
      );
    }

    return SettingsPage(
      title: l10n.lockSettingsTitle,
      screen: ScreenName.settingsLock,
      children: [body],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.settings,
    required this.canEnable,
    required this.message,
    required this.delayLabel,
    required this.onToggle,
  });

  final AppSettings settings;
  final bool canEnable;
  final String? message;
  final String Function(LockDelay) delayLabel;
  final Future<void> Function(bool) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final roles = context.roles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: l10n.settingsSectionSecurity,
          children: [
            SwitchRow(
              title: l10n.lockSwitchTitle,
              subtitle: l10n.lockSwitchSubtitle,
              icon: Icons.lock_outline,
              value: settings.lockEnabled,
              // A lock that is on can always be turned off; turning it on
              // needs a secure lock method on the device.
              onChanged: (canEnable || settings.lockEnabled) ? onToggle : null,
            ),
            ChoiceSheetRow<LockDelay>(
              title: l10n.lockDelayTitle,
              icon: Icons.timer_outlined,
              closeLabel: l10n.settingsClose,
              enabled: settings.lockEnabled,
              options: [
                for (final d in LockDelay.values)
                  ChoiceOption(value: d, label: delayLabel(d)),
              ],
              selected: settings.lockDelay,
              onSelected: ref.read(settingsProvider.notifier).setLockDelay,
            ),
          ],
          footer: l10n.lockDelayHint,
        ),
        if (message != null)
          Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.info_outline, color: roles.warning),
                ),
                const SizedBox(width: ConsolarrSpacing.sm),
                Expanded(
                  child: Text(
                    message!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SkeletonBox(height: 72),
      SizedBox(height: ConsolarrSpacing.sm),
      SkeletonBox(height: 56),
    ],
  );
}
