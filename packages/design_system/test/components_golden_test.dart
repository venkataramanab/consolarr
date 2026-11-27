// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

const _variants = {
  'dark_en': HarnessVariant(
    size: Size(360, 640),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.dark,
  ),
  'light_en': HarnessVariant(
    size: Size(360, 640),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.light,
  ),
  'dark_ar': HarnessVariant(
    size: Size(360, 640),
    textScale: 1,
    locale: Locale('ar'),
    brightness: Brightness.dark,
  ),
  'dark_enXA_x2': HarnessVariant(
    size: Size(360, 640),
    textScale: 2,
    locale: Locale('en', 'XA'),
    brightness: Brightness.dark,
  ),
};

Widget _gap() => const SizedBox(height: 12);

ProgressFillRow _row(ProgressRowState s, String label, double p) =>
    ProgressFillRow(
      title: 'Example Item',
      progress: p,
      state: s,
      stateIcon: switch (s) {
        ProgressRowState.active => Icons.arrow_downward,
        ProgressRowState.paused => Icons.pause,
        ProgressRowState.queued => Icons.schedule,
        ProgressRowState.idle => Icons.arrow_upward,
        ProgressRowState.error => Icons.error_outline,
      },
      stateLabel: label,
      progressLabel: '${(p * 100).round()}%',
      semanticsLabel: '$label ${(p * 100).round()}%',
      details: const ['1.2 MB/s', '10m left'],
    );

CertificateTrustSheet _sheet(CertificateSheetVariant v) =>
    CertificateTrustSheet(
      variant: v,
      title: 'Untrusted certificate',
      serverName: 'Example Server',
      explanation: 'Compare the fingerprint before trusting it.',
      warning: v == CertificateSheetVariant.firstUse
          ? null
          : 'The certificate is not the one you trusted before.',
      fingerprintLabel: 'SHA-256',
      fingerprint:
          'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
          'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89',
      subjectLabel: 'Subject',
      subject: 'CN=example.invalid',
      issuerLabel: 'Issuer',
      issuer: 'CN=example.invalid',
      validityLabel: 'Valid',
      validity: '2026-01-01 to 2027-01-01',
      acceptLabel: 'Trust this certificate',
      rejectLabel: 'Cancel',
      onAccept: () {},
      onReject: () {},
    );

/// One gallery of states per component.
final Map<String, Widget Function()> _galleries = {
  'glass_and_nav': () => Column(
    children: [
      const GlassBar(padding: EdgeInsets.all(16), child: Text('Glass bar')),
      _gap(),
      FloatingNavBar(
        selectedIndex: 0,
        onSelected: (_) {},
        destinations: const [
          FloatingNavDestination(
            icon: Icons.tv_outlined,
            selectedIcon: Icons.tv,
            label: 'Series',
          ),
          FloatingNavDestination(
            icon: Icons.download_outlined,
            selectedIcon: Icons.download,
            label: 'Torrents',
          ),
          FloatingNavDestination(
            icon: Icons.dns_outlined,
            selectedIcon: Icons.dns,
            label: 'Servers',
          ),
        ],
      ),
    ],
  ),
  'poster_card': () => const Row(
    children: [
      Expanded(
        child: PosterCard(
          title: 'Example Show',
          subtitle: '2021',
          badges: [StatusChip(label: 'Ended', icon: Icons.stop)],
        ),
      ),
      SizedBox(width: 12),
      Expanded(
        child: PosterCard(title: 'Another Example Show With A Long Name'),
      ),
    ],
  ),
  'media_list_tile': () => const Column(
    children: [
      MediaListTile(
        title: 'Example Show',
        metadata: ['2021', 'Example Network', '12 of 24'],
        leading: ArtworkPlaceholder(),
        trailing: StatusChip(label: 'Continuing', icon: Icons.play_arrow),
      ),
      SizedBox(height: 12),
      MediaListTile(title: 'Plain tile'),
    ],
  ),
  'progress_fill_row': () => Column(
    children: [
      _row(ProgressRowState.active, 'Downloading', 0.42),
      _gap(),
      _row(ProgressRowState.paused, 'Paused', 0.7),
      _gap(),
      _row(ProgressRowState.queued, 'Queued', 0),
      _gap(),
      _row(ProgressRowState.idle, 'Seeding', 1),
      _gap(),
      _row(ProgressRowState.error, 'Error', 0.2),
    ],
  ),
  'status_chip': () => const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      StatusChip(
        label: 'Healthy',
        icon: Icons.check_circle,
        tone: StatusTone.success,
      ),
      StatusChip(
        label: 'Degraded',
        icon: Icons.warning,
        tone: StatusTone.warning,
      ),
      StatusChip(
        label: 'Unreachable',
        icon: Icons.error,
        tone: StatusTone.error,
      ),
      StatusChip(label: 'Checking', icon: Icons.sync, tone: StatusTone.info),
      StatusChip(label: 'Unknown', icon: Icons.help_outline),
      StatusChip(
        label: 'Details',
        icon: Icons.info,
        details: 'Expanded details text',
        initiallyExpanded: true,
      ),
    ],
  ),
  'skeleton_box': () => const Column(
    children: [
      SkeletonBox(height: 72),
      SizedBox(height: 12),
      SkeletonBox(height: 16, width: 200),
      SizedBox(height: 12),
      SkeletonBox(height: 16, width: 120),
    ],
  ),
  'empty_state': () => SizedBox(
    height: 360,
    child: EmptyState(
      icon: Icons.tv_off,
      headline: 'No series yet',
      message: 'Add a series in Sonarr and it will show up here.',
      actionLabel: 'Refresh',
      onAction: () {},
    ),
  ),
  'error_state': () => SizedBox(
    height: 420,
    child: ErrorState(
      headline: 'Cannot connect',
      message: 'The server did not answer in time.',
      hint: 'Check the address and that the server is running.',
      retryLabel: 'Try again',
      onRetry: () {},
      secondaryLabel: 'Edit server',
      onSecondary: () {},
    ),
  ),
  'offline_banner': () => OfflineBanner(
    message: 'You are offline',
    ageText: 'Showing data from 5 minutes ago',
    retryLabel: 'Reconnect',
    onRetry: () {},
  ),
  'trust_sheet_first_use': () => _sheet(CertificateSheetVariant.firstUse),
  'trust_sheet_mismatch': () => _sheet(CertificateSheetVariant.mismatch),
  'trust_sheet_expired': () => _sheet(CertificateSheetVariant.expired),
  'secret_text_field': () => const Column(
    children: [
      SecretTextField(
        label: 'API key',
        showTooltip: 'Show',
        hideTooltip: 'Hide',
        helperText: 'Stored securely on this device',
      ),
    ],
  ),
};

void main() {
  _galleries.forEach((name, gallery) {
    _variants.forEach((vName, variant) {
      testWidgets('golden: $name $vName', (tester) async {
        applyVariantView(tester, variant);
        await tester.pumpWidget(
          harnessApp(
            variant,
            ConsolarrEffectsScope(
              reduceMotion: true,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: gallery(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_$vName.png'),
        );
      });
    });
  });
}
