// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/connection_check.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

String checkStepName(AppLocalizations l10n, CheckStep s) => switch (s) {
  CheckStep.dns => l10n.checkStepDns,
  CheckStep.connect => l10n.checkStepConnect,
  CheckStep.tls => l10n.checkStepTls,
  CheckStep.auth => l10n.checkStepAuth,
  CheckStep.version => l10n.checkStepVersion,
};

String checkStateName(AppLocalizations l10n, CheckStepState s) => switch (s) {
  CheckStepState.pending => l10n.checkStatePending,
  CheckStepState.running => l10n.checkStateRunning,
  CheckStepState.pass => l10n.checkStatePass,
  CheckStepState.fail => l10n.checkStateFail,
  CheckStepState.skipped => l10n.checkStateSkipped,
  CheckStepState.notNeeded => l10n.checkStateNotNeeded,
};

/// Step-by-step connection diagnostics for one server (SET-05): name
/// resolution, connect, TLS, sign-in and API version, each with a plain
/// pass/fail and, on failure, the cause and a fix hint.
class ConnectionCheckScreen extends ConsumerWidget {
  const ConnectionCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final servers = ref.watch(uiServersProvider);
    final check = ref.watch(connectionCheckProvider);
    final touch = TouchTargets.of(context).minimum;

    final List<Widget> children;
    if (servers.isLoading) {
      children = const [
        SkeletonBox(height: 56),
        SizedBox(height: 8),
        SkeletonBox(height: 200),
      ];
    } else if (servers.hasError) {
      children = [
        ErrorState(
          headline: l10n.checkLoadFailedTitle,
          message: l10n.checkLoadFailed,
          hint: l10n.checkLoadFailedHint,
          retryLabel: l10n.settingsRetry,
          onRetry: () => ref.invalidate(uiServersProvider),
        ),
      ];
    } else {
      final list = servers.requireValue;
      if (list.isEmpty) {
        children = [
          EmptyState(icon: Icons.dns_outlined, headline: l10n.checkNoServers),
        ];
      } else {
        final selected = _find(list, check.serverId) ?? list.first;
        children = [
          SettingsSection(
            title: l10n.checkChooseServer,
            children: [
              ChoiceSheetRow<String?>(
                title: l10n.checkChooseServer,
                icon: Icons.dns_outlined,
                closeLabel: l10n.settingsClose,
                enabled: !check.running,
                options: [
                  for (final s in list)
                    ChoiceOption(value: s.profile.id, label: s.profile.name),
                ],
                selected: selected.profile.id,
                onSelected: (id) {
                  if (id != null) {
                    ref.read(connectionCheckProvider.notifier).select(id);
                  }
                },
              ),
            ],
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
            onPressed: check.running
                ? null
                : () => ref
                      .read(connectionCheckProvider.notifier)
                      .run(selected.profile.id),
            icon: const Icon(Icons.play_arrow),
            label: Text(
              check.result?.finished ?? false
                  ? l10n.checkRunAgain
                  : l10n.checkRun,
            ),
          ),
          const SizedBox(height: ConsolarrSpacing.lg),
          if (check.failed)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.checkRunFailed,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          if (check.result != null)
            _Steps(result: check.result!, kind: selected.profile.kind),
        ];
      }
    }

    return SettingsPage(
      title: l10n.checkTitle,
      screen: ScreenName.settingsDiagnostics,
      children: children,
    );
  }

  ServerEntry? _find(List<ServerEntry> list, String? id) {
    for (final s in list) {
      if (s.profile.id == id) return s;
    }
    return null;
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.result, required this.kind});

  final ConnectionCheckResult result;
  final ServiceKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final failed = result.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: l10n.checkTitle,
          children: [
            for (final s in result.steps) _StepRow(result: s, kind: kind),
          ],
        ),
        if (result.allPassed) ...[
          Semantics(
            liveRegion: true,
            child: Text(l10n.checkAllPassed, style: theme.textTheme.bodyLarge),
          ),
          if (result.version != null)
            Text(
              l10n.checkServerVersion(result.version!),
              style: theme.textTheme.bodyMedium,
            ),
        ] else if (failed != null)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.checkSummaryFailed(checkStepName(l10n, failed.step)),
              style: theme.textTheme.bodyLarge,
            ),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.result, required this.kind});

  final StepResult result;
  final ServiceKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final state = result.state;
    final (icon, color) = switch (state) {
      CheckStepState.pass => (Icons.check_circle_outline, roles.success),
      CheckStepState.fail => (Icons.error_outline, roles.error),
      CheckStepState.running => (Icons.sync, roles.accent),
      CheckStepState.skipped => (
        Icons.remove_circle_outline,
        roles.textTertiary,
      ),
      CheckStepState.notNeeded => (
        Icons.check_circle_outline,
        roles.textTertiary,
      ),
      CheckStepState.pending => (
        Icons.radio_button_unchecked,
        roles.textTertiary,
      ),
    };
    String? message;
    String? hint;
    if (state == CheckStepState.fail) {
      final error = result.error;
      if (error != null) {
        final m = connectionErrorMessage(l10n, error, kind: kind);
        message = m.message;
        hint = m.hint;
      } else if (result.localFailure == CheckStep.dns) {
        message = l10n.checkDnsFailedMessage;
        hint = l10n.checkDnsFailedHint;
      } else {
        message = l10n.checkConnectFailedMessage;
        hint = l10n.checkConnectFailedHint;
      }
    }
    final name = checkStepName(l10n, result.step);
    final stateName = checkStateName(l10n, state);
    return Semantics(
      container: true,
      label: [name, stateName, ?message, ?hint].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ConsolarrSpacing.lg,
          vertical: ConsolarrSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: ConsolarrSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.bodyLarge),
                  // The state is always words, never colour alone.
                  Text(stateName, style: theme.textTheme.bodyMedium),
                  if (message != null) ...[
                    const SizedBox(height: ConsolarrSpacing.xs),
                    Text(message, style: theme.textTheme.bodyMedium),
                  ],
                  if (hint != null)
                    Text(hint, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
