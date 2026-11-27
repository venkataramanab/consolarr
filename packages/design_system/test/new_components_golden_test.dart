// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support/host.dart';

const _size = Size(360, 700);

/// name -> (harness variant, accessibility variant)
const _variants = {
  'dark_en': (
    HarnessVariant(
      size: _size,
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    ),
    A11yVariant.normal,
  ),
  'light_en': (
    HarnessVariant(
      size: _size,
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.light,
    ),
    A11yVariant.normal,
  ),
  'dark_ar': (
    HarnessVariant(
      size: _size,
      textScale: 1,
      locale: Locale('ar'),
      brightness: Brightness.dark,
    ),
    A11yVariant.normal,
  ),
  'dark_enXA_x2': (
    HarnessVariant(
      size: _size,
      textScale: 2,
      locale: Locale('en', 'XA'),
      brightness: Brightness.dark,
    ),
    A11yVariant.normal,
  ),
  'dark_hc_en': (
    HarnessVariant(
      size: _size,
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    ),
    A11yVariant.highContrastVariant,
  ),
  'light_hc_large_en': (
    HarnessVariant(
      size: _size,
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.light,
    ),
    A11yVariant(
      'high contrast, large targets',
      highContrast: true,
      largeTargets: true,
    ),
  ),
};

Widget _gap() => const SizedBox(height: 12);

final Map<String, Widget Function()> _galleries = {
  'glass_sheet': () => SizedBox(
    height: 520,
    child: GlassSheet(
      title: 'Sort by',
      closeLabel: 'Close',
      toggleDetentLabel: 'Expand or collapse',
      detents: const GlassSheetDetents(initialFull: true),
      child: const Text('Sheet content scrolls inside the sheet.'),
    ),
  ),
  'nested_menu': () => NestedMenu(
    semanticsLabel: 'More actions',
    items: [
      NestedMenuItem(label: 'Refresh', icon: Icons.refresh, onSelected: () {}),
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
        disabledReason: 'Nothing to search yet',
      ),
    ],
  ),
  'sort_sheet': () => SortSheet<int>(
    title: 'Sort',
    showTitle: true,
    options: const [
      SortOption(key: 0, label: 'Title'),
      SortOption(key: 1, label: 'Date added'),
      SortOption(key: 2, label: 'Size'),
    ],
    selected: 1,
    ascending: false,
    ascendingLabel: 'Ascending',
    descendingLabel: 'Descending',
    saveAsDefaultLabel: 'Save as default for this list',
    applyLabel: 'Apply',
    onApply: (_, _, _) {},
  ),
  'filter_sheet': () => FilterSheet(
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
          FilterChoice(id: 'ended', label: 'Ended'),
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
  'selection_bar': () => Column(
    children: [
      SelectionBar(
        selectedCount: 3,
        countLabel: '3 selected',
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
    ],
  ),
  'settings_blocks': () => Column(
    children: [
      SettingsSection(
        title: 'Security',
        footer: 'The lock covers the whole app.',
        children: [
          SwitchRow(
            title: 'App lock',
            subtitle: 'Ask for your device credential',
            icon: Icons.lock_outline,
            value: true,
            onChanged: (_) {},
          ),
          const SwitchRow(
            title: 'Block screenshots',
            icon: Icons.screenshot_outlined,
            value: false,
            onChanged: null,
          ),
          ChoiceSheetRow<int>(
            title: 'Theme',
            icon: Icons.palette_outlined,
            closeLabel: 'Close',
            options: const [
              ChoiceOption(value: 0, label: 'Dark'),
              ChoiceOption(value: 1, label: 'Light'),
            ],
            selected: 0,
            onSelected: (_) {},
          ),
          SettingsRow(title: 'About', icon: Icons.info_outline, onTap: () {}),
        ],
      ),
      _gap(),
    ],
  ),
};

void main() {
  _galleries.forEach((name, gallery) {
    _variants.forEach((vName, pair) {
      testWidgets('golden: $name $vName', (tester) async {
        final (harness, a11y) = pair;
        applyVariantView(tester, harness);
        await tester.pumpWidget(
          hostApp(
            harness,
            Padding(padding: const EdgeInsets.all(16), child: gallery()),
            a11y: a11y,
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/new_${name}_$vName.png'),
        );
      });
    });
  });
}
