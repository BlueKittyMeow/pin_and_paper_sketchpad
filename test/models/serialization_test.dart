import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/sketchpad.dart';

LayerStack _sampleStack() {
  final inkLayer = DrawingLayer(
    id: 'ink_test',
    name: 'Ink',
    blendMode: BlendMode.srcOver,
    defaultOptions: StrokeOptions.ink,
    strokes: [
      const Stroke(
        points: [
          StrokePoint(10.0, 20.0, 0.5),
          StrokePoint(30.5, 40.25, 0.75),
          StrokePoint(50.0, 60.0, 1.0),
        ],
        color: Color(0xFF2D2D2D),
        options: StrokeOptions.ink,
      ),
      const Stroke(
        points: [
          StrokePoint(15.0, 25.0, 0.5),
          StrokePoint(35.0, 45.0, 0.5),
        ],
        color: Color(0xFFFFFFFF),
        options: StrokeOptions(size: 12.0),
        isEraser: true,
      ),
    ],
  );
  final colorLayer = DrawingLayer(
    id: 'color_test',
    name: 'Color',
    visible: false,
    opacity: 0.6,
    blendMode: BlendMode.multiply,
    defaultOptions: StrokeOptions.watercolor,
    strokes: [
      const Stroke(
        points: [StrokePoint(5.0, 5.0, 0.3), StrokePoint(6.0, 6.0, 0.4)],
        color: Color(0xFFC75B4A),
        options: StrokeOptions.watercolor,
      ),
    ],
  );
  return LayerStack(
    layers: [colorLayer, inkLayer],
    size: const Size(880, 560),
  );
}

void main() {
  group('LayerStack constructor', () {
    test('defaults to three layers with the top layer active', () {
      final stack = LayerStack();
      expect(stack.layers.length, 3);
      expect(stack.activeLayerIndex, 2);
      expect(stack.activeLayer.name, 'Ink');
    });

    test('single custom layer is valid and active', () {
      final stack = LayerStack(layers: [DrawingLayer.ink()]);
      expect(stack.activeLayerIndex, 0);
      // Regression: this used to throw RangeError (hardcoded index 2).
      expect(stack.activeLayer.name, 'Ink');
    });

    test('two custom layers default to the top layer', () {
      final stack = LayerStack(
        layers: [DrawingLayer.color(), DrawingLayer.ink()],
      );
      expect(stack.activeLayerIndex, 1);
      expect(stack.activeLayer.name, 'Ink');
    });

    test('empty layer list is rejected', () {
      expect(() => LayerStack(layers: []), throwsArgumentError);
    });
  });

  group('Serialization format v1', () {
    test('top-level shape is {"v":1,"size":[w,h],"layers":[...]}', () {
      final json = _sampleStack().toJson();
      expect(json['v'], 1);
      expect(json['size'], [880.0, 560.0]);
      expect(json['layers'], isA<List<dynamic>>());
      expect((json['layers'] as List).length, 2);
    });

    test('round-trip preserves layers, strokes, options, and flags', () {
      final original = _sampleStack();
      final restored = LayerStack.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.size, const Size(880, 560));
      expect(restored.layers.length, original.layers.length);
      expect(restored.activeLayerIndex, original.activeLayerIndex);

      for (var i = 0; i < original.layers.length; i++) {
        final a = original.layers[i];
        final b = restored.layers[i];
        expect(b.id, a.id);
        expect(b.name, a.name);
        expect(b.visible, a.visible);
        expect(b.opacity, a.opacity);
        expect(b.blendMode, a.blendMode);
        expect(b.defaultOptions, a.defaultOptions);
        expect(b.strokes.length, a.strokes.length);
        for (var j = 0; j < a.strokes.length; j++) {
          expect(b.strokes[j].color, a.strokes[j].color);
          expect(b.strokes[j].isEraser, a.strokes[j].isEraser);
          expect(b.strokes[j].options, a.strokes[j].options);
          expect(b.strokes[j].points, a.strokes[j].points);
        }
      }

      // Second-generation serialization must be byte-identical.
      expect(jsonEncode(restored.toJson()), jsonEncode(original.toJson()));
    });

    test('eraser flag survives round-trip', () {
      final restored = LayerStack.fromJson(_sampleStack().toJson());
      final inkLayer = restored.layers[1];
      expect(inkLayer.strokes[0].isEraser, isFalse);
      expect(inkLayer.strokes[1].isEraser, isTrue);
    });

    test('points serialize as [x,y,p] triples rounded to 2 decimals', () {
      final stack = LayerStack(
        layers: [
          DrawingLayer(
            id: 'l',
            name: 'L',
            strokes: [
              const Stroke(
                points: [StrokePoint(10.123456, 20.987654, 0.333333)],
                color: Color(0xFF000000),
                options: StrokeOptions.ink,
              ),
            ],
          ),
        ],
        size: const Size(220, 140),
      );
      final json = stack.toJson();
      final points =
          ((json['layers'] as List)[0] as Map)['strokes'][0]['points'] as List;
      expect(points[0], [10.12, 20.99, 0.33]);
    });

    test('enums serialize by name', () {
      final json = _sampleStack().toJson();
      final layers = json['layers'] as List;
      expect((layers[0] as Map)['blendMode'], 'multiply');
      expect((layers[1] as Map)['blendMode'], 'srcOver');
    });

    test('toJson without a capture size throws StateError', () {
      final stack = LayerStack();
      expect(stack.toJson, throwsStateError);
    });

    test('fromJson rejects unknown versions with a clear error', () {
      final good = _sampleStack().toJson();
      expect(
        () => LayerStack.fromJson({...good, 'v': 2}),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('version'),
        )),
      );
      expect(
        () => LayerStack.fromJson({...good}..remove('v')),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson rejects a missing size field', () {
      final good = _sampleStack().toJson();
      expect(
        () => LayerStack.fromJson({...good}..remove('size')),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('size'),
        )),
      );
    });

    test('fromJson rejects unknown blend mode names', () {
      final good = _sampleStack().toJson();
      final layers = (good['layers'] as List).cast<Map<String, dynamic>>();
      layers[0] = {...layers[0], 'blendMode': 'notABlendMode'};
      expect(
        () => LayerStack.fromJson({...good, 'layers': layers}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson rejects an empty layers list', () {
      expect(
        () => LayerStack.fromJson({
          'v': 1,
          'size': [220.0, 140.0],
          'layers': <dynamic>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
