// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrent_limits_controller.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/error_text.dart';
import 'package:consolarr/features/torrents/presentation/screen_view.dart';
import 'package:consolarr/features/torrents/presentation/stand_ins/glass_sheet.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Opens the speed limits sheet (TOR-10).
Future<void> showSpeedLimitsSheet(BuildContext context) {
  final l10n = context.l10n;
  return showGlassSheet<void>(
    context: context,
    title: l10n.torLimitsTitle,
    closeLabel: l10n.torDetailClose,
    builder: (_) => const SpeedLimitsSheet(),
  );
}

enum _Unit {
  kb(1024),
  mb(1024 * 1024);

  const _Unit(this.bytes);
  final int bytes;
}

/// One limit editor: none or custom with a unit.
class _LimitDraft {
  _LimitDraft(int bytesPerSecond)
    : custom = bytesPerSecond > 0,
      unit =
          bytesPerSecond >= _Unit.mb.bytes * 1 &&
              bytesPerSecond % _Unit.mb.bytes == 0
          ? _Unit.mb
          : _Unit.kb,
      text = TextEditingController() {
    if (bytesPerSecond > 0) {
      text.text = '${(bytesPerSecond / unit.bytes).round()}';
    }
  }

  bool custom;
  _Unit unit;
  final TextEditingController text;

  int? get bytes {
    if (!custom) return 0;
    final v = int.tryParse(text.text.trim());
    return v == null || v <= 0 ? null : v * unit.bytes;
  }

  void dispose() => text.dispose();
}

/// Global download/upload limits and, where the client has it, the
/// alternative-limits switch.
class SpeedLimitsSheet extends ConsumerStatefulWidget {
  const SpeedLimitsSheet({super.key});

  @override
  ConsumerState<SpeedLimitsSheet> createState() => _SpeedLimitsSheetState();
}

class _SpeedLimitsSheetState extends ConsumerState<SpeedLimitsSheet> {
  _LimitDraft? _down;
  _LimitDraft? _up;
  bool _submitted = false;

  @override
  void dispose() {
    _down?.dispose();
    _up?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(torrentLimitsProvider);
    return TorrentScreenView(
      screen: ScreenName.torrentSpeedLimits,
      child: async.isLoading
          ? const Padding(
              padding: EdgeInsets.all(ConsolarrSpacing.gutter),
              child: SkeletonBox(height: 200),
            )
          : async.hasError
          ? Padding(
              padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.torLimitsLoadFailed(
                      torrentErrorReason(l10n, appErrorOrUnknown(async.error!)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(torrentLimitsProvider),
                    child: Text(l10n.torRetry),
                  ),
                ],
              ),
            )
          : _form(l10n, async.requireValue),
    );
  }

  Widget _editor(String title, _LimitDraft d, bool busy) {
    final l10n = context.l10n;
    final invalid = _submitted && d.bytes == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        RadioGroup<bool>(
          groupValue: d.custom,
          onChanged: (v) => setState(() => d.custom = v ?? d.custom),
          child: Column(
            children: [
              RadioListTile<bool>(
                value: false,
                enabled: !busy,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.torLimitsNone),
              ),
              RadioListTile<bool>(
                value: true,
                enabled: !busy,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.torLimitsCustom),
              ),
            ],
          ),
        ),
        if (d.custom)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: d.text,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.torLimitsValue,
                    errorText: invalid ? l10n.torLimitsInvalid : null,
                    errorMaxLines: 2,
                  ),
                ),
              ),
              const SizedBox(width: ConsolarrSpacing.sm),
              Semantics(
                container: true,
                label: l10n.torLimitsUnit,
                child: SegmentedButton<_Unit>(
                  segments: [
                    ButtonSegment(
                      value: _Unit.kb,
                      label: Text(l10n.torLimitsUnitKB),
                    ),
                    ButtonSegment(
                      value: _Unit.mb,
                      label: Text(l10n.torLimitsUnitMB),
                    ),
                  ],
                  selected: {d.unit},
                  onSelectionChanged: busy
                      ? null
                      : (s) => setState(() => d.unit = s.first),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _form(AppLocalizations l10n, LimitsView view) {
    _down ??= _LimitDraft(view.limits.download);
    _up ??= _LimitDraft(view.limits.upload);
    final caps = ref.watch(torrentCapabilitiesProvider);
    final busy = view.applying;
    final theme = Theme.of(context);
    final alt = view.limits.alternativeActive;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.gutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editor(l10n.torLimitsDownload, _down!, busy),
          const SizedBox(height: ConsolarrSpacing.md),
          _editor(l10n.torLimitsUpload, _up!, busy),
          const SizedBox(height: ConsolarrSpacing.md),
          if (caps.alternativeSpeed && alt != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: alt,
              title: Text(l10n.torLimitsAlt),
              subtitle: Text(
                view.altUnsupported
                    ? l10n.torLimitsAltUnsupported
                    : l10n.torLimitsAltHint,
              ),
              onChanged: busy || view.altUnsupported
                  ? null
                  : (v) => ref
                        .read(torrentLimitsProvider.notifier)
                        .setAlternative(v),
            ),
          ] else
            Text(l10n.torLimitsNoAlt, style: theme.textTheme.bodySmall),
          const SizedBox(height: ConsolarrSpacing.md),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    final d = _down!.bytes;
                    final u = _up!.bytes;
                    setState(() => _submitted = true);
                    if (d == null || u == null) return;
                    ref
                        .read(torrentLimitsProvider.notifier)
                        .apply(download: d, upload: u);
                  },
            child: Text(busy ? l10n.torLimitsApplying : l10n.torLimitsApply),
          ),
          if (view.failure != null || view.applied)
            Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  view.failure != null
                      ? l10n.torLimitsFailed(
                          torrentErrorReason(l10n, view.failure!),
                        )
                      : l10n.torLimitsApplied,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
