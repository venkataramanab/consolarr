// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'text_contrast.dart';

/// Android tap targets are at least 48x48 dp.
Future<void> expectTapTargets(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    // Semantics are only built on the next frame after being enabled; without
    // this pump the guidelines would pass vacuously on an empty tree.
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  } finally {
    handle.dispose();
  }
}

/// Every tappable element has a semantic label.
Future<void> expectLabeledTapTargets(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    // Semantics are only built on the next frame after being enabled; without
    // this pump the guidelines would pass vacuously on an empty tree.
    await tester.pump();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  } finally {
    handle.dispose();
  }
}

/// The labels of text that the viewport (or the screen) clips: only part
/// of it is painted there, so the contrast guideline, which reads pixels,
/// cannot judge it at this scroll position. Such text is judged once it is
/// scrolled fully into view (see [expectTextContrastWhileScrolling]).
Set<String> clippedLabels(WidgetTester tester) {
  final out = <String>{};
  final view = tester.binding.renderViews.first;
  final root = view.owner?.semanticsOwner?.rootSemanticsNode;
  if (root == null) return out;
  final screen = Offset.zero & view.size;

  Rect toGlobal(SemanticsNode node, Rect rect) {
    var r = rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final t = n.transform;
      if (t != null) r = MatrixUtils.transformRect(t, r);
    }
    return r;
  }

  void visit(SemanticsNode node) {
    if (node.label.trim().isNotEmpty) {
      final clip = node.parentPaintClipRect;
      // The clip is in the node's own coordinate system.
      final visible = clip == null
          ? screen
          : toGlobal(node, clip).intersect(screen);
      for (final element in find.text(node.label).hitTestable().evaluate()) {
        final box = element.renderObject;
        if (box is! RenderBox) continue;
        final sample = MatrixUtils.transformRect(
          box.getTransformTo(null),
          box.paintBounds,
        );
        if (!_containsRect(visible, sample)) out.add(node.label);
      }
    }
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(root);
  return out;
}

bool _containsRect(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

/// Runs [expectTextContrast] at every scroll position of the first
/// scrollable (top to bottom, half a viewport at a time), skipping at each
/// position only the nodes that position clips, so that every node is judged
/// while it is fully visible. [skipLabels] works as in [expectTextContrast].
Future<void> expectTextContrastWhileScrolling(
  WidgetTester tester, {
  Set<String> skipLabels = const {},
}) async {
  final scrollable = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(scrollable);
  final position = state.position;
  final step = position.viewportDimension / 2;
  final max = position.maxScrollExtent;
  // `pump`, not `pumpAndSettle`: a running spinner never settles.
  Future<void> frame() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  position.jumpTo(0);
  await frame();
  try {
    for (var offset = 0.0; ; offset += step) {
      final at = offset > max ? max : offset;
      position.jumpTo(at);
      await frame();
      // Semantics are only built on the next frame after being enabled.
      final handle = tester.ensureSemantics();
      await tester.pump();
      final skip = {...skipLabels, ...clippedLabels(tester)};
      handle.dispose();
      await expectTextContrast(tester, skipLabels: skip);
      if (at >= max) break;
    }
  } finally {
    position.jumpTo(0);
    await frame();
  }
}

/// Text meets the WCAG contrast guideline against what is rendered behind it.
///
/// [skipLabels] exempts individual nodes by their exact semantics label. It
/// exists for a node the guideline cannot judge (text over an image, say);
/// name the one node, say why at the call site, and never skip a whole size or
/// screen. Prefer fixing the screen: [TextContrastGuideline] reads the glyph
/// colour, not the anti-aliasing blends, and samples only the text's own box.
Future<void> expectTextContrast(
  WidgetTester tester, {
  Set<String> skipLabels = const {},
}) async {
  final handle = tester.ensureSemantics();
  try {
    // Semantics are only built on the next frame after being enabled; without
    // this pump the guidelines would pass vacuously on an empty tree.
    await tester.pump();
    await expectLater(
      tester,
      meetsGuideline(TextContrastGuideline(skipLabels: skipLabels)),
    );
  } finally {
    handle.dispose();
  }
}

/// All three guidelines.
Future<void> expectAccessible(WidgetTester tester) async {
  await expectTapTargets(tester);
  await expectLabeledTapTargets(tester);
  await expectTextContrast(tester);
}
