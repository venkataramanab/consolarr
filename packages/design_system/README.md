# design_system

Tokens, theme and reusable widgets for Consolarr. No l10n and no feature
imports: components take already-localized strings as parameters.

## Sheets and menus

* `showGlassSheet` opens on the **root** navigator (above the floating nav
  bar, surviving tab switches). Give exactly one body:
  * `builder` for a short body (the sheet scrolls it);
  * `scrollBuilder: (context, controller) => ...` for a long list: attach the
    controller to a `ListView.builder` and it stays lazy.
* `GlassSheetDetents.peek` / `GlassSheetDetents.full` are the two ready-made
  detents; `GlassSheetDetents(peekFraction:, fullFraction:)` for custom ones.
* `SortSheet` keeps `title` required: a caller migrating from a stand-in
  without a title must pass one.
* `showNestedMenu` also uses the root navigator; Android back steps out of a
  sub-menu before it closes the menu.

## Migrating a stand-in filter sheet to `FilterSheet`

| Stand-in | Design system |
| --- | --- |
| `FilterChipOption(id, label)` | `FilterChipOption` (alias of `FilterChoice`) |
| per-section `initial:` set | one `FilterSelection` passed as `selection:` |
| `onApply(Map<String, Set<String>>)` | `onApply(FilterSelection selection, bool saveAsDefault)`; `selection.of(sectionId)` returns the set |

```dart
showGlassSheet<void>(
  context: context,
  title: l10n.filterTitle,
  closeLabel: l10n.commonClose,
  builder: (context) => FilterSheet(
    title: l10n.filterTitle,
    sections: [
      FilterSection(
        id: 'status',
        label: l10n.status,
        chips: [FilterChipOption(id: 'ended', label: l10n.ended)],
      ),
    ],
    selection: const FilterSelection({'status': {'ended'}}), // was initial:
    activeCount: 1,
    clearAllLabel: l10n.clearAll,
    saveAsDefaultLabel: l10n.saveAsDefault,
    applyLabel: l10n.apply,
    onApply: (selection, saveAsDefault) {
      final ended = selection.of('status').contains('ended');
    },
    onClear: () {},
  ),
);
```
