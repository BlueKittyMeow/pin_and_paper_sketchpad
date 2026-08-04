import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/sketchpad.dart';

Widget _buildApp(LayerStack stack) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: DrawingCanvas(
              layerStack: stack,
              currentColor: const Color(0xFF2D2D2D),
              strokeOptions: StrokeOptions.ink,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a second touch pointer cannot interleave points into an '
      'in-progress stylus stroke', (tester) async {
    final stack = LayerStack();
    await tester.pumpWidget(_buildApp(stack));
    final center = tester.getCenter(find.byType(DrawingCanvas));

    final stylus =
        await tester.createGesture(kind: PointerDeviceKind.stylus);
    await stylus.down(center);
    await tester.pump();

    // Palm/second finger lands far away while the stylus is drawing.
    final touch = await tester.createGesture();
    await touch.down(center + const Offset(60, 60));
    await touch.moveBy(const Offset(10, 10));
    await tester.pump();

    await stylus.moveTo(center + const Offset(20, 0));
    await stylus.moveTo(center + const Offset(40, 0));
    await tester.pump();

    await touch.up();
    await stylus.up();
    await tester.pump();

    expect(stack.activeLayer.strokes, hasLength(1));
    final points = stack.activeLayer.strokes.single.points;
    expect(points, hasLength(3));
    // All points lie on the stylus's horizontal path — no touch points
    // (which were offset by +60 in y) leaked in.
    for (final p in points) {
      expect(p.y, closeTo(150.0, 0.01));
    }
    expect(points.map((p) => p.x), [150.0, 170.0, 190.0]);
  });

  testWidgets('stylus-down cancels an in-progress touch stroke '
      '(palm rejection)', (tester) async {
    final stack = LayerStack();
    await tester.pumpWidget(_buildApp(stack));
    final center = tester.getCenter(find.byType(DrawingCanvas));

    final touch = await tester.createGesture();
    await touch.down(center);
    await touch.moveBy(const Offset(10, 0));
    await tester.pump();

    final stylus =
        await tester.createGesture(kind: PointerDeviceKind.stylus);
    await stylus.down(center + const Offset(0, 40));
    await tester.pump();

    // Touch keeps wandering — must be ignored now.
    await touch.moveBy(const Offset(30, 0));
    await tester.pump();

    await stylus.moveBy(const Offset(0, 20));
    await stylus.up();
    await touch.up();
    await tester.pump();

    // Only the stylus stroke was committed; the touch stroke was discarded.
    expect(stack.activeLayer.strokes, hasLength(1));
    final points = stack.activeLayer.strokes.single.points;
    expect(points, hasLength(2));
    expect(points.map((p) => p.y), [190.0, 210.0]);
  });

  testWidgets('onPointerCancel discards the in-progress stroke',
      (tester) async {
    final stack = LayerStack();
    await tester.pumpWidget(_buildApp(stack));
    final center = tester.getCenter(find.byType(DrawingCanvas));

    final gesture = await tester.createGesture();
    await gesture.down(center);
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(stack.activeLayer.strokes, isEmpty);

    // The canvas recovers: a fresh stroke still works after the cancel.
    final next = await tester.createGesture();
    await next.down(center);
    await next.moveBy(const Offset(15, 0));
    await next.up();
    await tester.pump();

    expect(stack.activeLayer.strokes, hasLength(1));
  });

  testWidgets('real stylus pressure of 1.0 is preserved, not snapped to 0.5',
      (tester) async {
    final stack = LayerStack();
    await tester.pumpWidget(_buildApp(stack));
    final center = tester.getCenter(find.byType(DrawingCanvas));

    // Test stylus events report pressure 1.0 (max press).
    final stylus =
        await tester.createGesture(kind: PointerDeviceKind.stylus);
    await stylus.down(center);
    await stylus.moveBy(const Offset(10, 0));
    await stylus.up();
    await tester.pump();

    final points = stack.activeLayer.strokes.single.points;
    expect(points, isNotEmpty);
    for (final p in points) {
      expect(p.pressure, 1.0);
    }
  });

  testWidgets('touch input gets the neutral 0.5 pressure default',
      (tester) async {
    final stack = LayerStack();
    await tester.pumpWidget(_buildApp(stack));
    final center = tester.getCenter(find.byType(DrawingCanvas));

    final touch = await tester.createGesture();
    await touch.down(center);
    await touch.moveBy(const Offset(10, 0));
    await touch.up();
    await tester.pump();

    final points = stack.activeLayer.strokes.single.points;
    for (final p in points) {
      expect(p.pressure, 0.5);
    }
  });

  testWidgets('strokes land on the active layer and respect the eraser flag',
      (tester) async {
    final stack = LayerStack();
    stack.setActiveLayer(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: DrawingCanvas(
                layerStack: stack,
                currentColor: const Color(0xFF2D2D2D),
                strokeOptions: StrokeOptions.watercolor,
                isEraserActive: true,
              ),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(DrawingCanvas));

    final touch = await tester.createGesture();
    await touch.down(center);
    await touch.moveBy(const Offset(10, 0));
    await touch.up();
    await tester.pump();

    expect(stack.layers[0].strokes, hasLength(1));
    expect(stack.layers[1].strokes, isEmpty);
    expect(stack.layers[2].strokes, isEmpty);
    expect(stack.layers[0].strokes.single.isEraser, isTrue);
    expect(
        stack.layers[0].strokes.single.options, StrokeOptions.watercolor);
  });
}
