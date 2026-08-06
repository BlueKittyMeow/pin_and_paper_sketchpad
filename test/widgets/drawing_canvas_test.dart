import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

Widget _sizedApp(LayerStack stack, double width, double height) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
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
  group('capture-size stamping', () {
    testWidgets('a fresh LayerStack gets its size stamped from layout, '
        'so toJson works', (tester) async {
      final stack = LayerStack();
      expect(stack.size, isNull);

      await tester.pumpWidget(_buildApp(stack));

      expect(stack.size, const Size(300, 300));
      expect(stack.toJson()['size'], [300.0, 300.0]);
    });

    testWidgets('an explicitly set size is never overwritten',
        (tester) async {
      final stack = LayerStack(size: const Size(880, 560));

      await tester.pumpWidget(_buildApp(stack));

      expect(stack.size, const Size(880, 560));
    });

    testWidgets('auto-stamped size follows re-layout while empty, then '
        'freezes once a stroke lands', (tester) async {
      final stack = LayerStack();
      await tester.pumpWidget(_sizedApp(stack, 300, 300));
      expect(stack.size, const Size(300, 300));

      // Still empty: a resize re-stamps the capture space.
      await tester.pumpWidget(_sizedApp(stack, 200, 250));
      expect(stack.size, const Size(200, 250));

      final touch = await tester.createGesture();
      await touch.down(tester.getCenter(find.byType(DrawingCanvas)));
      await touch.moveBy(const Offset(10, 0));
      await touch.up();
      await tester.pump();
      expect(stack.activeLayer.strokes, hasLength(1));

      // With content, the capture space is frozen.
      await tester.pumpWidget(_sizedApp(stack, 300, 300));
      expect(stack.size, const Size(200, 250));
    });
  });

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

  group('DrawingCanvasController (pinch-to-zoom support, 2026-08-06)', () {
    testWidgets(
        'cancelActiveStroke discards the wet stroke without touching the '
        'raw pointer, so further moves for that pointer are ignored',
        (tester) async {
      final stack = LayerStack();
      final controller = DrawingCanvasController();
      addTearDown(controller.dispose);
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
                  strokeOptions: StrokeOptions.ink,
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(DrawingCanvas));

      final gesture = await tester.createGesture();
      await gesture.down(center);
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();

      // A host (e.g. a pinch-zoom gesture starting) discards the wet
      // stroke via the controller — NOT GestureBinding.cancelPointer.
      controller.cancelActiveStroke();
      await tester.pump();

      // The pointer is still "live" from Flutter's perspective (never
      // cancelled at the binding level) — further moves for it must be
      // silently ignored by the canvas, not accumulated into a new
      // stroke.
      await gesture.moveBy(const Offset(50, 50));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(stack.activeLayer.strokes, isEmpty);

      // The canvas recovers: a fresh stroke still works afterward.
      final next = await tester.createGesture();
      await next.down(center);
      await next.moveBy(const Offset(15, 0));
      await next.up();
      await tester.pump();
      expect(stack.activeLayer.strokes, hasLength(1));
    });

    testWidgets('a controller with no in-progress stroke is a harmless '
        'no-op', (tester) async {
      final stack = LayerStack();
      final controller = DrawingCanvasController();
      addTearDown(controller.dispose);
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
                  strokeOptions: StrokeOptions.ink,
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );

      expect(() => controller.cancelActiveStroke(), returnsNormally);
      await tester.pump();
      expect(stack.activeLayer.strokes, isEmpty);
    });
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

  group('baked committed strokes', () {
    /// The baked per-layer pictures list held by the canvas's painter.
    /// A re-bake always produces a new list, so list identity proves
    /// whether committed strokes were re-recorded.
    List<Object?> bakedPictures(WidgetTester tester) {
      final paints = tester.widgetList<CustomPaint>(find.descendant(
        of: find.byType(DrawingCanvas),
        matching: find.byType(CustomPaint),
      ));
      for (final paint in paints) {
        final painter = paint.painter;
        if (painter != null &&
            painter.runtimeType.toString() == '_DrawingPainter') {
          return (painter as dynamic).bakedLayerPictures as List<Object?>;
        }
      }
      fail('DrawingCanvas painter not found');
    }

    testWidgets('are not re-recorded while only the in-progress stroke '
        'changes', (tester) async {
      final stack = LayerStack();
      await tester.pumpWidget(_buildApp(stack));
      final center = tester.getCenter(find.byType(DrawingCanvas));

      // Commit one stroke so there is baked content.
      final first = await tester.createGesture();
      await first.down(center);
      await first.moveBy(const Offset(20, 0));
      await first.up();
      await tester.pump();
      final afterCommit = bakedPictures(tester);

      // Draw a second stroke: every pointer-move frame must reuse the
      // same baked pictures (no committed-stroke re-tessellation).
      final gesture = await tester.createGesture();
      await gesture.down(center + const Offset(0, 30));
      await tester.pump();
      expect(identical(bakedPictures(tester), afterCommit), isTrue);
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(identical(bakedPictures(tester), afterCommit), isTrue);
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      final duringStroke = bakedPictures(tester);
      expect(identical(duringStroke, afterCommit), isTrue);

      // Committing the stroke re-bakes.
      await gesture.up();
      await tester.pump();
      expect(identical(bakedPictures(tester), duringStroke), isFalse);
      expect(stack.activeLayer.strokes, hasLength(2));
    });

    testWidgets('baked compositing still paints committed and live '
        'strokes', (tester) async {
      final stack = LayerStack();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              child: SizedBox(
                width: 300,
                height: 300,
                child: DrawingCanvas(
                  layerStack: stack,
                  currentColor: const Color(0xFF2D2D2D),
                  strokeOptions: const StrokeOptions(
                    size: 10,
                    thinning: 0,
                    smoothing: 0,
                    streamline: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(DrawingCanvas));

      Future<int> alphaAtLocal(int x, int y) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).last);
        final data = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return bytes;
        });
        return data!.getUint8((y * 300 + x) * 4 + 3);
      }

      // Live: mid-gesture, the in-progress stroke is visible.
      final gesture = await tester.createGesture();
      await gesture.down(center + const Offset(-30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(await alphaAtLocal(150, 150), greaterThan(0));

      // Committed: after pointer-up the stroke replays from the baked
      // pictures and stays visible.
      await gesture.up();
      await tester.pump();
      expect(stack.activeLayer.strokes, hasLength(1));
      expect(await alphaAtLocal(150, 150), greaterThan(0));
      // Off-stroke stays clear.
      expect(await alphaAtLocal(150, 240), 0);
    });
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
