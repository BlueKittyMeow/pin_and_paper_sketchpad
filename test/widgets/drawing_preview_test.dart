import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/rendering/stroke_painter.dart';
import 'package:pin_and_paper_sketchpad/sketchpad.dart';

/// A constant-width stroke along [pts] (no thinning/smoothing/streamline
/// so the painted geometry is predictable for pixel probes).
Stroke _line(
  List<Offset> pts, {
  Color color = const Color(0xFF2D2D2D),
  double size = 10,
  bool eraser = false,
}) =>
    Stroke(
      points: [for (final o in pts) StrokePoint(o.dx, o.dy, 0.5)],
      color: color,
      options: StrokeOptions(
        size: size,
        thinning: 0,
        smoothing: 0,
        streamline: 0,
      ),
      isEraser: eraser,
    );

/// Horizontal line across the middle of a 100x100 capture space.
List<Offset> get _midlinePts =>
    [for (var x = 10.0; x <= 90.0; x += 10.0) Offset(x, 50)];

Widget _host(Widget preview) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: preview),
    );

Finder get _previewBoundary => find.descendant(
      of: find.byType(DrawingPreview),
      matching: find.byType(RepaintBoundary),
    );

Future<ByteData> _renderedPixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _previewBoundary,
  );
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes;
  });
  return data!;
}

int _alphaAt(ByteData data, int width, int x, int y) =>
    data.getUint8((y * width + x) * 4 + 3);

int _channelAt(ByteData data, int width, int x, int y, int channel) =>
    data.getUint8((y * width + x) * 4 + channel);

/// A flat-color `ui.Image`, [w]x[h], for use as a [DrawingPreview.backdropImage]
/// probe — a real backdrop the multiply math can be checked against
/// without depending on any actual card-rendering package.
Future<ui.Image> _solidColorImage(Color color, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(w, h);
}

/// Reference channel-wise multiply, independent of [resolveStrokeColor]
/// (which is hardcoded to [kPaperReferenceColor]) — used to check
/// backdrop-aware compositing against an arbitrary backdrop color.
int _multiplyChannel(Color src, Color backdrop, int channel) {
  double component(Color c) => switch (channel) {
        0 => c.r,
        1 => c.g,
        _ => c.b,
      };
  return (component(src) * component(backdrop) * 255).round();
}

