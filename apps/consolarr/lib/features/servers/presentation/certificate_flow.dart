// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

/// What the user decided about a certificate problem.
enum CertificateOutcome {
  /// A pin was written; the caller should test again.
  trusted,

  /// The user declined, or the certificate cannot be trusted.
  notTrusted,
}

String _validity(BuildContext context, CertificateDetails c) {
  final m = MaterialLocalizations.of(context);
  return context.l10n.certSheetValidityRange(
    m.formatMediumDate(c.notBefore.toLocal()),
    m.formatMediumDate(c.notAfter.toLocal()),
  );
}

/// Shows the trust sheet for a typed certificate error and, only after the
/// user's explicit accept, writes the pin (SRV-06).
///
/// Returns `null` when [error] is not a certificate decision.
Future<CertificateOutcome?> handleCertificateError(
  BuildContext context,
  WidgetRef ref, {
  required AppError error,
  required String serverName,
}) async {
  final l10n = context.l10n;
  final tracker = ref.read(eventTrackerProvider);
  final pins = ref.read(pinStoreProvider);

  if (error is CertificateDecisionRequired ||
      error is TlsPinMismatch ||
      error is CertificateExpired) {
    await tracker.track(
      const ScreenViewedEvent(screen: ScreenName.certificateSheet),
    );
  }

  switch (error) {
    case CertificateDecisionRequired(:final key, :final certificate):
      final accepted = await CertificateTrustSheet.show(
        context,
        builder: (context, accept, reject) => CertificateTrustSheet(
          variant: CertificateSheetVariant.firstUse,
          title: l10n.certSheetTitleFirstUse,
          serverName: serverName,
          explanation: l10n.certSheetExplanationFirstUse,
          fingerprintLabel: l10n.certSheetFingerprint,
          fingerprint: certificate.fingerprint.display,
          subjectLabel: l10n.certSheetSubject,
          subject: certificate.subject,
          issuerLabel: l10n.certSheetIssuer,
          issuer: certificate.issuer,
          validityLabel: l10n.certSheetValidity,
          validity: _validity(context, certificate),
          acceptLabel: l10n.certSheetAccept,
          rejectLabel: l10n.certSheetReject,
          onAccept: accept,
          onReject: reject,
          handleLabel: l10n.certSheetHandle,
        ),
      );
      if (!accepted) {
        await tracker.track(
          const CertificateDecisionEvent(
            decision: CertificateDecisionParam.rejected,
          ),
        );
        return CertificateOutcome.notTrusted;
      }
      // Directly after the explicit accept of the sheet that showed exactly
      // this fingerprint.
      await pins.write(
        key,
        certificate.fingerprint,
        UserPinConfirmation.userAccepted(
          key: key,
          fingerprint: certificate.fingerprint,
        ),
      );
      await tracker.track(
        const CertificateDecisionEvent(
          decision: CertificateDecisionParam.accepted,
        ),
      );
      return CertificateOutcome.trusted;

    case TlsPinMismatch(:final key, :final pinned, :final presented):
      await tracker.track(
        const CertificateDecisionEvent(
          decision: CertificateDecisionParam.mismatch,
        ),
      );
      final accepted = await CertificateTrustSheet.show(
        context,
        builder: (context, accept, reject) => CertificateTrustSheet(
          variant: CertificateSheetVariant.mismatch,
          title: l10n.certSheetTitleMismatch,
          serverName: serverName,
          explanation: l10n.certSheetExplanationMismatch,
          warning: l10n.certSheetMismatchWarning,
          fingerprintLabel: l10n.certSheetFingerprint,
          fingerprint: presented.fingerprint.display,
          previousFingerprintLabel: l10n.certSheetPreviousFingerprint,
          previousFingerprint: pinned.display,
          subjectLabel: l10n.certSheetSubject,
          subject: presented.subject,
          issuerLabel: l10n.certSheetIssuer,
          issuer: presented.issuer,
          validityLabel: l10n.certSheetValidity,
          validity: _validity(context, presented),
          acceptLabel: l10n.certSheetAcceptMismatch,
          rejectLabel: l10n.certSheetReject,
          onAccept: accept,
          onReject: reject,
          handleLabel: l10n.certSheetHandle,
        ),
      );
      if (!accepted) return CertificateOutcome.notTrusted;
      // Explicit re-trust: forget the old pin, then pin what the user saw.
      final confirmation = UserPinConfirmation.userAccepted(
        key: key,
        fingerprint: presented.fingerprint,
      );
      await pins.clear(key, confirmation);
      await pins.write(key, presented.fingerprint, confirmation);
      return CertificateOutcome.trusted;

    case CertificateExpired(:final certificate):
      await CertificateTrustSheet.show(
        context,
        builder: (context, accept, reject) => CertificateTrustSheet(
          variant: CertificateSheetVariant.expired,
          title: l10n.certSheetTitleExpired,
          serverName: serverName,
          explanation: l10n.certSheetExplanationExpired,
          fingerprintLabel: l10n.certSheetFingerprint,
          fingerprint: certificate.fingerprint.display,
          subjectLabel: l10n.certSheetSubject,
          subject: certificate.subject,
          issuerLabel: l10n.certSheetIssuer,
          issuer: certificate.issuer,
          validityLabel: l10n.certSheetValidity,
          validity: _validity(context, certificate),
          acceptLabel: l10n.certSheetAccept,
          rejectLabel: l10n.certSheetReject,
          onAccept: accept,
          onReject: reject,
          handleLabel: l10n.certSheetHandle,
        ),
      );
      return CertificateOutcome.notTrusted;

    default:
      return null;
  }
}
