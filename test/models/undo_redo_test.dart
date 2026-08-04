import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/sketchpad.dart';

Stroke _stroke(double x) => Stroke(
      points: [StrokePoint(x, 10, 0.5), StrokePoint(x + 10, 10, 0.5)],
      color: const Color(0xFF2D2D2D),
      options: StrokeOptions.ink,
    );

void main() {
  group('cross-layer chronological undo/redo', () {
    test('fresh stack has nothing to undo or redo', () {
      final stack = LayerStack();
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(stack.undo(), isFalse);
      expect(stack.redo(), isFalse);
    });

    test('undo removes the most recent stroke regardless of the active '
        'layer', () {
      final stack = LayerStack(); // Color(0), Sketch(1), Ink(2 active)
      final sketchStroke = _stroke(10);
      final inkStroke = _stroke(50);

      stack.setActiveLayer(1);
      stack.addStrokeToActiveLayer(sketchStroke);
      stack.setActiveLayer(2);
      stack.addStrokeToActiveLayer(inkStroke);

      // Switch back to Sketch and undo: the *Ink* stroke (most recent
      // chronologically) is removed, not a Sketch one.
      stack.setActiveLayer(1);
      expect(stack.undo(), isTrue);
      expect(stack.layers[2].strokes, isEmpty);
      expect(stack.layers[1].strokes, [sketchStroke]);

      // Next undo steps back to the Sketch stroke.
      expect(stack.undo(), isTrue);
      expect(stack.layers[1].strokes, isEmpty);
      expect(stack.canUndo, isFalse);
    });

    test('redo restores strokes to their original layers in order', () {
      final stack = LayerStack();
      final sketchStroke = _stroke(10);
      final inkStroke = _stroke(50);

      stack.setActiveLayer(1);
      stack.addStrokeToActiveLayer(sketchStroke);
      stack.setActiveLayer(2);
      stack.addStrokeToActiveLayer(inkStroke);
      stack.undo();
      stack.undo();

      expect(stack.canRedo, isTrue);
      expect(stack.redo(), isTrue);
      expect(stack.layers[1].strokes, [sketchStroke]);
      expect(stack.layers[2].strokes, isEmpty);
      expect(stack.redo(), isTrue);
      expect(stack.layers[2].strokes, [inkStroke]);
      expect(stack.canRedo, isFalse);
      expect(stack.canUndo, isTrue);
    });

    test('a new stroke clears the redo history', () {
      final stack = LayerStack();
      stack.addStrokeToActiveLayer(_stroke(10));
      stack.undo();
      expect(stack.canRedo, isTrue);

      stack.addStrokeToActiveLayer(_stroke(50));
      expect(stack.canRedo, isFalse);
      expect(stack.redo(), isFalse);
    });

    test('revision bumps on undo and on redo, not on empty no-ops', () {
      final stack = LayerStack();
      stack.addStrokeToActiveLayer(_stroke(10));

      var revision = stack.revision;
      stack.undo();
      expect(stack.revision, greaterThan(revision));

      revision = stack.revision;
      stack.redo();
      expect(stack.revision, greaterThan(revision));

      revision = stack.revision;
      stack.redo(); // nothing to redo
      expect(stack.revision, revision);
      stack.undo();
      stack.undo(); // nothing left to undo
      expect(stack.revision, greaterThan(revision));
    });

    test('clearActiveLayer is one undoable batch: undo restores all '
        'strokes in order, redo re-clears', () {
      final stack = LayerStack();
      final a = _stroke(10);
      final b = _stroke(30);
      const eraser = Stroke(
        points: [StrokePoint(15, 10, 0.5), StrokePoint(25, 10, 0.5)],
        color: Color(0xFFFFFFFF),
        options: StrokeOptions(size: 12),
        isEraser: true,
      );
      stack.addStrokeToActiveLayer(a);
      stack.addStrokeToActiveLayer(eraser);
      stack.addStrokeToActiveLayer(b);

      stack.clearActiveLayer();
      expect(stack.activeLayer.strokes, isEmpty);

      // One undo restores the whole batch, preserving the eraser
      // interleave order.
      expect(stack.undo(), isTrue);
      expect(stack.activeLayer.strokes, [a, eraser, b]);

      // Redo re-clears in one step.
      expect(stack.redo(), isTrue);
      expect(stack.activeLayer.strokes, isEmpty);

      // And it stays fully reversible.
      expect(stack.undo(), isTrue);
      expect(stack.activeLayer.strokes, [a, eraser, b]);
      expect(stack.undo(), isTrue); // undoes stroke b
      expect(stack.activeLayer.strokes, [a, eraser]);
    });

    test('clearing an empty layer is a no-op (no history entry, no '
        'revision bump)', () {
      final stack = LayerStack();
      final revision = stack.revision;
      stack.clearActiveLayer();
      expect(stack.canUndo, isFalse);
      expect(stack.revision, revision);
    });

    test('clear of one layer undoes independently of strokes on others',
        () {
      final stack = LayerStack();
      final sketchStroke = _stroke(10);
      final inkStroke = _stroke(50);

      stack.setActiveLayer(1);
      stack.addStrokeToActiveLayer(sketchStroke);
      stack.clearActiveLayer();
      stack.setActiveLayer(2);
      stack.addStrokeToActiveLayer(inkStroke);

      // Undo the ink stroke, then the sketch clear.
      stack.undo();
      expect(stack.layers[2].strokes, isEmpty);
      stack.undo();
      expect(stack.layers[1].strokes, [sketchStroke]);
    });

    test('strokes restored via fromJson are not undoable', () {
      final source = LayerStack(size: const Size(100, 100));
      source.addStrokeToActiveLayer(_stroke(10));
      final restored = LayerStack.fromJson(source.toJson());
      expect(restored.canUndo, isFalse);
      expect(restored.undo(), isFalse);
      expect(restored.activeLayer.strokes, hasLength(1));
    });
  });
}
