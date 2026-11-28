// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2 text contrast, read from the rendered pixels.
///
/// This replaces Flutter's own `textContrastGuideline` (a
/// `@visibleForTesting` class we would have to subclass, with a lint
/// suppression, to exempt single nodes). It walks the same semantics tree and
/// uses the same thresholds (4.5:1, or 3:1 for large text), but reads the
/// pixels differently, because two things in Flutter's sampler misjudge real
/// text:
///
///  * It samples the text box **plus 4 px** on every side, so a neighbour
///    closer than that (a button, a spinner, a divider) is counted as text or
///    page colour.
///  * It takes the **most frequent** light and dark colours of the box. Thin
///    text (12 px strokes about a pixel wide) is mostly anti-aliasing blends
///    of ink and page, so the commonest "dark" colour is a grey that was
///    never painted as text.
///
/// Here the sample is exactly the text's paint box. The page colour is the
/// most frequent colour in it, and the ink is the colour farthest from it in
/// contrast (the ratio is symmetric, so dense bold text whose ink is the
/// commonest colour is judged the same way). A blend of ink and page can never be farther from the page than
/// the ink itself, so this cannot be fooled upwards by anti-aliasing: it
/// reports the contrast of the most contrasting colour actually painted in the
/// text's box (the glyph colour when any pixel is solid).
class TextContrastGuideline extends AccessibilityGuideline {
  /// Judges every text node except those whose label is in [skipLabels].
  const TextContrastGuideline({this.skipLabels = const {}});

  /// Exact semantics labels that are not judged.
  final Set<String> skipLabels;

  static const double _normalRatio = 4.5;
  static const double _largeRatio = 3.0;
  static const int _largeSize = 18;
  static const int _boldLargeSize = 14;
  static const double _defaultFontSize = 12;
  static const double _tolerance = -0.01;

  @override
  String get description => 'Text contrast should follow WCAG guidelines';

  @override
  Future<Evaluation> evaluate(WidgetTester tester) async {
    var result = const Evaluation.pass();
    for (final renderView in tester.binding.renderViews) {
      final layer = renderView.debugLayer! as OffsetLayer;
      final root = renderView.owner!.semanticsOwner!.rootSemanticsNode!;
      late ui.Image image;
      final data = await tester.binding.runAsync<ByteData?>(() async {
        // Same pixel ratio as the layer's last transform, or the dimensions
        // would not match.
        final ratio = 1 / renderView.flutterView.devicePixelRatio;
        image = await layer.toImage(renderView.paintBounds, pixelRatio: ratio);
        final bytes = await image.toByteData();
        image.dispose();
        return bytes;
      });
      result += await _node(root, tester, image, data!, renderView);
    }
    return result;
  }

  Future<Evaluation> _node(
    SemanticsNode node,
    WidgetTester tester,
    ui.Image image,
    ByteData bytes,
    RenderView renderView,
  ) async {
    var result = const Evaluation.pass();
    final disabled = node.flagsCollection.isEnabled == ui.Tristate.isFalse;
    if (node.isInvisible ||
        node.isMergedIntoParent ||
        node.flagsCollection.isHidden ||
        disabled) {
      return result;
    }
    final data = node.getSemanticsData();
    final children = <SemanticsNode>[];
    node.visitChildren((child) {
      children.add(child);
      return true;
    });
    for (final child in children) {
      result += await _node(child, tester, image, bytes, renderView);
    }
    final text = data.label.isEmpty ? data.value : data.label;
    if (data.flagsCollection.scopesRoute ||
        text.trim().isEmpty ||
        skipLabels.contains(data.label)) {
      return result;
    }
    for (final element in find.text(text).hitTestable().evaluate()) {
      result += _element(node, element, image, bytes, renderView);
    }
    return result;
  }

