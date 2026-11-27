// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/error_messages.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/certificate_flow.dart';
import 'package:consolarr/features/servers/presentation/server_form_controller.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

sealed class _TestState {
  const _TestState();
}

class _Idle extends _TestState {
  const _Idle();
}

class _Testing extends _TestState {
  const _Testing();
}

class _Success extends _TestState {
  const _Success(this.version);
  final String version;
}

class _Failure extends _TestState {
  const _Failure(this.error);
  final AppError error;
}

/// The "Test connection" button and its result (SRV-05, SRV-06).
///
/// Failure classes each show a plain-language message and a fix hint. A
/// certificate problem opens the trust sheet; after an explicit accept the
/// pin is stored and the test runs again. The result resets when the form
/// changes.
class ConnectionTestPanel extends ConsumerStatefulWidget {
  const ConnectionTestPanel({
    required this.controller,
    this.onResult,
    super.key,
  });

  final ServerFormController controller;

  /// Called with `true` after a successful test and `false` when the result
  /// is cleared or the test failed.
  final ValueChanged<bool>? onResult;

  @override
  ConsumerState<ConnectionTestPanel> createState() =>
      _ConnectionTestPanelState();
}

class _ConnectionTestPanelState extends ConsumerState<ConnectionTestPanel> {
  _TestState _state = const _Idle();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_formChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller.removeListener(_formChanged);
    super.dispose();
  }

  void _formChanged() {
    if (_state is _Success || _state is _Failure) _set(const _Idle());
  }

  void _set(_TestState s) {
    if (_disposed || !mounted) return;
    setState(() => _state = s);
    widget.onResult?.call(s is _Success);
  }

  Future<ServerCredentials> _credentials(ServerDraft draft) async {
    final c = widget.controller;
    final existing = c.existing;
    var stored = ServerCredentials.empty;
    // Stored secrets are never sent to a changed origin.
    if (existing != null && !c.originChanged) {
      stored = await ref
          .read(serverRepositoryProvider)
          .loadCredentials(existing.profile);
    }
    final entered = c.toDraft(storedHeaders: stored.headers).credentials;
    return ServerCredentials(
      apiKey: entered.apiKey ?? stored.apiKey,
      username: entered.username ?? stored.username,
      password: entered.password ?? stored.password,
      headers: entered.headers,
    );
  }

  Future<void> _run() async {
    final c = widget.controller;
    c.showAllErrors();
    if (!c.validate().isValid) return;
    final draft = c.toDraft();
    final parsed = ServerProfile.parse(
      id: c.draftId,
      name: draft.name,
      kind: draft.kind,
      address: draft.address,
      pathPrefix: draft.pathPrefix,
      authMode: draft.authMode,
      allowCleartext: draft.allowCleartext,
      headerNames: [for (final h in draft.credentials.headers) h.name],
    );
    final profile = parsed.valueOrNull;
    if (profile == null) {
      _set(_Failure(parsed.errorOrNull!));
      return;
    }
    final credentials = await _credentials(draft);
    for (var attempt = 0; attempt < 3; attempt++) {
      _set(const _Testing());
      final outcome = await ref
          .read(connectionTesterProvider)
          .test(profile, credentials);
      if (!mounted) return;
      switch (outcome) {
        case ConnectionTestSuccess(:final version):
          _set(_Success(version));
          return;
        case ConnectionTestFailure(:final error):
          final decision = await handleCertificateError(
            context,
            ref,
            error: error,
            serverName: draft.name,
          );
          if (decision == CertificateOutcome.trusted && mounted) continue;
          _set(_Failure(error));
          return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = _state;
    final testing = state is _Testing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: testing ? null : _run,
            icon: testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: Text(
              testing ? l10n.serverTestTesting : l10n.serverTestButton,
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: switch (state) {
            _Success(:final version) => Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    label: l10n.serverTestSuccessLabel,
                    icon: Icons.check_circle_outline,
                    tone: StatusTone.success,
                  ),
                  const SizedBox(height: ConsolarrSpacing.xs),
                  Text(
                    l10n.serverTestSuccess(version),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            _Failure(:final error) => _FailureView(error: error),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final message = connectionErrorMessage(l10n, error);
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(
            label: l10n.serverTestFailedLabel,
            icon: Icons.error_outline,
            tone: StatusTone.error,
          ),
          const SizedBox(height: ConsolarrSpacing.xs),
          Text(message.message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: ConsolarrSpacing.xs),
          Text(message.hint, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
