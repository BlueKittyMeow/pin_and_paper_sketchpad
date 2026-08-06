import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../models/layer.dart';
import '../models/stroke.dart';

/// Shared layer/stroke painting used by both the live editor
/// (`DrawingCanvas`) and the read-only `DrawingPreview`, so saved
/// drawings replay exactly like they looked in the editor (same
/// saveLayer/opacity/blend/eraser semantics).
///
/// Minimum painted stroke width, in logical pixels at the final painted
/// size. Prevents fine strokes from thinning into near-invisibility when
/// a capture-space drawing is scaled far down (e.g. an 880x560 editor
/// drawing replayed on a 220x140 card, or further shrunk by desk zoom).
const double kMinPaintedStrokeWidth = 0.75;

/// Reference "paper" tone for [resolveStrokeColor]'s multiply baking.
/// Matches `AppTheme.creamPaper` / the toolbar's cream chrome in the host
/// app, but the sketchpad module doesn't depend on the app's theme, so
/// it's re-declared here as the module's own constant.
///
/// NOTE on the "purple marker draws thinner" owner report (2026-08-05):
/// stroke geometry is provably color-uniform — every color tessellates
/// through identical perfect_freehand geometry at identical
/// StrokeOptions.size, with no per-color width/opacity field anywhere in
/// the pipeline. A perceptual-contrast width compensation was tried here
/// and REVERTED (owner disproved the "optical illusion" diagnosis: the
/// thinness was real but intermittent — absent on a later launch —
/// which an always-on optical effect cannot be). The bug is therefore
/// state-dependent and still at large; the toolbar's size readout row
/// (added 2026-08-06) doubles as the diagnostic for next sighting: if
/// purple draws thin while the readout shows the normal size, the fault
/// is below the options layer; if the readout itself is small, stale
/// StrokeOptions state is the culprit.
const Color kPaperReferenceColor = Color(0xFFF5F1E8);

/// Capture-space stroke size floored so that after multiplying by
/// [scale] (capture -> painted) the painted width is at least
/// [kMinPaintedStrokeWidth]. At scale >= 1, normal sizes pass through
/// untouched.
double effectiveStrokeSize(double size, double scale) {
  if (scale <= 0) return size;
  final floor = kMinPaintedStrokeWidth / scale;
  return size < floor ? floor : size;
}

// -- Non-additive layer compositing (owner decision, 2026-08-06) -----------
//
// Previously a layer with BlendMode.multiply (the toolbar's "Blend" switch)
// composited live against the real canvas — the paper backdrop image AND
// whatever any other layer had already painted beneath it, in stacking
// order. That let a multiply touch-up stroke on one layer visually muddy
// or darken ink already committed on a DIFFERENT layer, fighting attempts
// to color-match a correction against the original line.
//
// Fix: multiply is now precomputed per-stroke against the fixed
// [kPaperReferenceColor] (see [resolveStrokeColor]) instead of applied as
// a live canvas blend. The layer is then always composited onto the
// canvas with plain BlendMode.srcOver (see [paintLayerStack]). A
// multiply-blend layer's ink still "blends with the paper" — it's
// darkened/muted exactly as before — but it can never again interact with
// what's on any other layer, because by the time it reaches the shared
// canvas its color is already a finished, self-contained RGBA value.
//
// This is a pure rendering change: [DrawingLayer.blendMode] is still
// stored and serialized exactly as before (format v1 is untouched), so
// existing saved drawings need no migration — they render as
// multiply-precomputed-against-paper for any layer already saved as
// BlendMode.multiply, which is the intended fix, not a regression.

/// Resolve the paint color a stroke should actually use: [strokeColor]
/// unchanged for a normal (srcOver) layer, or [strokeColor] precomputed
/// (channel-wise) against [kPaperReferenceColor] for a multiply layer.
/// Centralizing the blend HERE — at paint-color resolution — rather than
/// leaving it as a canvas-level `saveLayer` blend is what guarantees a
/// multiply layer's ink blends only with the paper, never with another
/// layer's strokes. See the section comment above for the "why".
Color resolveStrokeColor(Color strokeColor, BlendMode layerBlendMode) {
  if (layerBlendMode != BlendMode.multiply) return strokeColor;
  const paper = kPaperReferenceColor;
  return Color.fromARGB(
    (strokeColor.a * 255).round(),
    ((strokeColor.r * 255) * (paper.r)).round(),
    ((strokeColor.g * 255) * (paper.g)).round(),
    ((strokeColor.b * 255) * (paper.b)).round(),
  );
}

