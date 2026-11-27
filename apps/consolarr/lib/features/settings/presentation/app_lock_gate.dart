// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The app lock (SET-02), placed **above the navigator** (in
/// `MaterialApp.builder`), so routes, dialogs and sheets all sit beneath it.
///
/// * On a cold start the first frame is an opaque neutral cover and the app
///   content is not even built; it is mounted only after the lock state
///   resolves to disabled or unlocked.
/// * While locked (and while the app is inactive or paused with the lock on)
///   the content is not painted, is excluded from semantics, has its tickers
///   disabled, and `appLockedProvider` is true so polling pauses. It keeps its
///   state, so a dialog open before backgrounding is still there after unlock.
/// * While the lock is on (or "block screenshots" is), the window is flagged
///   secure through the `SecureScreen` seam, so the recent-apps thumbnail is
///   blank.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final GlobalKey _contentKey = GlobalKey();
  bool _contentBuilt = false;
  bool _lifecycleCover = false;
  bool _prompted = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lockOn = ref.read(settingsProvider).lockEnabled;
    final controller = ref.read(appLockStateProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        controller.onResumed();
        if (_lifecycleCover) setState(() => _lifecycleCover = false);
      case AppLifecycleState.inactive:
        if (lockOn && !_lifecycleCover) setState(() => _lifecycleCover = true);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        controller.onBackgrounded();
        if (lockOn && !_lifecycleCover) setState(() => _lifecycleCover = true);
      case AppLifecycleState.detached:
        break;
    }
  }

  void _applySecure(bool wanted) {
    PlatformSecureScreen.setBaseline(secure: wanted);
    unawaited(ref.read(secureScreenProvider).setSecure(secure: wanted));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      settingsProvider.select((s) => s.wantsSecureWindow),
      (_, wanted) => _applySecure(wanted),
    );
    final lock = ref.watch(appLockStateProvider);
    final visible = lock.contentVisible;
    if (visible) _contentBuilt = true;
    final hidden = !visible || _lifecycleCover;
    if (!lock.locked) _prompted = false;

    final cooling = lock.coolingDown(ref.read(clockProvider)());
    if (cooling) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_contentBuilt)
          Offstage(
            offstage: hidden,
            child: TickerMode(
              enabled: !hidden,
              child: ExcludeSemantics(
                excluding: hidden,
                child: KeyedSubtree(key: _contentKey, child: widget.child),
              ),
            ),
          ),
        if (hidden)
          Positioned.fill(
            child: lock.locked && !_lifecycleCover
                ? _LockScreen(
                    state: lock,
                    cooling: cooling,
                    onFirstShown: _maybePrompt,
                  )
                : const _NeutralCover(),
          ),
      ],
    );
  }

  void _maybePrompt() {
    if (_prompted) return;
    _prompted = true;
    final reason = context.l10n.lockReasonUnlock;
    unawaited(
      ref.read(appLockStateProvider.notifier).authenticate(reason: reason),
    );
  }
}

/// An opaque cover with nothing on it: the first frame, and the recents
/// preview while the lock is on.
class _NeutralCover extends StatelessWidget {
  const _NeutralCover();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: color,
      child: Semantics(
        container: true,
        label: _coverLabel(context),
        child: const SizedBox.expand(),
      ),
    );
  }

  String? _coverLabel(BuildContext context) {
    try {
      return context.l10n.lockCoverLabel;
    } on Object {
      return null;
    }
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({
    required this.state,
    required this.cooling,
    required this.onFirstShown,
  });

  final AppLockState state;
  final bool cooling;
  final VoidCallback onFirstShown;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  bool _confirmingTurnOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstShown();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final s = widget.state;
    final controller = ref.read(appLockStateProvider.notifier);
    final removed = s.problem == LockProblem.secureLockRemoved;
    final remaining = s.coolDownUntil == null
        ? 0
        : ((s.coolDownUntil!
                          .difference(ref.read(clockProvider)())
                          .inMilliseconds +
                      999) ~/
                  1000)
              .clamp(1, 3600);
    final touch = TouchTargets.of(context).minimum;

    final children = <Widget>[
      ExcludeSemantics(
        child: Icon(
          removed ? Icons.lock_open : Icons.lock_outline,
          size: 48,
          color: roles.accent,
        ),
      ),
      const SizedBox(height: ConsolarrSpacing.lg),
      Semantics(
        header: true,
        child: Text(
          removed ? l10n.lockRemovedTitle : l10n.lockScreenTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: ConsolarrSpacing.sm),
      Text(
        removed ? l10n.lockRemovedBody : l10n.lockScreenBody,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      if (!removed && s.lastAttemptFailed && !widget.cooling) ...[
        const SizedBox(height: ConsolarrSpacing.md),
        _Notice(icon: Icons.error_outline, text: l10n.lockFailedFeedback),
      ],
      if (widget.cooling) ...[
        const SizedBox(height: ConsolarrSpacing.md),
        _Notice(icon: Icons.timer_outlined, text: l10n.lockCoolDown(remaining)),
      ],
      if (!removed && !s.biometricsAvailable) ...[
        const SizedBox(height: ConsolarrSpacing.md),
        _Notice(icon: Icons.info_outline, text: l10n.lockBiometricsUnavailable),
      ],
      const SizedBox(height: ConsolarrSpacing.xl),
    ];

    if (removed) {
      if (_confirmingTurnOff) {
        children
          ..add(
            Text(
              l10n.lockTurnOffConfirmBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          )
          ..add(const SizedBox(height: ConsolarrSpacing.md))
          ..add(
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
              onPressed: controller.turnOffAfterCredentialRemoved,
              child: Text(l10n.lockTurnOffConfirm),
            ),
          )
          ..add(const SizedBox(height: ConsolarrSpacing.sm))
          ..add(
            TextButton(
              style: TextButton.styleFrom(minimumSize: Size(0, touch)),
              onPressed: () => setState(() => _confirmingTurnOff = false),
              child: Text(l10n.lockKeepOn),
            ),
          );
      } else {
        children.add(
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
            onPressed: () => setState(() => _confirmingTurnOff = true),
            child: Text(l10n.lockTurnOffButton),
          ),
        );
      }
    } else {
      children.add(
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
          onPressed: (s.authenticating || widget.cooling)
              ? null
              : () => controller.authenticate(reason: l10n.lockReasonUnlock),
          child: Text(l10n.lockUnlockButton),
        ),
      );
    }

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ConsolarrSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                scopesRoute: true,
                namesRoute: true,
                label: l10n.lockScreenTitle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon plus text, never colour alone.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: roles.warning, size: 20)),
          const SizedBox(width: ConsolarrSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
