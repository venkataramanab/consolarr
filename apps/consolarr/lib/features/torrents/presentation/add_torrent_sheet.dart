// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:consolarr/features/torrents/application/torrent_link.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/error_text.dart';
import 'package:consolarr/features/torrents/presentation/screen_view.dart';
import 'package:consolarr/features/torrents/presentation/stand_ins/glass_sheet.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Opens the add sheet (TOR-04, TOR-05).
Future<void> showAddTorrentSheet(BuildContext context) {
  final l10n = context.l10n;
  return showGlassSheet<void>(
    context: context,
    title: l10n.torAddTitle,
    closeLabel: l10n.torDetailClose,
    detents: GlassSheetDetents.full,
    builder: (_) => const AddTorrentSheet(),
  );
}

/// The add form: a link (paste or type) with the parsed name to confirm, or
/// `.torrent` files from the system picker, plus options the client supports.
class AddTorrentSheet extends ConsumerStatefulWidget {
  const AddTorrentSheet({super.key});

  @override
  ConsumerState<AddTorrentSheet> createState() => _AddTorrentSheetState();
}

class _AddTorrentSheetState extends ConsumerState<AddTorrentSheet> {
  final _link = TextEditingController();
  final _savePath = TextEditingController();
  final _category = TextEditingController();
  final _tags = TextEditingController();
  bool _paused = false;

  @override
  void dispose() {
    _link.dispose();
    _savePath.dispose();
    _category.dispose();
    _tags.dispose();
    super.dispose();
  }

  AddTorrentOptions _options(TorrentCapabilities caps) {
    String? clean(String s) => s.trim().isEmpty ? null : s.trim();
    return AddTorrentOptions(
      savePath: clean(_savePath.text),
      category: caps.hasLabel ? clean(_category.text) : null,
      tags: caps.tags
          ? [
              for (final t in _tags.text.split(','))
                if (t.trim().isNotEmpty) t.trim(),
            ]
          : const [],
      paused: _paused,
    );
  }

