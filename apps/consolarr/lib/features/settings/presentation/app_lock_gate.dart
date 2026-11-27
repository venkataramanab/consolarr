// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The app lock (SET-02), placed **above the navigator** (in
/// `MaterialApp.builder`), so routes, dialogs and sheets all sit beneath it.
///
/// * On a cold start the first frame is an opaque neutral cover. The content
///   is mounted at once but hidden (not painted, no semantics, no focus, no
///   tickers) so the shell is warm when the lock state resolves; it is shown
///   only when that is disabled or unlocked.
/// * While locked or resolving (and while the app is inactive or paused with
///   the lock on) the content is hidden the same way, and `appLockedProvider`
///   is true so polling pauses. It keeps its state, so a dialog open before
///   backgrounding is still there after unlock.
/// * If the stored settings cannot be read the lock **fails closed**: the
///   content stays hidden, the window secure, and the screen offers "try
///   again".
/// * System back never pops the routes behind the lock screen.
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
  bool _lifecycleCover = false;
  bool _hidden = true;
  bool _lockShown = false;
  bool _prompted = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The one-second tick runs only while a cool-down lasts.
    ref.listenManual<DateTime?>(
      appLockStateProvider.select((s) => s.coolDownUntil),
      (_, _) => _syncTick(),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  /// The system back button while the lock (or its cover) is showing: never
  /// pops the routes behind it. On the lock screen it leaves the app.
  @override
  Future<bool> didPopRoute() async {
    if (!_hidden) return false;
    if (_lockShown) unawaited(SystemNavigator.pop());
    return true;
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

  void _applySecure(bool wanted) => unawaited(
    ref.read(secureScreenProvider).setSecure(secure: wanted, owner: this),
  );

  /// Runs the one-second tick only while the cool-down lasts; announces once
  /// when unlocking is possible again.
  void _syncTick() {
    final lock = ref.read(appLockStateProvider);
    final cooling = lock.coolingDown(ref.read(clockProvider)());
    if (cooling && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final still = ref
            .read(appLockStateProvider)
            .coolingDown(ref.read(clockProvider)());
        if (!still) {
          _tick?.cancel();
          _tick = null;
          _announceCoolDownOver();
        }
        setState(() {});
      });
    } else if (!cooling && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _announceCoolDownOver() {
    if (!ref.read(appLockStateProvider).locked) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.lockCoolDownOver,
        Directionality.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      settingsProvider.select((s) => s.wantsSecureWindow),
      (_, wanted) => _applySecure(wanted),
    );
    final lock = ref.watch(appLockStateProvider);
    final hidden = !lock.contentVisible || _lifecycleCover;
    if (!lock.locked) _prompted = false;
    _hidden = hidden;
    _lockShown = lock.locked && !_lifecycleCover;

    final cooling = lock.coolingDown(ref.read(clockProvider)());

    final Widget cover;
    if (_lifecycleCover) {
      cover = const _NeutralCover();
    } else if (lock.phase == LockPhase.loadFailed) {
      cover = _LoadFailedScreen(
        onRetry: ref.read(appLockStateProvider.notifier).retryLoad,
      );
    } else if (lock.locked) {
      cover = _LockScreen(
        state: lock,
        cooling: cooling,
        onFirstShown: _maybePrompt,
      );
    } else {
      cover = const _NeutralCover();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Always mounted (warm when the lock resolves), hidden whenever
        // locked, resolving or covered.
        Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: !hidden,
            child: ExcludeSemantics(
              excluding: hidden,
              child: ExcludeFocus(
                excluding: hidden,
                child: KeyedSubtree(key: _contentKey, child: widget.child),
              ),
            ),
          ),
        ),
        if (hidden) Positioned.fill(child: cover),
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
        _Notice(
          icon: Icons.timer_outlined,
          text: l10n.lockCoolDown(remaining),
          // Static message for assistive tech; the ticking number is not
          // announced every second.
          semanticsLabel: l10n.lockCoolDownPaused,
        ),
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
  const _Notice({required this.icon, required this.text, this.semanticsLabel});

  final IconData icon;
  final String text;

  /// A fixed spoken label; the visible [text] is then excluded from semantics
  /// (for text that changes every second).
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, color: roles.warning, size: 20)),
        const SizedBox(width: ConsolarrSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
    return Semantics(
      liveRegion: true,
      container: true,
      label: semanticsLabel,
      child: semanticsLabel == null ? row : ExcludeSemantics(child: row),
    );
  }
}

/// Shown when the stored settings could not be read: the app stays closed and
/// offers a retry. Never shows content.
class _LoadFailedScreen extends StatelessWidget {
  const _LoadFailedScreen({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final touch = TouchTargets.of(context).minimum;
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
                label: l10n.lockLoadFailedTitle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.lock_outline,
                        size: 48,
                        color: context.roles.warning,
                      ),
                    ),
                    const SizedBox(height: ConsolarrSpacing.lg),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.lockLoadFailedTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: ConsolarrSpacing.sm),
                    Text(
                      l10n.lockLoadFailedBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: ConsolarrSpacing.xl),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: Size(0, touch),
                      ),
                      onPressed: onRetry,
                      child: Text(l10n.lockLoadFailedRetry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
