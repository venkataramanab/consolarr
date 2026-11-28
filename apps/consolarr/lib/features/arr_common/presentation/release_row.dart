// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Download state of one release row.
enum ReleaseGrabState {
  idle,
  grabbing,
  grabbed,

  /// The server refused or failed: nothing was sent.
  failed,

  /// The request may have reached the server; check the queue before retrying.
  maybeSent,
}

/// Localized strings of [ReleaseRow] (passed in; no l10n here).
class ReleaseRowLabels {
  const ReleaseRowLabels({
    required this.download,
    required this.downloadAgain,
    required this.grabbing,
    required this.grabbed,
    required this.failed,
    required this.maybeSent,
    required this.rejectedBadge,
    required this.expand,
    required this.collapse,
    required this.rejectionsHeading,
    required this.customFormatsHeading,
    required this.languagesHeading,
    required this.partSeparator,
  });

  final String download;
  final String downloadAgain;
  final String grabbing;
  final String grabbed;
  final String failed;
  final String maybeSent;
  final String rejectedBadge;
  final String expand;
  final String collapse;
  final String rejectionsHeading;
  final String customFormatsHeading;
  final String languagesHeading;

  /// Between the facts of one row (localized: `sharedPartSeparator`).
  final String partSeparator;
}

/// What a release row shows. All text is plain text from the server or
/// already localized; nothing is interpreted as markup or as a link.
class ReleaseRowData {
  const ReleaseRowData({
    required this.title,
    required this.facts,
    required this.semanticsLabel,
    this.isRejected = false,
    this.rejections = const [],
    this.customFormats = const [],
    this.languages = const [],
    this.grab = ReleaseGrabState.idle,
  });

  final String title;

  /// Quality, size, age, seeders, indexer ... already formatted.
  final List<String> facts;

  /// Name, facts, rejection and download state, for screen readers.
  final String semanticsLabel;
  final bool isRejected;
  final List<String> rejections;
  final List<String> customFormats;
  final List<String> languages;
  final ReleaseGrabState grab;

  bool get hasDetails =>
      rejections.isNotEmpty || customFormats.isNotEmpty || languages.isNotEmpty;
}

/// One release of an interactive search (SON-18): title, facts, a rejected
/// badge, an expandable details panel (rejection reasons, custom formats,
/// languages) and the download button with its states. Kind-agnostic.
class ReleaseRow extends StatefulWidget {
  const ReleaseRow({
    required this.data,
    required this.labels,
    required this.onDownload,
    super.key,
  });

  final ReleaseRowData data;
  final ReleaseRowLabels labels;

  /// Called for the download button (and "download again").
  final VoidCallback onDownload;

  @override
  State<ReleaseRow> createState() => _ReleaseRowState();
}

class _ReleaseRowState extends State<ReleaseRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final labels = widget.labels;
    final theme = Theme.of(context);
    final roles = context.roles;
    return Semantics(
      container: true,
      label: data.semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: roles.raised,
          borderRadius: ConsolarrRadii.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(ConsolarrSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: ConsolarrSpacing.sm,
                        ),
                        child: Text(
                          data.title,
                          maxLines: _expanded ? null : 3,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                  if (data.hasDetails)
                    IconButton(
                      tooltip: _expanded ? labels.collapse : labels.expand,
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                ],
              ),
              const SizedBox(height: ConsolarrSpacing.xs),
              ExcludeSemantics(
                child: Text(
                  data.facts.join(labels.partSeparator),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: roles.textSecondary,
                  ),
                ),
              ),
              if (data.isRejected) ...[
                const SizedBox(height: ConsolarrSpacing.sm),
                StatusChip(
                  label: labels.rejectedBadge,
                  icon: Icons.block,
                  tone: StatusTone.warning,
                ),
              ],
              if (_expanded && data.hasDetails) ...[
                const SizedBox(height: ConsolarrSpacing.sm),
                _Details(data: data, labels: labels),
              ],
              const SizedBox(height: ConsolarrSpacing.sm),
              _DownloadControl(
                grab: data.grab,
                labels: labels,
                onDownload: widget.onDownload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.data, required this.labels});

  final ReleaseRowData data;
  final ReleaseRowLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String heading, List<String> lines) => Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(heading, style: theme.textTheme.labelLarge),
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.xxs),
              child: Text(
                context.l10n.sharedBulletLine(line),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.rejections.isNotEmpty)
          section(labels.rejectionsHeading, data.rejections),
        if (data.customFormats.isNotEmpty)
          section(labels.customFormatsHeading, data.customFormats),
        if (data.languages.isNotEmpty)
          section(labels.languagesHeading, data.languages),
      ],
    );
  }
}

class _DownloadControl extends StatelessWidget {
  const _DownloadControl({
    required this.grab,
    required this.labels,
    required this.onDownload,
  });

  final ReleaseGrabState grab;
  final ReleaseRowLabels labels;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    switch (grab) {
      case ReleaseGrabState.idle:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: Text(labels.download),
          ),
        );
      case ReleaseGrabState.grabbing:
        return Semantics(
          liveRegion: true,
          label: labels.grabbing,
          child: ExcludeSemantics(
            child: Row(
              children: [
                const BusyIndicator(semanticLabel: null),
                const SizedBox(width: ConsolarrSpacing.sm),
                Flexible(child: Text(labels.grabbing)),
              ],
            ),
          ),
        );
      case ReleaseGrabState.grabbed:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            liveRegion: true,
            child: StatusChip(
              label: labels.grabbed,
              icon: Icons.download_done,
              tone: StatusTone.success,
            ),
          ),
        );
      case ReleaseGrabState.failed:
      case ReleaseGrabState.maybeSent:
        final unsure = grab == ReleaseGrabState.maybeSent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: StatusChip(
                label: unsure ? labels.maybeSent : labels.failed,
                icon: unsure ? Icons.help_outline : Icons.error_outline,
                tone: StatusTone.warning,
              ),
            ),
            const SizedBox(height: ConsolarrSpacing.xs),
            TextButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.refresh),
              label: Text(labels.downloadAgain),
            ),
          ],
        );
    }
  }
}