void main() {
  group('scale math', () {
    test('uniform 2x', () {
      expect(
        DrawingPreview.scaleFactors(
            const Size(220, 140), const Size(440, 280)),
        const Offset(2, 2),
      );
    });

    test('non-uniform axes scale independently', () {
      expect(
        DrawingPreview.scaleFactors(
            const Size(100, 200), const Size(50, 300)),
        const Offset(0.5, 1.5),
      );
    });
  });

  testWidgets('renders without the live painter, inside a RepaintBoundary',
      (tester) async {
    final stack = LayerStack(size: const Size(100, 100));
    stack.addStrokeToActiveLayer(_line(_midlinePts));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    expect(find.byType(DrawingCanvas), findsNothing);
    expect(_previewBoundary, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DrawingPreview),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('picture is recorded once per content change, not per frame',
      (tester) async {
    final stack = LayerStack(size: const Size(100, 100));
    stack.addStrokeToActiveLayer(_line(_midlinePts));

    Widget build() => _host(
          DrawingPreview(layerStack: stack, size: const Size(200, 200)),
        );

    CustomPaint paintWidget() => tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(DrawingPreview),
            matching: find.byType(CustomPaint),
          ),
        );

    await tester.pumpWidget(build());
    final picture1 = (paintWidget().painter as dynamic).picture;

    // Rebuild with unchanged content: same recorded picture is reused.
    await tester.pumpWidget(build());
    await tester.pumpWidget(build());
    final picture2 = (paintWidget().painter as dynamic).picture;
    expect(identical(picture1, picture2), isTrue);

    // Content change (revision bump): a new picture is recorded.
    stack.addStrokeToActiveLayer(
        _line(const [Offset(20, 20), Offset(40, 20), Offset(60, 20)]));
    await tester.pumpWidget(build());
    final picture3 = (paintWidget().painter as dynamic).picture;
    expect(identical(picture2, picture3), isFalse);
  });

  testWidgets('empty stack that gains content starts rendering it',
      (tester) async {
    final stack = LayerStack(size: const Size(100, 100));

    Widget build() => _host(
          DrawingPreview(layerStack: stack, size: const Size(200, 200)),
        );

    await tester.pumpWidget(build());
    expect(
      find.descendant(
        of: find.byType(DrawingPreview),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );

    stack.addStrokeToActiveLayer(_line(_midlinePts));
    await tester.pumpWidget(build());

    final pixels = await _renderedPixels(tester);
    expect(_alphaAt(pixels, 200, 100, 100), greaterThan(0));
  });

  testWidgets('empty stack renders nothing', (tester) async {
    final stack = LayerStack(size: const Size(100, 100));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    expect(
      find.descendant(
        of: find.byType(DrawingPreview),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    // The slot still occupies its target size.
    expect(tester.getSize(find.byType(DrawingPreview)), const Size(200, 200));
  });

  testWidgets('eraser-only content also renders nothing', (tester) async {
    final stack = LayerStack(size: const Size(100, 100));
    stack.addStrokeToActiveLayer(_line(_midlinePts, eraser: true));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    expect(
      find.descendant(
        of: find.byType(DrawingPreview),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('capture-space strokes are scaled to the target size',
      (tester) async {
    final stack = LayerStack(size: const Size(100, 100));
    stack.addStrokeToActiveLayer(_line(_midlinePts));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    final pixels = await _renderedPixels(tester);
    // Capture-space midline (y=50 of 100) lands at y=100 of 200.
    expect(_alphaAt(pixels, 200, 100, 100), greaterThan(0));
    expect(_alphaAt(pixels, 200, 60, 100), greaterThan(0));
    // Well off the scaled stroke (stroke half-width is 10px at 2x):
    expect(_alphaAt(pixels, 200, 100, 75), 0);
    expect(_alphaAt(pixels, 200, 4, 4), 0);
  });

  testWidgets('hairline strokes scaled down 4x still paint at the '
      'minimum width floor', (tester) async {
    // A 1px hairline in a 400x400 capture space rendered on a 100x100
    // target would paint at 0.25px — nearly invisible. The floor
    // guarantees ~0.75px of painted coverage.
    final stack = LayerStack(size: const Size(400, 400));
    stack.addStrokeToActiveLayer(_line(
      [for (var x = 40.0; x <= 360.0; x += 40.0) const Offset(0, 200) + Offset(x, 0)],
      size: 1.0,
    ));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(100, 100)),
    ));

    final pixels = await _renderedPixels(tester);
    // Total alpha coverage down the column crossing the line ~= painted
    // width in px * 255. Unfloored 0.25px would give ~64; the 0.75px
    // floor gives ~191. Assert comfortably above the unfloored value.
    var coverage = 0;
    for (var y = 40; y <= 60; y++) {
      coverage += _alphaAt(pixels, 100, 50, y);
    }
    expect(coverage, greaterThanOrEqualTo(150));
  });

  testWidgets('hidden layers are not rendered', (tester) async {
    final visibleLayer = DrawingLayer(id: 'a', name: 'A')
      ..addStroke(_line(_midlinePts));
    final hiddenLayer = DrawingLayer(id: 'b', name: 'B', visible: false)
      ..addStroke(_line(
          [for (var x = 10.0; x <= 90.0; x += 10.0) Offset(x, 20)]));
    final stack = LayerStack(
      layers: [visibleLayer, hiddenLayer],
      size: const Size(100, 100),
    );

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    final pixels = await _renderedPixels(tester);
    // Visible layer's stroke at capture y=50 → target y=100: painted.
    expect(_alphaAt(pixels, 200, 100, 100), greaterThan(0));
    // Hidden layer's stroke at capture y=20 → target y=40: absent.
    expect(_alphaAt(pixels, 200, 100, 40), 0);
  });

  testWidgets('layer opacity is honored', (tester) async {
    final layer = DrawingLayer(id: 'a', name: 'A', opacity: 0.5)
      ..addStroke(_line(_midlinePts));
    final stack = LayerStack(layers: [layer], size: const Size(100, 100));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    final pixels = await _renderedPixels(tester);
    final alpha = _alphaAt(pixels, 200, 100, 100);
    expect(alpha, greaterThan(100));
    expect(alpha, lessThan(160)); // ~128 for a 0.5-opacity layer
  });

  testWidgets('eraser strokes cut holes in their layer (BlendMode.dstOut)',
      (tester) async {
    final stack = LayerStack(size: const Size(100, 100));
    stack.addStrokeToActiveLayer(_line(_midlinePts));
    // Vertical eraser through the middle of the line.
    stack.addStrokeToActiveLayer(_line(
      [for (var y = 30.0; y <= 70.0; y += 10.0) Offset(50, y)],
      size: 20,
      eraser: true,
    ));

    await tester.pumpWidget(_host(
      DrawingPreview(layerStack: stack, size: const Size(200, 200)),
    ));

    final pixels = await _renderedPixels(tester);
    // Center of the line was erased (capture 50,50 → target 100,100).
    expect(_alphaAt(pixels, 200, 100, 100), 0);
    // The line survives outside the eraser's reach (capture 75,50).
    expect(_alphaAt(pixels, 200, 150, 100), greaterThan(0));
  });

  testWidgets('fromJson factory renders serialized format v1 directly',
      (tester) async {
    final source = LayerStack(size: const Size(100, 100));
    source.addStrokeToActiveLayer(_line(_midlinePts));
    final json = jsonEncode(source.toJson());

    await tester.pumpWidget(_host(
      DrawingPreview.fromJson(json, size: const Size(200, 200)),
    ));

    final pixels = await _renderedPixels(tester);
    expect(_alphaAt(pixels, 200, 100, 100), greaterThan(0));
  });

  group('non-additive layer compositing (owner decision, 2026-08-06)', () {
    testWidgets(
        'a multiply-blend layer stacked ABOVE another layer\'s ink no '
        'longer blends with it — only with the fixed paper reference',
        (tester) async {
      // Bottom layer: an opaque bright-green stroke covering the probe
      // region. Under the OLD live-canvas-blend behavior, a multiply
      // layer painted on top of this would visibly darken/tint toward
      // green. Under the fix, the top layer's color is precomputed
      // against kPaperReferenceColor alone — this stroke's presence (or
      // absence, or color) must make ZERO difference to the result.
      final bottom = DrawingLayer(id: 'bottom', name: 'Bottom')
        ..addStroke(_line(_midlinePts, color: const Color(0xFF00FF00), size: 30));
      // Top layer: multiply blend, opaque red stroke over the same
      // pixels.
      const red = Color(0xFFFF0000);
      final top = DrawingLayer(
        id: 'top',
        name: 'Top',
        blendMode: BlendMode.multiply,
      )..addStroke(_line(_midlinePts, color: red, size: 30));

      final stack = LayerStack(layers: [bottom, top], size: const Size(100, 100));

      await tester.pumpWidget(_host(
        DrawingPreview(layerStack: stack, size: const Size(100, 100)),
      ));

      final image = await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(_previewBoundary);
        return boundary.toImage();
      });
      final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
      image!.dispose();

      int channelAt(int x, int y, int channel) =>
          bytes!.getUint8((y * 100 + x) * 4 + channel);

      // Center of the probe region: fully covered by both strokes.
      const x = 50, y = 50;
      final resolved = resolveStrokeColor(red, BlendMode.multiply);
      expect(channelAt(x, y, 0), (resolved.r * 255).round()); // R
      expect(channelAt(x, y, 1), (resolved.g * 255).round()); // G
      expect(channelAt(x, y, 2), (resolved.b * 255).round()); // B
      // In particular: NOT green-tinted (the old, additive behavior
      // would have driven the green channel up from whatever's beneath
      // showing through the multiply).
      expect(channelAt(x, y, 1), lessThan(80));
    });

    testWidgets(
        'an existing saved drawing (format v1, blendMode "multiply") '
        'still loads and renders without throwing — no migration needed',
        (tester) async {
      // Hand-built JSON matching what a pre-fix save would have produced:
      // format v1 doesn't encode HOW a blend mode is applied, only which
      // one — so old rows are forward-compatible with the new
      // compositing by construction.
      final json = jsonEncode({
        'v': 1,
        'size': [100.0, 100.0],
        'activeLayer': 0,
        'layers': [
          {
            'id': 'color',
            'name': 'Color',
            'visible': true,
            'opacity': 1.0,
            'blendMode': 'multiply',
            'defaultOptions': StrokeOptions.watercolor.toJson(),
            'strokes': [
              _line(_midlinePts, color: const Color(0xFFC75B4A)).toJson(),
            ],
          },
        ],
      });

      await tester.pumpWidget(_host(
        DrawingPreview.fromJson(json, size: const Size(100, 100)),
      ));

      final pixels = await _renderedPixels(tester);
      expect(_alphaAt(pixels, 100, 50, 50), greaterThan(0));
    });
  });

  group('backdrop-aware multiply compositing (owner report 2026-08-06, '
      'fixed 2026-08-07)', () {
    testWidgets(
        'a multiply layer composites with a real multiply blend against a '
        'supplied backdropImage, not the flat paper reference',
        (tester) async {
      const red = Color(0xFFFF0000);
      // Distinct from kPaperReferenceColor, so a passing result proves the
      // real backdrop was used, not the 2026-08-06 flat-paper precompute.
      const backdropColor = Color(0xFF4080C0);

      final layer = DrawingLayer(id: 'marker', name: 'Marker', blendMode: BlendMode.multiply)
        ..addStroke(_line(_midlinePts, color: red, size: 30));
      final stack = LayerStack(layers: [layer], size: const Size(100, 100));
      final backdrop = await _solidColorImage(backdropColor, 100, 100);
      addTearDown(backdrop.dispose);

      await tester.pumpWidget(_host(
        DrawingPreview(
          layerStack: stack,
          size: const Size(100, 100),
          backdropImage: backdrop,
        ),
      ));

      final pixels = await _renderedPixels(tester);
      const x = 50, y = 50; // fully covered by the stroke

      expect(_channelAt(pixels, 100, x, y, 0),
          closeTo(_multiplyChannel(red, backdropColor, 0), 2));
      expect(_channelAt(pixels, 100, x, y, 1),
          closeTo(_multiplyChannel(red, backdropColor, 1), 2));
      expect(_channelAt(pixels, 100, x, y, 2),
          closeTo(_multiplyChannel(red, backdropColor, 2), 2));
      expect(_alphaAt(pixels, 100, x, y), 255);

      // Not the flat-paper precompute — proves the backdrop is what
      // actually drove the result.
      final flatPaper = resolveStrokeColor(red, BlendMode.multiply);
      final actualRed = _channelAt(pixels, 100, x, y, 0);
      expect(actualRed, isNot(closeTo((flatPaper.r * 255).round(), 2)));

      // Outside the stroke, nothing was drawn at all (DrawingPreview only
      // paints ink — the backdrop's own visible presence is the host's
      // job, same as before).
      expect(_alphaAt(pixels, 100, 5, 5), 0);
    });

    testWidgets(
        'a sibling layer\'s already-painted pixels are untouched by a '
        'multiply layer\'s backdrop compositing — only the paper/card '
        'behind is a blend source, never another layer',
        (tester) async {
      const backdropColor = Color(0xFF4080C0);
      const red = Color(0xFFFF0000);

      // Bottom layer: opaque bright-green stroke, srcOver, covering the
      // whole probe region.
      const green = Color(0xFF00FF00);
      final bottom = DrawingLayer(id: 'bottom', name: 'Bottom')
        ..addStroke(_line(_midlinePts, color: green, size: 30));
      // Top layer: multiply blend, red stroke over the SAME pixels.
      final top = DrawingLayer(id: 'top', name: 'Top', blendMode: BlendMode.multiply)
        ..addStroke(_line(_midlinePts, color: red, size: 30));

      final stack = LayerStack(layers: [bottom, top], size: const Size(100, 100));
      final backdrop = await _solidColorImage(backdropColor, 100, 100);
      addTearDown(backdrop.dispose);

      // Render once with the green bottom layer...
      await tester.pumpWidget(_host(
        DrawingPreview(
          layerStack: stack,
          size: const Size(100, 100),
          backdropImage: backdrop,
        ),
      ));
      final withGreenBottom = await _renderedPixels(tester);

      // ...and again with the bottom layer recolored to blue. If the top
      // (multiply) layer's result changes at all, it was blending against
      // the bottom layer instead of purely the backdrop.
      bottom.strokes.clear();
      bottom.addStroke(_line(_midlinePts, color: const Color(0xFF0000FF), size: 30));
      stack.markChanged();
      await tester.pumpWidget(_host(
        DrawingPreview(
          layerStack: stack,
          size: const Size(100, 100),
          backdropImage: backdrop,
        ),
      ));
      final withBlueBottom = await _renderedPixels(tester);

      const x = 50, y = 50;
      for (final channel in [0, 1, 2, 3]) {
        expect(
          _channelAt(withGreenBottom, 100, x, y, channel),
          _channelAt(withBlueBottom, 100, x, y, channel),
          reason: 'channel $channel changed when only the sibling layer '
              'did — the multiply layer leaked a blend with another '
              'layer instead of only the backdrop',
        );
      }

      // And the top layer's result is the real backdrop multiply, not a
      // pass-through of the bottom layer's own color (i.e. it's not just
      // "always shows the top color unmodified" — the backdrop math
      // actually ran).
      expect(_channelAt(withGreenBottom, 100, x, y, 0),
          closeTo(_multiplyChannel(red, backdropColor, 0), 2));
    });

    testWidgets(
        'without a backdropImage, multiply still falls back to the exact '
        '2026-08-06 flat-paper precompute (no regression for callers not '
        'yet updated)', (tester) async {
      const red = Color(0xFFFF0000);
      final layer = DrawingLayer(id: 'marker', name: 'Marker', blendMode: BlendMode.multiply)
        ..addStroke(_line(_midlinePts, color: red, size: 30));
      final stack = LayerStack(layers: [layer], size: const Size(100, 100));

      await tester.pumpWidget(_host(
        DrawingPreview(layerStack: stack, size: const Size(100, 100)),
      ));

      final pixels = await _renderedPixels(tester);
      final resolved = resolveStrokeColor(red, BlendMode.multiply);
      const x = 50, y = 50;
      expect(_channelAt(pixels, 100, x, y, 0), (resolved.r * 255).round());
      expect(_channelAt(pixels, 100, x, y, 1), (resolved.g * 255).round());
      expect(_channelAt(pixels, 100, x, y, 2), (resolved.b * 255).round());
    });
  });

  test('fromJson factory rejects unknown versions', () {
    final source = LayerStack(size: const Size(100, 100));
    source.addStrokeToActiveLayer(_line(_midlinePts));
    final bad = jsonEncode({...source.toJson(), 'v': 99});
    expect(
      () => DrawingPreview.fromJson(bad, size: const Size(200, 200)),
      throwsA(isA<FormatException>()),
    );
  });
}
