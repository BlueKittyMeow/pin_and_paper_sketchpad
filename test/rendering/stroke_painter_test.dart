import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/rendering/stroke_painter.dart';

void main() {
  group('effectiveStrokeSize (min painted width floor)', () {
    test('at scale 1, normal sizes pass through untouched', () {
      expect(effectiveStrokeSize(3.0, 1.0), 3.0);
      expect(effectiveStrokeSize(16.0, 1.0), 16.0);
    });

    test('at scale 1, sub-floor hairlines are floored', () {
      expect(effectiveStrokeSize(0.5, 1.0), kMinPaintedStrokeWidth);
    });

    test('a hairline scaled down 4x still paints at >= the floor', () {
      // 1.0 capture px at 0.25x would paint 0.25px — floored so that
      // painted width is exactly kMinPaintedStrokeWidth.
      final effective = effectiveStrokeSize(1.0, 0.25);
      expect(effective, kMinPaintedStrokeWidth / 0.25);
      expect(effective * 0.25, kMinPaintedStrokeWidth);
    });

    test('large strokes are unaffected by downscaling', () {
      // 16 capture px at 0.25x paints 4px — well above the floor.
      expect(effectiveStrokeSize(16.0, 0.25), 16.0);
    });

    test('upscaling never inflates sizes', () {
      expect(effectiveStrokeSize(2.0, 4.0), 2.0);
      expect(effectiveStrokeSize(0.5, 4.0), 0.5); // paints 2.0px, fine
    });

    test('non-positive scale is a no-op guard', () {
      expect(effectiveStrokeSize(2.0, 0.0), 2.0);
      expect(effectiveStrokeSize(2.0, -1.0), 2.0);
    });
  });
}
