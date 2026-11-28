// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:consolarr/features/settings/settings_paths.dart';
import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

String logLevelLabel(AppLocalizations l10n, LogLevel level) => switch (level) {
  LogLevel.debug => l10n.diagLevelDebug,
  LogLevel.info => l10n.diagLevelInfo,
  LogLevel.warning => l10n.diagLevelWarning,
  LogLevel.error => l10n.diagLevelError,
};

IconData _levelIcon(LogLevel level) => switch (level) {
  LogLevel.debug => Icons.bug_report_outlined,
  LogLevel.info => Icons.info_outline,
  LogLevel.warning => Icons.warning_amber_outlined,
  LogLevel.error => Icons.error_outline,
};

/// Diagnostics (SET-04): the opt-in in-app log (off / empty / capturing),
/// level selector and filter, clear, and the entry to the share preview and
/// the connection check (SET-05).
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  /// `null` shows every level.
  LogLevel? _filter;

  Future<void> _confirmClear() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.diagClearConfirmTitle),
        content: Text(l10n.diagClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.diagClearConfirm),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      ref.read(diagnosticsLogViewProvider.notifier).clear();
      _announce(l10n.diagAnnounceCleared);
    }
  }

  /// Said once on a change of state (on, off, cleared); the running count is
  /// not a live region.
  void _announce(String message) {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  Future<void> _setEnabled(bool value) async {
    final l10n = context.l10n;
    final stored = await ref
        .read(settingsProvider.notifier)
        .setDiagnosticsEnabled(value);
    if (stored) _announce(value ? l10n.diagAnnounceOn : l10n.diagAnnounceOff);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final view = ref.watch(diagnosticsLogViewProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Newest first. The rows are read lazily from the buffer; only the
    // indexes of matching lines are kept when a level filter is on.
    final matches = _filter == null
        ? null
        : [
            for (var i = view.length - 1; i >= 0; i--)
              if (view.entryAt(i).level == _filter) i,
          ];
    final shownCount = matches?.length ?? view.length;
    LogEntry entryFor(int row) =>
        view.entryAt(matches == null ? view.length - 1 - row : matches[row]);

    Widget status;
    if (!view.enabled) {
      status = EmptyState(
        icon: Icons.history_toggle_off,
        headline: l10n.diagOffTitle,
        message: l10n.diagOffBody,
      );
    } else if (view.isEmpty) {
      status = EmptyState(
        icon: Icons.hourglass_empty,
        headline: l10n.diagEmptyTitle,
        message: l10n.diagEmptyBody,
      );
    } else if (shownCount == 0) {
      status = EmptyState(
        icon: Icons.filter_alt_off_outlined,
        headline: l10n.diagFilterEmptyTitle,
      );
    } else {
      status = const SizedBox.shrink();
    }

    return ScreenTracker(
      screen: ScreenName.settingsDiagnostics,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.diagTitle)),
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ConsolarrSpacing.gutter,
                  ConsolarrSpacing.md,
                  ConsolarrSpacing.gutter,
                  0,
                ),
                sliver: SliverList.list(
                  children: [
                    SettingsSection(
                      title: l10n.diagLogSection,
                      footer: l10n.diagLogSwitchHint,
                      children: [
                        SwitchRow(
                          title: l10n.diagLogSwitch,
                          icon: Icons.receipt_long_outlined,
                          value: settings.diagnosticsEnabled,
                          onChanged: _setEnabled,
                        ),
                        ChoiceSheetRow<LogLevel>(
                          title: l10n.diagLevelTitle,
                          icon: Icons.tune,
                          closeLabel: l10n.settingsClose,
                          options: [
                            for (final l in LogLevel.values)
                              ChoiceOption(
                                value: l,
                                label: logLevelLabel(l10n, l),
                              ),
                          ],
                          selected: settings.diagnosticsLevel,
                          onSelected: notifier.setDiagnosticsLevel,
                        ),
                      ],
                    ),
                    SettingsSection(
                      title: l10n.settingsSectionDiagnostics,
                      children: [
                        SettingsRow(
                          title: l10n.diagCheckRow,
                          subtitle: l10n.diagCheckRowSubtitle,
                          icon: Icons.network_check,
                          onTap: () =>
                              context.push(SettingsPaths.connectionCheck),
                        ),
                        SettingsRow(
                          title: l10n.diagShareButton,
                          icon: Icons.ios_share,
                          onTap: () =>
                              context.push(SettingsPaths.diagnosticsPreview),
                        ),
                      ],
                    ),
                    if (view.enabled) ...[
                      Row(
                        children: [
                          Expanded(
                            // Not a live region: the count changes with every
                            // log line. State changes are announced instead.
                            child: Semantics(
                              container: true,
                              child: Row(
                                children: [
                                  const ExcludeSemantics(
                                    child: Icon(
                                      Icons.fiber_manual_record,
                                      size: 12,
                                    ),
                                  ),
                                  const SizedBox(width: ConsolarrSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      l10n.diagCapturing(view.length),
                                      style: theme.textTheme.labelLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: Size.square(
                                TouchTargets.of(context).minimum,
                              ),
                            ),
                            onPressed: view.isEmpty ? null : _confirmClear,
                            child: Text(l10n.diagClear),
                          ),
                        ],
                      ),
                      const SizedBox(height: ConsolarrSpacing.sm),
                      ChoiceSheetRow<LogLevel?>(
                        title: l10n.diagFilterLabel,
                        icon: Icons.filter_list,
                        closeLabel: l10n.settingsClose,
                        options: [
                          ChoiceOption(value: null, label: l10n.diagFilterAll),
                          for (final l in LogLevel.values)
                            ChoiceOption(
                              value: l,
                              label: logLevelLabel(l10n, l),
                            ),
                        ],
                        selected: _filter,
                        onSelected: (v) => setState(() => _filter = v),
                      ),
                      const SizedBox(height: ConsolarrSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(Icons.shield_outlined, size: 18),
                          ),
                          const SizedBox(width: ConsolarrSpacing.sm),
                          Expanded(
                            child: Text(
                              l10n.diagRedactionNotice,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ConsolarrSpacing.md),
                    ],
                  ],
                ),
              ),
              if (!view.enabled || view.isEmpty || shownCount == 0)
                SliverToBoxAdapter(child: SizedBox(height: 260, child: status))
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    ConsolarrSpacing.gutter,
                    0,
                    ConsolarrSpacing.gutter,
                    ConsolarrSpacing.lg + bottom,
                  ),
                  sliver: SliverList.builder(
                    itemCount: shownCount,
                    itemBuilder: (context, i) {
                      final e = entryFor(i);
                      final time = MaterialLocalizations.of(context)
                          .formatTimeOfDay(
                            TimeOfDay.fromDateTime(e.time.toLocal()),
                            alwaysUse24HourFormat: true,
                          );
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: ConsolarrSpacing.sm,
                        ),
                        child: Semantics(
                          container: true,
                          label: joinList(l10n, [
                            logLevelLabel(l10n, e.level),
                            time,
                            e.message,
                          ]),
                          excludeSemantics: true,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _levelIcon(e.level),
                                size: 18,
                                color: roles.textSecondary,
                              ),
                              const SizedBox(width: ConsolarrSpacing.sm),
                              Expanded(
                                child: Text(
                                  '$time  ${e.message}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: roles.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
