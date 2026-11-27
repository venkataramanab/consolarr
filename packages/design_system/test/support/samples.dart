// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

const longText =
    'An extraordinarily long title that keeps going and going well past any '
    'reasonable width so that wrapping and ellipsis are exercised properly';

const fingerprintSample =
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';

/// Named widgets, each pumped under the whole harness matrix.
Map<String, Widget Function()> componentSamples() => {
  'GlassBar': () =>
      const GlassBar(padding: EdgeInsets.all(12), child: Text(longText)),
  'FloatingNavBar': () => Align(
    alignment: Alignment.bottomCenter,
    child: FloatingNavBar(
      selectedIndex: 1,
      onSelected: (_) {},
      destinations: const [
        FloatingNavDestination(
          icon: Icons.tv_outlined,
          selectedIcon: Icons.tv,
          label: 'Series library',
        ),
        FloatingNavDestination(
          icon: Icons.download_outlined,
          selectedIcon: Icons.download,
          label: 'Torrents and downloads',
          badge: Icon(Icons.circle, size: 8),
        ),
        FloatingNavDestination(
          icon: Icons.dns_outlined,
          selectedIcon: Icons.dns,
          label: 'Servers',
        ),
      ],
    ),
  ),
  'PosterCard': () => Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 120,
      child: PosterCard(
        title: longText,
        subtitle: longText,
        badges: const [
          StatusChip(label: 'Continuing', icon: Icons.play_arrow),
          StatusChip(label: 'Monitored', icon: Icons.bookmark),
        ],
        onTap: () {},
      ),
    ),
  ),
  'MediaListTile': () => Padding(
    padding: const EdgeInsets.all(16),
    child: MediaListTile(
      title: longText,
      metadata: const [longText, '2021', 'Network'],
      leading: const ArtworkPlaceholder(),
      trailing: const StatusChip(label: 'Ended', icon: Icons.stop),
      onTap: () {},
    ),
  ),
  'ProgressFillRow': () => Padding(
    padding: const EdgeInsets.all(16),
    child: ProgressFillRow(
      title: longText,
      progress: 0.42,
      state: ProgressRowState.active,
      stateIcon: Icons.arrow_downward,
      stateLabel: 'Downloading',
      progressLabel: '42%',
      semanticsLabel: 'Downloading, 42 percent',
      details: const ['12.5 MB/s', '1h 20m left', 'Ratio 0.5', '4.2 GB'],
      onTap: () {},
    ),
  ),
  'StatusChip': () => const Padding(
    padding: EdgeInsets.all(16),
    child: StatusChip(
      label: longText,
      icon: Icons.check_circle,
      tone: StatusTone.success,
      details: longText,
      initiallyExpanded: true,
    ),
  ),
  'SkeletonBox': () => const Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        SkeletonBox(height: 24),
        SizedBox(height: 8),
        SkeletonBox(width: 200, height: 24),
      ],
    ),
  ),
  'EmptyState': () => EmptyState(
    icon: Icons.tv_off,
    headline: longText,
    message: longText,
    actionLabel: 'Add a server with a long label',
    onAction: () {},
  ),
  'ErrorState': () => ErrorState(
    headline: longText,
    message: longText,
    hint: longText,
    retryLabel: 'Try again',
    onRetry: () {},
    secondaryLabel: 'Edit server',
    onSecondary: () {},
  ),
  'OfflineBanner': () => Padding(
    padding: const EdgeInsets.all(16),
    child: OfflineBanner(
      message: longText,
      ageText: longText,
      retryLabel: 'Reconnect',
      onRetry: () {},
    ),
  ),
  'CertificateTrustSheet': () => CertificateTrustSheet(
    variant: CertificateSheetVariant.mismatch,
    title: 'Certificate changed',
    serverName: longText,
    explanation: longText,
    warning: longText,
    fingerprintLabel: 'SHA-256 fingerprint',
    fingerprint: fingerprintSample,
    previousFingerprintLabel: 'Previously trusted',
    previousFingerprint: fingerprintSample,
    subjectLabel: 'Subject',
    subject: longText,
    issuerLabel: 'Issuer',
    issuer: longText,
    validityLabel: 'Valid',
    validity: 'Jan 1, 2026 to Jan 1, 2027',
    acceptLabel: 'Trust the new certificate',
    rejectLabel: 'Cancel',
    onAccept: () {},
    onReject: () {},
  ),
  'SecretTextField': () => const Padding(
    padding: EdgeInsets.all(16),
    child: SecretTextField(
      label: 'API key',
      showTooltip: 'Show',
      hideTooltip: 'Hide',
      helperText: 'Stored securely on this device',
    ),
  ),
  'SecretTextField (long)': () => const Padding(
    padding: EdgeInsets.all(16),
    child: SecretTextField(
      label: longText,
      showTooltip: 'Show',
      hideTooltip: 'Hide',
      helperText: longText,
    ),
  ),
};
