// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/source_link.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/application/services_check.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Full preview of the redacted diagnostics bundle (SET-04). The user reads
/// every section, then either shares the file or opens a pre-filled GitHub
/// issue in the browser. Neither happens without a tap, and the shared bytes
/// are exactly the previewed text.
class DiagnosticsPreviewScreen extends ConsumerStatefulWidget {
  const DiagnosticsPreviewScreen({super.key});

  @override
  ConsumerState<DiagnosticsPreviewScreen> createState() =>
      _DiagnosticsPreviewScreenState();
}

class _DiagnosticsPreviewScreenState
    extends ConsumerState<DiagnosticsPreviewScreen> {
  String? _message;

  Future<void> _share(DiagnosticsBundle bundle) async {
    final l10n = context.l10n;
    final actions = ref.read(externalActionsProvider);
    try {
      await actions.shareText(
        text: bundle.text,
        subject: l10n.diagIssueTitle,
        truncationNote: l10n.diagShareTruncationNote,
      );
      await ref
          .read(eventTrackerProvider)
          .track(
            const DiagnosticsSharedEvent(channel: DiagnosticsChannelParam.file),
          );
      if (mounted) setState(() => _message = null);
    } on Object {
      if (mounted) setState(() => _message = l10n.diagShareFailed);
    }
  }

  Future<void> _openGithub(DiagnosticsBundle bundle) async {
    final l10n = context.l10n;
    final uri = GithubIssueLink.build(
      repository: sourceRepositoryUri,
      title: l10n.diagIssueTitle,
      // A short summary and a request to attach the shared file: the full
      // bundle never goes into an address.
      body: '${bundle.summaryText}\n\n${l10n.diagAttachNote}',
      truncationNote: l10n.diagTruncationNote,
    );
    final opened = await ref.read(externalActionsProvider).openHttps(uri);
    if (opened) {
      await ref
          .read(eventTrackerProvider)
          .track(
            const DiagnosticsSharedEvent(
              channel: DiagnosticsChannelParam.github,
            ),
          );
    }
    if (mounted) setState(() => _message = opened ? null : l10n.diagOpenFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final bundle = ref.watch(diagnosticsBundleProvider);
    final touch = TouchTargets.of(context).minimum;

    // Loading, then error, then the value.
    final List<Widget> children;
    // A rebuild with a value (the services check changing a line) keeps the
    // sections on screen instead of flashing the skeleton.
    if (bundle.isLoading && !bundle.hasValue) {
      children = const [
        SkeletonBox(height: 24),
        SizedBox(height: ConsolarrSpacing.sm),
        SkeletonBox(height: 160),
      ];
    } else if (bundle.hasError && !bundle.hasValue) {
      children = [
        ErrorState(
          headline: l10n.diagLoadFailedTitle,
          message: l10n.diagLoadFailed,
          hint: l10n.diagLoadFailedHint,
          retryLabel: l10n.settingsRetry,
          onRetry: () => ref.invalidate(diagnosticsBundleProvider),
        ),
      ];
    } else {
      final b = bundle.requireValue;
      children = [
        Text(l10n.diagPreviewIntro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: ConsolarrSpacing.md),
        const _ServicesCheck(),
        const SizedBox(height: ConsolarrSpacing.md),
        for (final section in b.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    section.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: ConsolarrSpacing.xs),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: roles.card,
                    borderRadius: BorderRadius.circular(ConsolarrRadii.sm),
                    border: Border.all(color: roles.track),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(ConsolarrSpacing.md),
                    // Left to right: the bundle is English, read by
                    // maintainers, and must be shown exactly as shared.
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          section.body,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: roles.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (b.logIsEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
            child: Text(
              l10n.diagPreviewEmptyLog,
              style: theme.textTheme.bodySmall?.copyWith(
                color: roles.textPrimary,
              ),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.error_outline, color: roles.error),
                  ),
                  const SizedBox(width: ConsolarrSpacing.sm),
                  Expanded(
                    child: Text(_message!, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
          onPressed: () => _share(b),
          icon: const Icon(Icons.ios_share),
          label: Text(l10n.diagShareFile),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: Size(0, touch)),
          onPressed: () => _openGithub(b),
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.diagOpenGithub),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        Text(
          l10n.diagGithubNote,
          style: theme.textTheme.bodySmall?.copyWith(color: roles.textPrimary),
        ),
      ];
    }

    return SettingsPage(
      title: l10n.diagPreviewTitle,
      screen: ScreenName.settingsDiagnostics,
      children: children,
    );
  }
}

/// The user-initiated "Check services" control: a button with a running state
/// and a status line that says what the check found, in words. The status is
/// a live region whose text changes only when the check starts, finishes or
/// fails, so nothing is announced twice.
class _ServicesCheck extends ConsumerWidget {
  const _ServicesCheck();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final touch = TouchTargets.of(context).minimum;
    final roles = context.roles;
    final check = ref.watch(servicesCheckProvider);
    final servers = ref.watch(serversProvider).value ?? const <ServerEntry>[];
    final checking = check.phase == ServicesCheckPhase.checking;

    final String status;
    switch (check.phase) {
      case ServicesCheckPhase.notChecked:
        status = l10n.diagServicesNotChecked;
      case ServicesCheckPhase.checking:
        status = l10n.diagServicesChecking;
      case ServicesCheckPhase.failed:
        status = l10n.diagServicesFailed;
      case ServicesCheckPhase.done:
        final results = check.results.values;
        if (servers.isEmpty && results.isEmpty) {
          status = l10n.diagServicesNone;
        } else if (results.length < servers.length) {
          status = l10n.diagServicesPartial;
        } else {
          status = l10n.diagServicesDone(
            results.length,
            results.where((r) => r.health != ServerHealth.healthy).length,
          );
        }
    }

    final label = checking
        ? l10n.diagServicesChecking
        : check.phase == ServicesCheckPhase.notChecked
        ? l10n.diagServicesCheck
        : l10n.diagServicesCheckAgain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: Size(0, touch)),
          onPressed: checking
              ? null
              : () => ref.read(servicesCheckProvider.notifier).check(),
          icon: checking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.health_and_safety_outlined),
          label: Text(label),
        ),
        const SizedBox(height: ConsolarrSpacing.xs),
        Semantics(
          liveRegion: true,
          child: Text(status, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}
