// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/error_messages.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/connection_test_panel.dart';
import 'package:consolarr/features/servers/presentation/reveal_tracker.dart';
import 'package:consolarr/features/servers/presentation/screen_tracking.dart';
import 'package:consolarr/features/servers/presentation/server_form_controller.dart';
import 'package:consolarr/features/servers/presentation/server_form_fields.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

/// Create or edit one server (SRV-02, SRV-04..SRV-07).
///
/// Secrets are never prefilled; leaving a secret empty keeps the saved value.
/// While any secret is revealed the window is marked secure (no screenshots).
class ServerEditorScreen extends ConsumerStatefulWidget {
  const ServerEditorScreen({this.serverId, this.initialKind, super.key});

  /// Edit this server; `null` creates a new one.
  final String? serverId;
  final ServiceKind? initialKind;

  @override
  ConsumerState<ServerEditorScreen> createState() => _ServerEditorScreenState();
}

class _ServerEditorScreenState extends ConsumerState<ServerEditorScreen> {
  ServerFormController? _controller;
  RevealTracker? _reveal;
  bool _loading = true;
  bool _saving = false;
  bool _discarding = false;
  AppError? _saveError;

  @override
  void initState() {
    super.initState();
    _reveal = RevealTracker(ref.read(secureScreenProvider));
    _load();
  }

  Future<void> _load() async {
    ServerEntry? existing;
    if (widget.serverId != null) {
      existing = await ref
          .read(serverRepositoryProvider)
          .find(widget.serverId!);
    }
    if (!mounted) return;
    setState(() {
      _controller = ServerFormController(
        kind: widget.initialKind,
        existing: existing,
      );
      _loading = false;
    });
  }

  @override
  void dispose() {
    _reveal?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = _controller!;
    c.showAllErrors();
    if (!c.validate().isValid || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final repo = ref.read(serverRepositoryProvider);
    final existing = c.existing;
    final stored = existing == null || c.originChanged
        ? ServerCredentials.empty
        : await repo.loadCredentials(existing.profile);
    final result = await repo.save(c.toDraft(storedHeaders: stored.headers));
    if (!mounted) return;
    switch (result) {
      case Ok():
        c.markSaved();
        ref.invalidate(serversProvider);
        setState(() => _saving = false);
        await Navigator.of(context).maybePop();
      case Err(:final error):
        setState(() {
          _saving = false;
          _saveError = error;
        });
    }
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverDiscardTitle),
        content: Text(l10n.serverDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.serverDiscardKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.serverDiscardConfirm),
          ),
        ],
      ),
    );
    if (discard ?? false) {
      setState(() => _discarding = true);
      if (mounted) await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = _controller;
    final title = widget.serverId == null
        ? l10n.serverEditorTitleNew
        : l10n.serverEditorTitleEdit;
    if (_loading || c == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return ScreenViewTracker(
      screen: ScreenName.serverEditor,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => PopScope(
          canPop: _discarding || !c.isDirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmDiscard();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.serverEditorSave),
                ),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.existing?.needsCredentials ?? false)
                      _Banner(
                        icon: Icons.key_off_outlined,
                        text: l10n.serverNeedsCredentialsBanner,
                      ),
                    ServerFormFields(
                      controller: c,
                      onRevealChanged: _reveal!.update,
                    ),
                    const SizedBox(height: ConsolarrSpacing.section),
                    ConnectionTestPanel(controller: c),
                    if (c.existing != null) PinSection(entry: c.existing!),
                    if (_saveError != null) _SaveError(error: _saveError!),
                    const SizedBox(height: ConsolarrSpacing.xxl),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
      padding: const EdgeInsets.all(ConsolarrSpacing.md),
      decoration: BoxDecoration(
        color: context.roles.raised,
        borderRadius: ConsolarrRadii.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.roles.warning),
          const SizedBox(width: ConsolarrSpacing.md),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SaveError extends StatelessWidget {
  const _SaveError({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = connectionErrorMessage(l10n, error);
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.lg),
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
            const SizedBox(height: ConsolarrSpacing.xs),
            Text(message.message),
            Text(message.hint, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// The pinned certificate of a server with a remove action (SRV-06).
class PinSection extends ConsumerStatefulWidget {
  const PinSection({required this.entry, super.key});

  final ServerEntry entry;

  @override
  ConsumerState<PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends ConsumerState<PinSection> {
  late Future<CertificateFingerprint?> _pin = _read();

  PinKey get _key => PinKey.forProfile(widget.entry.profile);

  /// The pin section is informational: a profile that cannot form a pin key,
  /// or a store that cannot be read, simply shows no pin (the connection
  /// itself fails closed elsewhere).
  Future<CertificateFingerprint?> _read() async {
    try {
      return await ref.read(pinStoreProvider).read(_key);
    } on Object {
      return null;
    }
  }

  Future<void> _remove(CertificateFingerprint pinned) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverPinRemoveTitle),
        content: Text(l10n.serverPinRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.serversCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.serverPinRemoveConfirm),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    // Directly after the user's explicit confirmation of this exact removal.
    await ref
        .read(pinStoreProvider)
        .clear(
          _key,
          UserPinConfirmation.userAccepted(key: _key, fingerprint: pinned),
        );
    if (mounted) {
      setState(() {
        _pin = _read();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<CertificateFingerprint?>(
      future: _pin,
      builder: (context, snapshot) {
        final pin = snapshot.data;
        if (pin == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: ConsolarrSpacing.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.serverPinTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: ConsolarrSpacing.xs),
              Text(
                l10n.serverPinFingerprint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SelectableText(
                pin.display,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontFeatures: ConsolarrTypeScale.tabularFigures),
              ),
              TextButton.icon(
                onPressed: () => _remove(pin),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.serverPinRemove),
              ),
            ],
          ),
        );
      },
    );
  }
}