  Future<void> _paste() async {
    // Only on this explicit tap: the clipboard is never read otherwise.
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(context.l10n.torAddPasteEmpty)));
      return;
    }
    setState(() => _link.text = text.trim());
  }

  Future<void> _send(TorrentCapabilities caps) async {
    final ok = await ref
        .read(addTorrentProvider.notifier)
        .addLink(_link.text, _options(caps));
    // Never keep a link (it may carry a tracker passkey) after it was sent.
    if (ok && mounted) setState(_link.clear);
  }

  Future<void> _pickFiles(TorrentCapabilities caps) async {
    final files = await ref.read(torrentFilePickerProvider)();
    if (!mounted || files.isEmpty) return;
    await ref.read(addTorrentProvider.notifier).addFiles(files, _options(caps));
  }

  String? _problemText(AppLocalizations l10n, ParsedLink parsed) {
    if (parsed is! InvalidLink || parsed.problem == LinkProblem.empty) {
      return null;
    }
    return switch (parsed.problem) {
      LinkProblem.scheme => l10n.torAddInvalidScheme,
      LinkProblem.hash => l10n.torAddInvalidHash,
      LinkProblem.userinfo => l10n.torAddInvalidUserinfo,
      _ => l10n.torAddInvalidUrl,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final add = ref.watch(addTorrentProvider);
    final caps = ref.watch(torrentCapabilitiesProvider);
    final kind = ref.watch(torrentClientProvider).value?.kind;
    final parsed = parseTorrentLink(_link.text);
    final adding = add is AddAdding;
    final canSend = !adding && (parsed is MagnetLink || parsed is UrlLink);
    final theme = Theme.of(context);

    return TorrentScreenView(
      screen: ScreenName.torrentAdd,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ConsolarrSpacing.gutter,
          ConsolarrSpacing.sm,
          ConsolarrSpacing.gutter,
          ConsolarrSpacing.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _link,
              enabled: !adding,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              // The link may hold a tracker passkey: no learning, no history.
              enableIMEPersonalizedLearning: false,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.torAddSourceLabel,
                hintText: l10n.torAddSourceHint,
                errorText: _problemText(l10n, parsed),
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: l10n.torAddPaste,
                  icon: const Icon(Icons.content_paste),
                  onPressed: adding ? null : _paste,
                ),
              ),
            ),
            if (parsed is MagnetLink || parsed is UrlLink) ...[
              const SizedBox(height: ConsolarrSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(switch (parsed) {
                  MagnetLink(:final displayName) => l10n.torAddConfirmName(
                    displayName,
                  ),
                  UrlLink(:final host) => l10n.torAddConfirmUrl(host),
                  _ => '',
                }, style: theme.textTheme.bodyLarge),
              ),
            ],
            const SizedBox(height: ConsolarrSpacing.md),
            _options_(l10n, caps, kind, adding),
            const SizedBox(height: ConsolarrSpacing.md),
            FilledButton(
              onPressed: canSend ? () => _send(caps) : null,
              child: Text(adding ? l10n.torAddAdding : l10n.torAddButton),
            ),
            const SizedBox(height: ConsolarrSpacing.sm),
            Center(
              child: Text(l10n.torAddOr, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: ConsolarrSpacing.sm),
            OutlinedButton.icon(
              onPressed: adding ? null : () => _pickFiles(caps),
              icon: const Icon(Icons.upload_file),
              label: Text(l10n.torAddPickFiles),
            ),
            const SizedBox(height: ConsolarrSpacing.md),
            _result(l10n, add),
          ],
        ),
      ),
    );
  }

  Widget _options_(
    AppLocalizations l10n,
    TorrentCapabilities caps,
    ServiceKind? kind,
    bool adding,
  ) {
    return ExpansionTile(
      title: Text(l10n.torAddOptions),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      children: [
        TextField(
          controller: _savePath,
          enabled: !adding,
          autocorrect: false,
          decoration: InputDecoration(labelText: l10n.torAddSavePath),
        ),
        if (caps.hasLabel) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          TextField(
            controller: _category,
            enabled: !adding,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: caps.labelModel == LabelModel.label
                  ? l10n.torAddLabel
                  : l10n.torAddCategory,
            ),
          ),
        ] else if (kind == ServiceKind.deluge) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          Text(
            l10n.torAddNoLabels,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (caps.tags) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          TextField(
            controller: _tags,
            enabled: !adding,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.torAddTags,
              hintText: l10n.torAddTagsHint,
            ),
          ),
        ],
        if (caps.startPaused)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.torAddStartPaused),
            value: _paused,
            onChanged: adding ? null : (v) => setState(() => _paused = v),
          ),
      ],
    );
  }

  Widget _result(AppLocalizations l10n, AddState add) {
    final theme = Theme.of(context);
    final roles = context.roles;
    switch (add) {
      case AddIdle() || AddAdding():
        return const SizedBox.shrink();
      case AddFinished(:final results):
        final isFiles = results.any((r) => r.name != null);
        final okAll = results.every((r) => r.ok);
        return Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFiles)
                Text(
                  l10n.torAddFileSummary(
                    results.where((r) => r.ok).length,
                    results.length,
                  ),
                  style: theme.textTheme.titleSmall,
                ),
              for (final r in results) _resultRow(l10n, r, roles),
              if (!okAll)
                Padding(
                  padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
                  child: Text(
                    l10n.torAddRetryHint,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (okAll)
                Row(
                  children: [
                    TextButton(
                      onPressed: () =>
                          ref.read(addTorrentProvider.notifier).reset(),
                      child: Text(l10n.torAddAnother),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(l10n.torAddDone),
                    ),
                  ],
                ),
            ],
          ),
        );
    }
  }

  Widget _resultRow(
    AppLocalizations l10n,
    AddItemResult r,
    ConsolarrColorRoles roles,
  ) {
    final String text;
    if (r.ok) {
      text = r.name == null ? l10n.torAddAdded : l10n.torAddFileOk(r.name!);
    } else {
      final reason = switch (r.fileProblem) {
        FileProblem.tooLarge => l10n.torAddFileTooLarge,
        FileProblem.notTorrent => l10n.torAddFileNotTorrent,
        null =>
          r.error!.category == ErrorCategory.parseError && r.name != null
              ? l10n.torAddFileUnreadable
              : torrentErrorReason(l10n, r.error!),
      };
      text = r.name == null
          ? l10n.torAddFailed(reason)
          : l10n.torAddFileFailed(r.name!, reason);
    }
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            r.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: r.ok ? roles.success : roles.error,
          ),
          const SizedBox(width: ConsolarrSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