/// [bounds] is the capture-space rect used for each layer's `saveLayer`.
/// The optional in-progress stroke is drawn on top of the active layer's
/// committed strokes (only the live editor passes one).
///
/// [scale] is the capture-space -> painted-size factor the caller will
/// apply around this call (e.g. `DrawingPreview`'s `canvas.scale`); it
/// is used only to enforce [kMinPaintedStrokeWidth] on downscaled
/// strokes.
///
/// [bakedLayerPictures], when provided, must run parallel to
/// `layerStack.layers`: each entry is a pre-recorded picture of that
/// layer's committed strokes (see `DrawingCanvas`). Committed strokes
/// then replay from the pictures instead of being re-tessellated —
/// each still inside its layer's `saveLayer`, so opacity, blend modes,
/// and eraser `dstOut` semantics are identical to the un-baked path.
void paintLayerStack(
  Canvas canvas,
  LayerStack layerStack,
  Rect bounds, {
  List<StrokePoint> inProgressPoints = const [],
  Color inProgressColor = const Color(0xFF000000),
  StrokeOptions inProgressOptions = const StrokeOptions(),
  bool inProgressIsEraser = false,
  double scale = 1.0,
  List<Picture>? bakedLayerPictures,
}) {
  assert(bakedLayerPictures == null ||
      bakedLayerPictures.length == layerStack.layers.length);
  for (var i = 0; i < layerStack.layers.length; i++) {
    final layer = layerStack.layers[i];
    if (!layer.visible) continue;

    // Save canvas state for layer opacity. No `blendMode` here (defaults
    // to srcOver): a multiply layer's blend is precomputed per-stroke by
    // resolveStrokeColor below, not applied as a live canvas blend — see
    // the "Non-additive layer compositing" note above resolveStrokeColor.
    canvas.saveLayer(
      bounds,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: layer.opacity),
    );

    if (bakedLayerPictures != null && i < bakedLayerPictures.length) {
      // Committed strokes replay from the pre-recorded picture (already
      // baked with resolveStrokeColor applied — see DrawingCanvas._bakeLayer).
      canvas.drawPicture(bakedLayerPictures[i]);
    } else {
      // Draw strokes interleaved — eraser strokes use dstOut to cut
      // holes
      for (final stroke in layer.strokes) {
        final resolved = resolveStrokeColor(stroke.color, layer.blendMode);
        drawFreehandStroke(
          canvas,
          stroke.points,
          stroke.options,
          paint: stroke.isEraser ? eraserPaint() : inkPaint(resolved),
          scale: scale,
        );
      }
    }

    // Draw the in-progress stroke inside its own layer
    final isActiveLayer = layer == layerStack.activeLayer;
    if (isActiveLayer && inProgressPoints.isNotEmpty) {
      final resolved = resolveStrokeColor(inProgressColor, layer.blendMode);
      drawFreehandStroke(
        canvas,
        inProgressPoints,
        inProgressOptions,
        paint: inProgressIsEraser ? eraserPaint() : inkPaint(resolved),
        scale: scale,
      );
    }

    canvas.restore();
  }
}

/// Fill paint for an ordinary ink stroke.
Paint inkPaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

/// Paint for an eraser stroke — dstOut cuts a hole in the layer.
Paint eraserPaint() => Paint()
  ..blendMode = BlendMode.dstOut
  ..color = const Color(0xFFFFFFFF)
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

/// Tessellate [points] with perfect_freehand and fill the outline.
///
/// [scale] (capture -> painted) floors the tessellated stroke size so
/// the painted width never drops below [kMinPaintedStrokeWidth].
void drawFreehandStroke(
  Canvas canvas,
  List<StrokePoint> points,
  StrokeOptions options, {
  required Paint paint,
  double scale = 1.0,
}) {
  if (points.isEmpty) return;

  // Convert to perfect_freehand input format
  final pfPoints =
      points.map((p) => pf.PointVector(p.x, p.y, p.pressure)).toList();

  // Get the outline points from perfect_freehand
  final outlinePoints = pf.getStroke(
    pfPoints,
    options: pf.StrokeOptions(
      size: effectiveStrokeSize(options.size, scale),
      thinning: options.thinning,
      smoothing: options.smoothing,
      streamline: options.streamline,
      start: pf.StrokeEndOptions.start(
        customTaper: options.taperStart > 0 ? options.taperStart : null,
        taperEnabled: options.taperStart > 0,
      ),
      end: pf.StrokeEndOptions.end(
        customTaper: options.taperEnd > 0 ? options.taperEnd : null,
        taperEnabled: options.taperEnd > 0,
      ),
      simulatePressure: options.simulatePressure,
    ),
  );

  if (outlinePoints.isEmpty) return;

  // Build path from outline points
  final path = Path();
  path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);

  for (int i = 1; i < outlinePoints.length; i++) {
    path.lineTo(outlinePoints[i].dx, outlinePoints[i].dy);
  }
  path.close();

  canvas.drawPath(path, paint);
}
