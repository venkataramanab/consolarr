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
  'CertificateTrustSheet (first use)': () =>
      _trustSheet(CertificateSheetVariant.firstUse),
  'CertificateTrustSheet (mismatch)': () =>
      _trustSheet(CertificateSheetVariant.mismatch),
  'CertificateTrustSheet (expired)': () =>
      _trustSheet(CertificateSheetVariant.expired),
  'ArtworkPlaceholder': () => const Padding(
    padding: EdgeInsets.all(16),
    child: SizedBox(width: 120, height: 180, child: ArtworkPlaceholder()),
  ),
  'MeasuredBarHeight': () => MeasuredBarHeight(
    height: ValueNotifier<double>(0),
    child: const GlassBar(padding: EdgeInsets.all(12), child: Text(longText)),
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

  'GlassSheet': () => SizedBox(
    height: 560,
    child: GlassSheet(
      title: longText,
      closeLabel: 'Close',
      toggleDetentLabel: 'Expand or collapse',
      detents: const GlassSheetDetents(initialFull: true),
      child: const Text(longText),
    ),
  ),
  'NestedMenu': () => Padding(
    padding: const EdgeInsets.all(16),
    child: NestedMenu(
      semanticsLabel: 'More actions',
      items: [
        const NestedMenuItem(label: longText, icon: Icons.sort),
        NestedMenuItem(
          label: 'Sort by',
          icon: Icons.sort,
          children: [NestedMenuItem(label: 'Title', onSelected: () {})],
        ),
        NestedMenuItem(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () {},
        ),
        const NestedMenuItem(
          label: 'Search',
          icon: Icons.search,
          enabled: false,
          disabledReason: longText,
        ),
      ],
    ),
  ),
  'SortSheet': () => Padding(
    padding: const EdgeInsets.all(16),
    child: SortSheet<int>(
      title: 'Sort',
      showTitle: true,
      options: const [
        SortOption(key: 0, label: longText),
        SortOption(key: 1, label: 'Added'),
      ],
      selected: 0,
      ascending: true,
      ascendingLabel: 'Ascending',
      descendingLabel: 'Descending',
      saveAsDefaultLabel: 'Save as default for this list',
      applyLabel: 'Apply',
      onApply: (_, _, _) {},
    ),
  ),
  'FilterSheet': () => Padding(
    padding: const EdgeInsets.all(16),
    child: FilterSheet(
      title: 'Filter',
      activeCount: 2,
      activeCountLabel: '2 filters active',
      selection: const FilterSelection({
        'status': {'continuing'},
        'tags': {'a'},
      }),
      sections: const [
        FilterSection(
          id: 'status',
          label: 'Status',
          multiSelect: false,
          chips: [
            FilterChoice(id: 'continuing', label: 'Continuing'),
            FilterChoice(id: 'ended', label: longText),
          ],
        ),
        FilterSection(
          id: 'tags',
          label: 'Tags',
          chips: [
            FilterChoice(id: 'a', label: 'Tag A'),
            FilterChoice(id: 'b', label: 'Tag B'),
          ],
        ),
      ],
      clearAllLabel: 'Clear all',
      saveAsDefaultLabel: 'Save as default for this list',
      applyLabel: 'Apply',
      onApply: (_, _) {},
      onClear: () {},
    ),
  ),
  'SelectionBar': () => Padding(
    padding: const EdgeInsets.all(16),
    child: SelectionBar(
      selectedCount: 3,
      countLabel: '3 selected of a very long list of items',
      exitLabel: 'Exit selection',
      selectAllLabel: 'Select all',
      onExit: () {},
      onSelectAll: () {},
      actions: [
        SelectionAction(icon: Icons.pause, label: 'Pause', onPressed: () {}),
        SelectionAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onPressed: () {},
        ),
      ],
    ),
  ),
  'StagedReveal': () => const StagedReveal(
    revealKey: 'sample',
    order: 1,
    child: Padding(padding: EdgeInsets.all(16), child: Text(longText)),
  ),
  'SettingsSection': () => Padding(
    padding: const EdgeInsets.all(16),
    child: SettingsSection(
      title: longText,
      footer: longText,
      children: [
        SettingsRow(
          title: longText,
          subtitle: longText,
          icon: Icons.language,
          value: longText,
          onTap: () {},
        ),
        SwitchRow(
          title: longText,
          subtitle: longText,
          icon: Icons.lock_outline,
          value: true,
          onChanged: (_) {},
        ),
        ChoiceSheetRow<int>(
          title: 'Theme',
          icon: Icons.palette_outlined,
          closeLabel: 'Close',
          options: const [
            ChoiceOption(value: 0, label: 'Dark'),
            ChoiceOption(value: 1, label: longText, hint: 'Hint'),
          ],
          selected: 1,
          onSelected: (_) {},
        ),
      ],
    ),
  ),
  'SettingsRow (disabled)': () => Padding(
    padding: const EdgeInsets.all(16),
    child: SettingsRow(title: longText, enabled: false, onTap: () {}),
  ),
  'SwitchRow (off, disabled)': () => const Padding(
    padding: EdgeInsets.all(16),
    child: SwitchRow(title: longText, value: false, onChanged: null),
  ),
};

CertificateTrustSheet _trustSheet(CertificateSheetVariant variant) =>
    CertificateTrustSheet(
      variant: variant,
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
    );
