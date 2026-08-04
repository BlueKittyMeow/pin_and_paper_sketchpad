import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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
