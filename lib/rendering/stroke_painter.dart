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

/// Capture-space stroke size floored so that after multiplying by
/// [scale] (capture -> painted) the painted width is at least
/// [kMinPaintedStrokeWidth]. At scale >= 1 normal sizes pass through
/// untouched.
double effectiveStrokeSize(double size, double scale) {
  if (scale <= 0) return size;
  final floor = kMinPaintedStrokeWidth / scale;
  return size < floor ? floor : size;
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

    // Save canvas state for layer opacity/blend
    canvas.saveLayer(
      bounds,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: layer.opacity)
        ..blendMode = layer.blendMode,
    );

    if (bakedLayerPictures != null && i < bakedLayerPictures.length) {
      // Committed strokes replay from the pre-recorded picture.
      canvas.drawPicture(bakedLayerPictures[i]);
    } else {
      // Draw strokes interleaved — eraser strokes use dstOut to cut
      // holes
      for (final stroke in layer.strokes) {
        drawFreehandStroke(
          canvas,
          stroke.points,
          stroke.options,
          paint: stroke.isEraser ? eraserPaint() : inkPaint(stroke.color),
          scale: scale,
        );
      }
    }

    // Draw the in-progress stroke inside its own layer
    final isActiveLayer = layer == layerStack.activeLayer;
    if (isActiveLayer && inProgressPoints.isNotEmpty) {
      drawFreehandStroke(
        canvas,
        inProgressPoints,
        inProgressOptions,
        paint:
            inProgressIsEraser ? eraserPaint() : inkPaint(inProgressColor),
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
