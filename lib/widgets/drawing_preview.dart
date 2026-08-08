import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../rendering/stroke_painter.dart';

/// Read-only renderer for a saved drawing.
///
/// Paints the flattened visible layers of a [LayerStack] via a
/// `ui.Picture` recorded once per content change — never per frame, and
/// with no per-frame perfect_freehand re-tessellation — inside a
/// [RepaintBoundary]. This is the widget task cards embed; cards must
/// never run the live [DrawingCanvas] painter.
///
/// Honors layer visibility, opacity, and blend modes, and eraser strokes
/// (`BlendMode.dstOut`), identically to the live editor (both replay
/// through the same shared painting code).
///
/// Strokes are recorded in capture-space coordinates
/// ([LayerStack.size]); the preview scales them to [size] via
/// `canvas.scale`, so stroke widths scale proportionally and the vector
/// picture stays crisp under further transforms (e.g. desk zoom).
///
/// Content-change detection: re-records when the [layerStack] instance,
/// its [LayerStack.revision], the target [size], or [backdropImage]
/// changes. Mutations made behind the stack's back must call
/// [LayerStack.markChanged].
///
/// Lifecycle: the picture is recorded in [State.initState] /
/// [State.didUpdateWidget] and disposed in [State.dispose] — never
/// allocated or disposed inside `build()`, so no native graphics
/// resource is torn down while the raster thread may still be painting
/// a frame that references it.
class DrawingPreview extends StatefulWidget {
  /// The drawing to render. [LayerStack.size] (capture space) should be
  /// set — as it always is for stacks restored via [LayerStack.fromJson]
  /// — otherwise strokes are assumed to already be in target space.
  final LayerStack layerStack;

  /// Target render size (e.g. the 220x140 logical card face).
  final Size size;

  /// Raster snapshot of whatever real content sits beneath the drawing
  /// (e.g. the card back), in the drawing's own capture-space coordinates
  /// ([LayerStack.size] — NOT [size]; it is stretched to fit via
  /// `drawImageRect`, so any resolution works). When supplied, a
  /// BlendMode.multiply layer composites with a real multiply blend
  /// against it instead of the flat-paper precompute — see the
  /// "Backdrop-aware multiply compositing" note in
  /// `rendering/stroke_painter.dart`. Null (the default) preserves prior
  /// behavior for hosts that haven't been updated to supply one (owner
  /// report 2026-08-06, fixed 2026-08-07) — e.g. the desk's card overlay
  /// (`canvas_screen.dart`) still needs its own follow-up to snapshot the
  /// card back and pass it here for full on-card consistency.
  final ui.Image? backdropImage;

  const DrawingPreview({
    super.key,
    required this.layerStack,
    required this.size,
    this.backdropImage,
  });

  /// Convenience: build a preview straight from serialized format-v1
  /// JSON (the `task_drawings.drawing_json` column).
  ///
  /// Throws [FormatException] for unknown versions, like
  /// [LayerStack.fromJson].
  factory DrawingPreview.fromJson(
    String json, {
    Key? key,
    required Size size,
    ui.Image? backdropImage,
  }) =>
      DrawingPreview(
        key: key,
        layerStack:
            LayerStack.fromJson(jsonDecode(json) as Map<String, dynamic>),
        size: size,
        backdropImage: backdropImage,
      );

  /// Scale factors applied to capture-space strokes to fill [target].
  @visibleForTesting
  static Offset scaleFactors(Size capture, Size target) =>
      Offset(target.width / capture.width, target.height / capture.height);

  @override
  State<DrawingPreview> createState() => _DrawingPreviewState();
}

class _DrawingPreviewState extends State<DrawingPreview> {
  ui.Picture? _picture;
  LayerStack? _recordedStack;
  int _recordedRevision = -1;
  Size? _recordedSize;
  ui.Image? _recordedBackdropImage;

  bool get _hasVisibleContent => widget.layerStack.visibleLayers
      .any((l) => l.strokes.any((s) => !s.isEraser && s.points.isNotEmpty));

  @override
  void initState() {
    super.initState();
    _syncPicture();
  }

  @override
  void didUpdateWidget(DrawingPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPicture();
  }

  /// Record (or re-record) the picture if content changed; called only
  /// from lifecycle methods, never from `build()`.
  void _syncPicture() {
    final stack = widget.layerStack;
    if (identical(_recordedStack, stack) &&
        _recordedRevision == stack.revision &&
        _recordedSize == widget.size &&
        identical(_recordedBackdropImage, widget.backdropImage)) {
      return; // Content unchanged — reuse the recorded picture.
    }
    _picture?.dispose();
    // Empty drawings never record: an absent picture keeps the
    // zero-overhead SizedBox path in build().
    _picture = _hasVisibleContent ? _record(stack) : null;
    _recordedStack = stack;
    _recordedRevision = stack.revision;
    _recordedSize = widget.size;
    _recordedBackdropImage = widget.backdropImage;
  }

  ui.Picture _record(LayerStack stack) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final capture = stack.size ?? widget.size;
    final scale = DrawingPreview.scaleFactors(capture, widget.size);
    canvas.scale(scale.dx, scale.dy);
    paintLayerStack(
      canvas,
      stack,
      Rect.fromLTWH(0, 0, capture.width, capture.height),
      // Worst-case shrink axis governs the min painted stroke width.
      scale: math.min(scale.dx, scale.dy),
      backdropImage: widget.backdropImage,
    );
    return recorder.endRecording();
  }

  @override
  void dispose() {
    _picture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    if (picture == null) {
      // Nothing to draw — keep the slot's size but paint nothing.
      return SizedBox.fromSize(size: widget.size);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: widget.size,
        isComplex: true,
        painter: _PicturePainter(picture),
      ),
    );
  }
}

/// Replays a pre-recorded picture; repaints only when the picture object
/// itself is swapped (i.e. content changed).
class _PicturePainter extends CustomPainter {
  final ui.Picture picture;

  _PicturePainter(this.picture);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(_PicturePainter oldDelegate) =>
      !identical(oldDelegate.picture, picture);
}
