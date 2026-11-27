// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/presentation/connection_test_panel.dart';
import 'package:consolarr/features/servers/presentation/reveal_tracker.dart';
import 'package:consolarr/features/servers/presentation/screen_tracking.dart';
import 'package:consolarr/features/servers/presentation/server_form_controller.dart';
import 'package:consolarr/features/servers/presentation/server_form_fields.dart';
import 'package:consolarr/features/servers/presentation/servers_routes.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

enum _Step { welcome, choose, details, test }

/// First-run guided setup (SRV-12): welcome, choose a service, enter details,
/// test and finish. Skipping is always possible; every step has its own error
/// state.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({this.onFinished, this.onSkip, super.key});

  /// Called with the kind of the server that was added. Defaults to
  /// navigating to that service's first route.
  final ValueChanged<ServiceKind>? onFinished;

  /// Called when the user skips setup. Defaults to opening the servers list.
  final VoidCallback? onSkip;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final ServerFormController _form = ServerFormController();
  late final RevealTracker _reveal;
  _Step _step = _Step.welcome;
  bool _tested = false;
  bool _saving = false;
  AppError? _saveError;

  @override
  void initState() {
    super.initState();
    _reveal = RevealTracker(ref.read(secureScreenProvider));
  }

  @override
  void dispose() {
    _reveal.dispose();
    _form.dispose();
    super.dispose();
  }

  void _skip() {
    final cb = widget.onSkip;
    if (cb != null) {
      cb();
    } else {
      context.go(ServersRoutes.list);
    }
  }

  void _goTo(_Step step) => setState(() {
    _step = step;
    _saveError = null;
  });

  void _next() {
    if (_step == _Step.details) {
      _form.showAllErrors();
      if (!_form.validate().isValid) return;
    }
    _goTo(_Step.values[_step.index + 1]);
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final result = await ref
        .read(serverRepositoryProvider)
        .save(_form.toDraft());
    if (!mounted) return;
    switch (result) {
      case Ok():
        setState(() => _saving = false);
        final cb = widget.onFinished;
        if (cb != null) {
          cb(_form.kind);
        } else {
          context.go(ServersRoutes.afterOnboarding(_form.kind));
        }
      case Err(:final error):
        setState(() {
          _saving = false;
          _saveError = error;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final body = switch (_step) {
      _Step.welcome => _welcome(l10n, theme),
      _Step.choose => _choose(l10n, theme),
      _Step.details => _details(l10n, theme),
      _Step.test => _test(l10n, theme),
    };
    return ScreenViewTracker(
      screen: ScreenName.onboarding,
      child: PopScope(
        canPop: _step == _Step.welcome,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goTo(_Step.values[_step.index - 1]);
        },
        child: Scaffold(
          appBar: AppBar(
            actions: [
              TextButton(onPressed: _skip, child: Text(l10n.onboardingSkip)),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.onboardingStepOf(_step.index + 1, _Step.values.length),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: ConsolarrSpacing.sm),
                  ...body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(text, style: theme.textTheme.headlineSmall),
    ),
  );

  List<Widget> _welcome(AppLocalizations l10n, ThemeData theme) => [
    const SizedBox(height: ConsolarrSpacing.xl),
    const ExcludeSemantics(child: Icon(Icons.dns_outlined, size: 72)),
    const SizedBox(height: ConsolarrSpacing.lg),
    _heading(l10n.onboardingWelcomeTitle, theme),
    Text(l10n.onboardingWelcomeBody, style: theme.textTheme.bodyMedium),
    const SizedBox(height: ConsolarrSpacing.xl),
    FilledButton(
      onPressed: () => _goTo(_Step.choose),
      child: Text(l10n.onboardingStart),
    ),
  ];

  List<Widget> _choose(AppLocalizations l10n, ThemeData theme) => [
    _heading(l10n.onboardingChooseTitle, theme),
    Text(l10n.onboardingChooseBody, style: theme.textTheme.bodyMedium),
    const SizedBox(height: ConsolarrSpacing.lg),
    for (final kind in supportedServiceKinds)
      Padding(
        padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
        child: Material(
          color: context.roles.card,
          borderRadius: ConsolarrRadii.card,
          child: ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: ConsolarrRadii.card,
            ),
            minTileHeight: ConsolarrSpacing.minTapTarget,
            leading: ExcludeSemantics(child: Icon(serviceKindIcon(kind))),
            title: Text(serviceKindLabel(l10n, kind)),
            subtitle: Text(serviceKindDescription(l10n, kind)),
            trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
            onTap: () {
              _form.setKind(kind);
              _goTo(_Step.details);
            },
          ),
        ),
      ),
    _backButton(l10n),
  ];

  List<Widget> _details(AppLocalizations l10n, ThemeData theme) => [
    _heading(l10n.onboardingDetailsTitle, theme),
    ServerFormFields(
      controller: _form,
      showKindPicker: false,
      onRevealChanged: _reveal.update,
    ),
    const SizedBox(height: ConsolarrSpacing.xl),
    FilledButton(onPressed: _next, child: Text(l10n.onboardingNext)),
    _backButton(l10n),
  ];

  List<Widget> _test(AppLocalizations l10n, ThemeData theme) {
    final error = _saveError;
    final message = error == null ? null : connectionErrorMessage(l10n, error);
    return [
      _heading(l10n.onboardingTestTitle, theme),
      ConnectionTestPanel(
        controller: _form,
        onResult: (ok) {
          if (ok != _tested) setState(() => _tested = ok);
        },
      ),
      if (!_tested)
        Padding(
          padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
          child: Text(
            l10n.onboardingTestFirst,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(
                  label: l10n.serverSaveFailedHeadline,
                  icon: Icons.error_outline,
                  tone: StatusTone.error,
                ),
                Text(message.message),
                Text(message.hint, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      const SizedBox(height: ConsolarrSpacing.xl),
      FilledButton(
        onPressed: _tested && !_saving ? _finish : null,
        child: Text(l10n.onboardingFinish),
      ),
      _backButton(l10n),
    ];
  }

  Widget _backButton(AppLocalizations l10n) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: () => _goTo(_Step.values[_step.index - 1]),
      child: Text(l10n.onboardingBack),
    ),
  );
}
