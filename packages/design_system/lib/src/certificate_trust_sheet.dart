// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/label_separators.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/type_scale.dart';
import 'package:material_ui/material_ui.dart';

/// Which situation the sheet explains.
enum CertificateSheetVariant {
  /// First contact with an untrusted certificate: accept pins it.
  firstUse,

  /// A pinned server presented a different certificate: blocking; accepting
  /// is an explicit re-trust.
  mismatch,

  /// Expired certificate: cannot be trusted, accept is disabled.
  expired,
}

/// Builds the sheet; [accept] and [reject] close the modal with a result.
typedef CertificateSheetBuilder = CertificateTrustSheet Function(
  BuildContext context,
  VoidCallback accept,
  VoidCallback reject,
);

/// Content of the certificate trust bottom sheet (SRV-06).
///
/// Pure presentation: it only reports the user's choice through [onAccept] /
/// [onReject]. The feature code creates any pin confirmation in its own
/// accept handler.
class CertificateTrustSheet extends StatelessWidget {
  const CertificateTrustSheet({
    required this.variant,
    required this.title,
    required this.serverName,
    required this.explanation,
    required this.fingerprintLabel,
    required this.fingerprint,
    required this.subjectLabel,
    required this.subject,
    required this.issuerLabel,
    required this.issuer,
    required this.validityLabel,
    required this.validity,
    required this.acceptLabel,
    required this.rejectLabel,
    required this.onAccept,
    required this.onReject,
    this.warning,
    this.previousFingerprintLabel,
    this.previousFingerprint,
    this.handleLabel,
    super.key,
  });

  final CertificateSheetVariant variant;
  final String title;
  final String serverName;
  final String explanation;

  /// Prominent warning text for [CertificateSheetVariant.mismatch] and
  /// [CertificateSheetVariant.expired].
  final String? warning;

  final String fingerprintLabel;

  /// SHA-256, colon separated hex (`AB:CD:...`).
  final String fingerprint;
  final String? previousFingerprintLabel;
  final String? previousFingerprint;
  final String subjectLabel;
  final String subject;
  final String issuerLabel;
  final String issuer;
  final String validityLabel;

  /// Pre-formatted validity range.
  final String validity;
  final String acceptLabel;
  final String rejectLabel;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  /// Accessible name of the drag handle.
  final String? handleLabel;

  /// Shows the sheet. Resolves `true` on accept, `false` on reject or dismiss.
  static Future<bool> show(
    BuildContext context, {
    required CertificateSheetBuilder builder,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => builder(
        sheetContext,
        () => Navigator.of(sheetContext).pop(true),
        () => Navigator.of(sheetContext).pop(false),
      ),
    );
    return result ?? false;
  }

  /// `AB:CD:EF:GH:...` -> groups of four bytes for wrapping.
  static List<String> _groups(String fp) {
    final parts = fp.split(':');
    return [
      for (var i = 0; i < parts.length; i += 4)
        parts.sublist(i, (i + 4).clamp(0, parts.length)).join(':'),
    ];
  }

  Widget _fingerprint(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: ConsolarrSeparators.of(context).joinList([label, value]),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: ConsolarrSpacing.xs),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: ConsolarrSpacing.md,
              runSpacing: ConsolarrSpacing.xxs,
              children: [
                for (final g in _groups(value))
                  Text(
                    g,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: ConsolarrTypeScale.tabularFigures,
                      fontWeight: ConsolarrTypeScale.bold,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    const gap = SizedBox(height: ConsolarrSpacing.md);
    final canAccept = variant != CertificateSheetVariant.expired;
    final showWarning = warning != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ConsolarrSpacing.gutter,
          ConsolarrSpacing.sm,
          ConsolarrSpacing.gutter,
          ConsolarrSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Semantics(
                label: handleLabel,
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: roles.textTertiary,
                    borderRadius: ConsolarrRadii.chip,
                  ),
                ),
              ),
            ),
            gap,
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: ConsolarrSpacing.xs),
            Text(serverName, style: theme.textTheme.titleMedium),
            const SizedBox(height: ConsolarrSpacing.sm),
            Text(explanation, style: theme.textTheme.bodyLarge),
            if (showWarning) ...[
              gap,
              Semantics(
                container: true,
                liveRegion: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: roles.raised,
                    borderRadius: ConsolarrRadii.card,
                    border: Border.all(color: roles.error, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(ConsolarrSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: roles.error,
                          ),
                        ),
                        const SizedBox(width: ConsolarrSpacing.md),
                        Expanded(
                          child: Text(
                            warning!,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            gap,
            _fingerprint(context, fingerprintLabel, fingerprint),
            if (previousFingerprint != null &&
                previousFingerprintLabel != null) ...[
              gap,
              _fingerprint(
                context,
                previousFingerprintLabel!,
                previousFingerprint!,
              ),
            ],
            gap,
            _field(context, subjectLabel, subject),
            const SizedBox(height: ConsolarrSpacing.sm),
            _field(context, issuerLabel, issuer),
            const SizedBox(height: ConsolarrSpacing.sm),
            _field(context, validityLabel, validity),
            const SizedBox(height: ConsolarrSpacing.xl),
            FilledButton(
              onPressed: onReject,
              child: Text(rejectLabel, textAlign: TextAlign.center),
            ),
            const SizedBox(height: ConsolarrSpacing.sm),
            OutlinedButton(
              onPressed: canAccept ? onAccept : null,
              child: Text(acceptLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
