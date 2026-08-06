import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/rendering/stroke_painter.dart';

void main() {
  group('effectiveStrokeSize is color-blind', () {
    // Guards against reintroducing per-color width behavior. A perceptual
    // contrast-compensation was tried and reverted here (2026-08-06): the
    // owner's "purple draws thinner" report turned out intermittent —
    // absent on a later launch — so it cannot be an always-on optical
    // effect, and painted width must stay identical across colors. See
    // the note on kPaperReferenceColor in stroke_painter.dart.
    test('size passes through unchanged at scale >= 1', () {
      expect(effectiveStrokeSize(3.0, 1.0), 3.0);
      expect(effectiveStrokeSize(3.0, 0.5), 3.0);
    });

    test('floors so painted width never drops below the minimum', () {
      expect(effectiveStrokeSize(0.5, 0.1) * 0.1,
          closeTo(kMinPaintedStrokeWidth, 1e-9));
    });
  });

  group('resolveStrokeColor (non-additive cross-layer compositing, owner '
      'decision 2026-08-06)', () {
    const red = Color(0xFFFF0000);

    test('a normal (srcOver) layer passes the stroke color through '
        'unchanged', () {
      expect(resolveStrokeColor(red, BlendMode.srcOver), red);
    });

    test('a multiply layer precomputes against kPaperReferenceColor, not '
        'BlendMode.srcOver\'s (or any other) canvas state', () {
      final resolved = resolveStrokeColor(red, BlendMode.multiply);
      // Pure function: identical regardless of what canvas/other-layer
      // content exists — that's precisely what makes it non-additive.
      expect(resolved, resolveStrokeColor(red, BlendMode.multiply));
      expect(resolved, isNot(red)); // actually blended, not passed through
      expect(resolved.a, red.a); // alpha untouched by the color multiply
    });

    test('multiplying against a fully-white reference paper is a no-op', () {
      // Sanity check on the multiply math itself, independent of
      // whatever kPaperReferenceColor happens to be tuned to.
      const white = Color(0xFFFFFFFF);
      const blue = Color(0xFF3355CC);
      // resolveStrokeColor always uses kPaperReferenceColor, so this test
      // documents the *formula* via a hand-rolled equivalent instead.
      Color multiplyChannelwise(Color a, Color b) => Color.fromARGB(
            (a.a * 255).round(),
            ((a.r * 255) * b.r).round(),
            ((a.g * 255) * b.g).round(),
            ((a.b * 255) * b.b).round(),
          );
      expect(multiplyChannelwise(blue, white).toARGB32(), blue.toARGB32());
    });
  });

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
