import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../models/layer.dart';
import '../models/stroke.dart';

/// Shared layer/stroke painting used by both the live editor
/// (`DrawingCanvas`) and the read-only `DrawingPreview`, so saved
/// drawings replay exactly like they looked in the editor (same
/// saveLayer/opacity/blend/eraser semantics).
///
/// [bounds] is the capture-space rect used for each layer's `saveLayer`.
/// The optional in-progress stroke is drawn on top of the active layer's
/// committed strokes (only the live editor passes one).
void paintLayerStack(
  Canvas canvas,
  LayerStack layerStack,
  Rect bounds, {
  List<StrokePoint> inProgressPoints = const [],
  Color inProgressColor = const Color(0xFF000000),
  StrokeOptions inProgressOptions = const StrokeOptions(),
  bool inProgressIsEraser = false,
}) {
  for (final layer in layerStack.visibleLayers) {
    // Save canvas state for layer opacity/blend
    canvas.saveLayer(
      bounds,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: layer.opacity)
        ..blendMode = layer.blendMode,
    );

    // Draw strokes interleaved — eraser strokes use dstOut to cut holes
    for (final stroke in layer.strokes) {
      drawFreehandStroke(
        canvas,
        stroke.points,
        stroke.options,
        paint: stroke.isEraser ? eraserPaint() : inkPaint(stroke.color),
      );
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
void drawFreehandStroke(
  Canvas canvas,
  List<StrokePoint> points,
  StrokeOptions options, {
  required Paint paint,
}) {
  if (points.isEmpty) return;

  // Convert to perfect_freehand input format
  final pfPoints =
      points.map((p) => pf.PointVector(p.x, p.y, p.pressure)).toList();

  // Get the outline points from perfect_freehand
  final outlinePoints = pf.getStroke(
    pfPoints,
    options: pf.StrokeOptions(
      size: options.size,
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
