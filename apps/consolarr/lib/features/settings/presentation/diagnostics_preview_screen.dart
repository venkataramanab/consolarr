// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:consolarr/features/about/source_link.dart';
import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
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
      await actions.shareFile(
        fileName: 'consolarr-diagnostics.txt',
        bytes: Uint8List.fromList(bundle.bytes),
        mimeType: 'text/plain',
        subject: l10n.diagIssueTitle,
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
      body: bundle.text,
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
    if (bundle.isLoading) {
      children = const [
        SkeletonBox(height: 24),
        SizedBox(height: ConsolarrSpacing.sm),
        SkeletonBox(height: 160),
      ];
    } else if (bundle.hasError) {
      children = [
        ErrorState(
          headline: l10n.diagLoadFailed,
          message: l10n.diagLoadFailed,
          hint: l10n.diagLoadFailed,
          retryLabel: l10n.diagPreviewTitle,
          onRetry: () => ref.invalidate(diagnosticsBundleProvider),
        ),
      ];
    } else {
      final b = bundle.requireValue;
      children = [
        Text(l10n.diagPreviewIntro, style: theme.textTheme.bodyLarge),
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
        Text(l10n.diagGithubNote, style: theme.textTheme.bodySmall),
      ];
    }

    return SettingsPage(
      title: l10n.diagPreviewTitle,
      screen: ScreenName.settingsDiagnostics,
      children: children,
    );
  }
}
