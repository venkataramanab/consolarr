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
/// most frequent colour in it. The other pixels are split by whether they are
/// lighter or darker than the page, and only the larger side is the text: a
/// stray mark on the other side of the page (an underline in another colour, a
/// cursor, a lone dot) is not what is being read. The ink is then the 90th
/// percentile of those pixels' contrast with the page, so a colour needs real
/// coverage (at least a tenth of the text's pixels) to count: one dark pixel,
/// a one-letter span or a hairline cannot lift the result, and the caret of a
/// focused field is left out of the sample. Anti-aliasing blends are never
/// farther from the page than the ink, so this cannot be fooled upwards by
/// them either.
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
    final Color? declared;
    final widget = element.widget;
    if (widget is Text) {
      final style = widget.style;
      final effective = style == null || style.inherit
          ? DefaultTextStyle.of(element).style.merge(style)
          : style;
      final root = widget.textSpan?.style;
      final painted = root == null ? effective : effective.merge(root);
      bold = painted.fontWeight == FontWeight.bold;
      fontSize = painted.fontSize;
      declared = painted.color;
    } else if (widget is EditableText) {
      bold = widget.style.fontWeight == FontWeight.bold;
      fontSize = widget.style.fontSize;
      declared = widget.style.color;
    } else {
      throw StateError('Unexpected widget type: ${widget.runtimeType}');
    }

    final pixels = _Pixels.sample(
      bytes,
      sample,
      image.width,
      image.height,
      skip: _caret(box, global),
      declared: declared,
    );
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

  /// The caret of a focused field, in image pixels, or null. A cursor is
  /// painted in its own colour and blinks; it is not the text.
  Rect? _caret(RenderBox box, Matrix4 global) {
    RenderEditable? editable;
    void find(RenderObject o) {
      if (editable != null) return;
      if (o is RenderEditable) {
        editable = o;
        return;
      }
      o.visitChildren(find);
    }

    find(box);
    final e = editable;
    if (e == null || !e.hasFocus) return null;
    final selection = e.selection;
    if (selection == null || !selection.isValid) return null;
    final caret = e.getLocalRectForCaret(
      TextPosition(offset: selection.extentOffset),
    );
    final toScreen = e.getTransformTo(null);
    return MatrixUtils.transformRect(toScreen, caret).inflate(1);
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

  static _Pixels? sample(
    ByteData data,
    Rect box,
    int width,
    int height, {
    Rect? skip,
    Color? declared,
  }) {
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
        if (skip != null && skip.contains(Offset(x + 0.5, y + 0.5))) continue;
        final rgba = data.getUint32((y * width + x) * 4);
        all.update(rgba, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    if (all.isEmpty) return null;
    final page = _color(_mode(all));
    final pageLuminance = page.computeLuminance();

    // Pixels lighter than the page and pixels darker than it; the larger
    // side is the text.
    final lighter = <_Weighted>[];
    final darker = <_Weighted>[];
    var lighterCount = 0;
    var darkerCount = 0;
    for (final entry in all.entries) {
      final color = _color(entry.key);
      final luminance = color.computeLuminance();
      final ratio = _ratio(color, page);
      // A faint shadow or gradient is not a mark: it must not count as one.
      if (ratio < _visible) continue;
      final w = _Weighted(color, ratio, entry.value);
      if (luminance > pageLuminance) {
        lighter.add(w);
        lighterCount += entry.value;
      } else {
        darker.add(w);
        darkerCount += entry.value;
      }
    }
    // The side the text's declared colour lies on; when it says nothing (no
    // colour, or the same luminance as the page) the side with more pixels.
    var useLighter = lighterCount > darkerCount;
    if (declared != null) {
      final d = declared.computeLuminance() - pageLuminance;
      if (d.abs() > 1e-3) useLighter = d > 0;
    }
    final side = useLighter ? lighter : darker;
    final total = useLighter ? lighterCount : darkerCount;
    if (total == 0) return _Pixels(page, page);
    side.sort((a, b) => a.ratio.compareTo(b.ratio));
    final rank = ((total - 1) * _percentile).floor();
    var seen = 0;
    var ink = side.last.color;
    for (final w in side) {
      seen += w.count;
      if (seen > rank) {
        ink = w.color;
        break;
      }
    }
    return _Pixels(page, ink);
  }

  static const double _percentile = 0.9;

  /// Below this ratio a pixel is indistinguishable from the page.
  static const double _visible = 1.1;

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

class _Weighted {
  const _Weighted(this.color, this.ratio, this.count);

  final Color color;
  final double ratio;
  final int count;
}