  Evaluation _element(
    SemanticsNode node,
    Element element,
    ui.Image image,
    ByteData bytes,
    RenderView renderView,
  ) {
    final box = element.renderObject;
    if (box is! RenderBox) {
      throw StateError('Unexpected renderObject type: $box');
    }
    // Elements are found by their text, and a screen can repeat a string (a
    // button's label and the status line that echoes it). The node that
    // really carries this element must be a judged one: a disabled control's
    // text is exempt, and must not be judged as another node's.
    for (RenderObject? r = box; r != null; r = r.parent) {
      final owner = r.debugSemantics;
      if (owner == null) continue;
      final disabled = owner.flagsCollection.isEnabled == ui.Tristate.isFalse;
      if (disabled || owner.flagsCollection.isHidden || owner.isInvisible) {
        return const Evaluation.pass();
      }
      break;
    }
    final global = box.getTransformTo(null);
    final sample = MatrixUtils.transformRect(global, box.paintBounds);

    // The semantics transform includes the root view's transform, which
    // `getTransformTo(null)` does not.
    final rootTransform = Matrix4.identity();
    renderView.applyPaintTransform(renderView.child!, rootTransform);
    rootTransform.multiply(global);
    final screenBounds = MatrixUtils.transformRect(
      rootTransform,
      box.paintBounds,
    );
    var nodeBounds = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final t = n.transform;
      if (t != null) nodeBounds = MatrixUtils.transformRect(t, nodeBounds);
    }
    final overlap = nodeBounds.intersect(screenBounds);
    if (overlap.width <= 0 || overlap.height <= 0) {
      // A different element with the same text, not this semantics node.
      return const Evaluation.pass();
    }

    final double? fontSize;
    final bool bold;
    final widget = element.widget;
    if (widget is Text) {
      final style = widget.style;
      final effective = style == null || style.inherit
          ? DefaultTextStyle.of(element).style.merge(style)
          : style;
      bold = effective.fontWeight == FontWeight.bold;
      fontSize = effective.fontSize;
    } else if (widget is EditableText) {
      bold = widget.style.fontWeight == FontWeight.bold;
      fontSize = widget.style.fontSize;
    } else {
      throw StateError('Unexpected widget type: ${widget.runtimeType}');
    }

    final pixels = _Pixels.sample(bytes, sample, image.width, image.height);
    if (pixels == null) return const Evaluation.pass(); // off screen
    final ratio = pixels.contrast();
    final target = _target(fontSize, bold: bold);
    if (ratio - target >= _tolerance) return const Evaluation.pass();
    return Evaluation.fail(
      '$node:\n'
      'Expected contrast ratio of at least $target '
      'but found ${ratio.toStringAsFixed(2)} '
      'for a font size of $fontSize.\n'
      'The sampled colors were:\n'
      'page - ${pixels.page}, ink - ${pixels.ink}',
    );
  }

  double _target(double? fontSize, {required bool bold}) {
    final size = fontSize ?? _defaultFontSize;
    if ((bold && size >= _boldLargeSize) || size >= _largeSize) {
      return _largeRatio;
    }
    return _normalRatio;
  }
}

/// The page colour and the ink colour of one text box.
class _Pixels {
  const _Pixels(this.page, this.ink);

  final Color page;
  final Color ink;

  static _Pixels? sample(ByteData data, Rect box, int width, int height) {
    final clipped = box.intersect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    if (clipped.width <= 0 || clipped.height <= 0) return null;
    final left = clipped.left.floor();
    final right = clipped.right.ceil();
    final top = clipped.top.floor();
    final bottom = clipped.bottom.ceil();
    if (right <= left || bottom <= top) return null;

    final all = <int, int>{};
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final rgba = data.getUint32((y * width + x) * 4);
        all.update(rgba, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final page = _color(_mode(all));
    var ink = page;
    var best = 1.0;
    for (final rgba in all.keys) {
      final color = _color(rgba);
      final r = _ratio(color, page);
      if (r > best) {
        best = r;
        ink = color;
      }
    }
    return _Pixels(page, ink);
  }

  double contrast() => _ratio(ink, page);

  static int _mode(Map<int, int> histogram) {
    var best = 0;
    var bestCount = -1;
    histogram.forEach((rgba, n) {
      if (n > bestCount) {
        best = rgba;
        bestCount = n;
      }
    });
    return best;
  }

  static Color _color(int rgba) =>
      Color((rgba << 24) | (rgba >> 8) & 0xFFFFFFFF);

  static double _ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}
