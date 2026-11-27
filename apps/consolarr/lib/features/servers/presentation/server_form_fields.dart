// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/presentation/server_form_controller.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

String? _issueText(AppLocalizations l10n, FieldIssue? issue) => switch (issue) {
  null => null,
  FieldIssue.nameRequired => l10n.serverErrorNameRequired,
  FieldIssue.addressRequired => l10n.serverErrorAddressRequired,
  FieldIssue.addressInvalid => l10n.serverErrorAddressInvalid,
  FieldIssue.addressCredentials => l10n.serverErrorAddressCredentials,
  FieldIssue.addressQuery => l10n.serverErrorAddressQuery,
  FieldIssue.prefixInvalid => l10n.serverErrorPrefixInvalid,
  FieldIssue.headerInvalid => l10n.serverErrorHeaderInvalid,
};

// 12px helper/error text fails the contrast guideline on the card tones, so
// the form uses the 15px body styles.
TextStyle? _helperStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium;

TextStyle? _errorStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.error);

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: ConsolarrSpacing.section,
      bottom: ConsolarrSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Fields the user sets for the service type picker, name and address.
/// Used by the editor and, in parts, by onboarding.
class ServerFormFields extends StatelessWidget {
  const ServerFormFields({
    required this.controller,
    required this.onRevealChanged,
    this.showKindPicker = true,
    super.key,
  });

  final ServerFormController controller;

  /// Reports every secret field's reveal state (drives the window secure flag).
  final void Function(Object field, bool revealed) onRevealChanged;

  final bool showKindPicker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final l10n = context.l10n;
        final issues = controller.validate();
        final c = controller;
        final keepHint = c.hasStoredSecrets ? l10n.serverSecretKeepHint : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showKindPicker) ...[
              _SectionHeading(l10n.serverSectionService),
              Wrap(
                spacing: ConsolarrSpacing.sm,
                runSpacing: ConsolarrSpacing.sm,
                children: [
                  for (final kind in supportedServiceKinds)
                    ChoiceChip(
                      avatar: Icon(serviceKindIcon(kind), size: 18),
                      label: Text(serviceKindLabel(l10n, kind)),
                      selected: c.kind == kind,
                      onSelected: c.isEditing ? null : (_) => c.setKind(kind),
                    ),
                ],
              ),
              const SizedBox(height: ConsolarrSpacing.md),
            ],
            TextField(
              controller: c.name,
              textInputAction: TextInputAction.next,
              onTap: () => c.touch('name'),
              onChanged: (_) => c.touch('name'),
              decoration: InputDecoration(
                helperStyle: _helperStyle(context),
                errorStyle: _errorStyle(context),
                labelText: l10n.serverFieldName,
                errorText: c.shows('name')
                    ? _issueText(l10n, issues.name)
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            _SectionHeading(l10n.serverSectionAddress),
            TextField(
              controller: c.address,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => c.touch('address'),
              decoration: InputDecoration(
                helperStyle: _helperStyle(context),
                errorStyle: _errorStyle(context),
                labelText: l10n.serverFieldAddress,
                hintText: l10n.serverFieldAddressHint,
                errorText: c.shows('address')
                    ? _issueText(l10n, issues.address)
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: ConsolarrSpacing.md),
            TextField(
              controller: c.pathPrefix,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => c.touch('prefix'),
              decoration: InputDecoration(
                helperStyle: _helperStyle(context),
                errorStyle: _errorStyle(context),
                labelText: l10n.serverFieldPathPrefix,
                helperText: l10n.serverPathPrefixHelper,
                helperMaxLines: 4,
                errorText: c.shows('prefix')
                    ? _issueText(l10n, issues.prefix)
                    : null,
                errorMaxLines: 4,
                border: const OutlineInputBorder(),
              ),
            ),
            _SectionHeading(l10n.serverSectionAuth),
            Wrap(
              spacing: ConsolarrSpacing.sm,
              runSpacing: ConsolarrSpacing.sm,
              children: [
                for (final mode in authModesFor(c.kind))
                  ChoiceChip(
                    label: Text(authModeLabel(l10n, mode)),
                    selected: c.authMode == mode,
                    onSelected: (_) => c.setAuthMode(mode),
                  ),
              ],
            ),
            const SizedBox(height: ConsolarrSpacing.md),
            if (c.authMode == AuthMode.apiKey)
              SecretTextField(
                label: l10n.serverFieldApiKey,
                showTooltip: l10n.serverSecretShow,
                hideTooltip: l10n.serverSecretHide,
                controller: c.apiKey,
                helperText: keepHint,
                onRevealChanged: (v) => onRevealChanged(c.apiKey, v),
              ),
            if (c.authMode == AuthMode.basic) ...[
              TextField(
                controller: c.username,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  helperStyle: _helperStyle(context),
                  errorStyle: _errorStyle(context),
                  labelText: l10n.serverFieldUsername,
                  helperText: keepHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: ConsolarrSpacing.md),
              SecretTextField(
                label: l10n.serverFieldPassword,
                showTooltip: l10n.serverSecretShow,
                hideTooltip: l10n.serverSecretHide,
                controller: c.password,
                helperText: keepHint,
                onRevealChanged: (v) => onRevealChanged(c.password, v),
              ),
            ],
            _SectionHeading(l10n.serverSectionHeaders),
            Text(
              l10n.serverHeadersHelper,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (c.shows('headers') && issues.headers != null)
              Padding(
                padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
                child: Text(
                  _issueText(l10n, issues.headers)!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (var i = 0; i < c.headers.length; i++)
              _HeaderRow(
                key: ObjectKey(c.headers[i]),
                field: c.headers[i],
                onRemove: () => c.removeHeader(i),
                onRevealChanged: (v) => onRevealChanged(c.headers[i], v),
                onNameChanged: () => c.touch('headers'),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: c.headers.length >= ServerProfile.maxHeaders
                    ? null
                    : c.addHeader,
                icon: const Icon(Icons.add),
                label: Text(l10n.serverHeaderAdd),
              ),
            ),
            _SectionHeading(l10n.serverSectionSecurity),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.serverCleartextTitle),
              value: c.allowCleartext,
              onChanged: c.setAllowCleartext,
            ),
            if (c.allowCleartext || c.addressIsHttp)
              Padding(
                padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcludeSemantics(
                      child: Icon(Icons.warning_amber_rounded, size: 20),
                    ),
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Expanded(
                      child: Text(
                        c.addressIsHttp && !c.allowCleartext
                            ? l10n.serverCleartextNeeded
                            : l10n.serverCleartextRisk,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.field,
    required this.onRemove,
    required this.onRevealChanged,
    required this.onNameChanged,
    super.key,
  });

  final HeaderField field;
  final VoidCallback onRemove;
  final ValueChanged<bool> onRevealChanged;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: field.name,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => onNameChanged(),
                  decoration: InputDecoration(
                    helperStyle: _helperStyle(context),
                    errorStyle: _errorStyle(context),
                    labelText: l10n.serverHeaderName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: ConsolarrSpacing.sm),
                SecretTextField(
                  label: l10n.serverHeaderValue,
                  showTooltip: l10n.serverSecretShow,
                  hideTooltip: l10n.serverSecretHide,
                  controller: field.value,
                  onRevealChanged: onRevealChanged,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.serverHeaderRemove,
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
