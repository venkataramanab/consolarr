// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'detail_harness.dart';

const _variant = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

/// The labels of the semantics tree in the order TalkBack walks it.
List<String> _traversal(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.trim().isNotEmpty) labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(tester.binding.rootPipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

/// The ordinal of the nearest ancestor of the node labelled [label] that has
/// an ordinal sort key.
double? _ordinalOf(WidgetTester tester, String label) {
  SemanticsNode? node = tester.getSemantics(find.bySemanticsLabel(label));
  while (node != null) {
    final key = node.sortKey;
    if (key is OrdinalSortKey) return key.order;
    node = node.parent;
  }
  return null;
}

void main() {
  testWidgets('sort keys put the Back button ahead of the content', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    applyVariantView(tester, _variant);
    await tester.pumpWidget(detailApp(_variant, api: detailApi()));
    await tester.pumpAndSettle();
    final back = _ordinalOf(tester, 'Back');
    final title = _ordinalOf(tester, 'Example Show 1');
    expect(back, isNotNull);
    expect(title, isNotNull);
    expect(back, lessThan(title!));
    handle.dispose();
  });

  testWidgets('the Back button is read before the series content', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    applyVariantView(tester, _variant);
    await tester.pumpWidget(detailApp(_variant, api: detailApi()));
    await tester.pumpAndSettle();

    final order = _traversal(tester);
    final back = order.indexWhere((l) => l == 'Back');
    final title = order.indexWhere((l) => l.contains('Example Show 1'));
    expect(back, isNonNegative, reason: 'Back button not in semantics');
    expect(title, isNonNegative, reason: 'title not in semantics');
    expect(back, lessThan(title), reason: 'order: $order');
    handle.dispose();
  });

  testWidgets('the Back button is read first on the not-found screen too', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    applyVariantView(tester, _variant);
    await tester.pumpWidget(detailApp(_variant, api: detailApi(), seriesId: 0));
    await tester.pumpAndSettle();
    final order = _traversal(tester);
    final back = order.indexWhere((l) => l == 'Back');
    expect(back, 0, reason: 'order: $order');
    handle.dispose();
  });
}
