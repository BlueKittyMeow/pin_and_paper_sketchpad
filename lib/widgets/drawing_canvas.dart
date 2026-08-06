import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/stroke.dart';
import '../models/layer.dart';
import '../rendering/stroke_painter.dart';

/// Imperative handle a host app can use to tell a live [DrawingCanvas] to
/// discard whatever stroke is currently in progress, without going
/// through Flutter's raw pointer-cancellation machinery
/// (`GestureBinding.cancelPointer`).
///
/// Added for pinch-to-zoom (owner request, 2026-08-06): a host that wraps
/// the canvas in some zoom/pan gesture recognizer (e.g. a
/// `GestureDetector`'s scale gesture, or `InteractiveViewer`) needs to
/// make sure the first finger's in-progress stroke doesn't silently keep
/// accumulating (and eventually commit as ink) once a second finger joins
/// and turns the gesture into a zoom. Calling `GestureBinding.cancelPointer`
/// on that first finger would work for discarding the stroke, but it ALSO
/// stops the host's zoom recognizer from tracking that same pointer —
/// breaking the pinch mid-gesture (verified the hard way: the main app's
/// own drawing-editor screen hit exactly this, see
/// `pin-and-paper/lib/screens/drawing_editor_screen.dart`'s
/// `_handlePolicyPointerDown` doc comment). This controller lets the host
/// discard the wet stroke on the sketchpad side only, leaving the raw
/// pointer (and whatever else is listening to it, like a zoom gesture
/// recognizer) completely alone.
class DrawingCanvasController extends ChangeNotifier {
  /// Discard the canvas's in-progress stroke, if any. A no-op if nothing
  /// is currently being drawn.
  void cancelActiveStroke() => notifyListeners();
}

/// The main drawing canvas widget
class DrawingCanvas extends StatefulWidget {
  final LayerStack layerStack;
  final Color currentColor;
  final StrokeOptions strokeOptions;
  final bool isEraserActive;
  final VoidCallback? onStrokeComplete;
  final ImageProvider? backgroundImage;
  final bool debugPressure; // Show pressure values for testing

  /// Optional imperative handle — see [DrawingCanvasController]. Null by
  /// default (no behavior change for hosts that don't need it, e.g. the
  /// module's own example app).
  final DrawingCanvasController? controller;

  const DrawingCanvas({
    super.key,
    required this.layerStack,
    required this.currentColor,
    required this.strokeOptions,
    this.isEraserActive = false,
    this.onStrokeComplete,
    this.backgroundImage,
    this.debugPressure = false,
    this.controller,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<StrokePoint> _currentPoints = [];
  double _lastPressure = 0.0;

  /// Whether this canvas (not the caller) set the stack's capture size.
  bool _autoStampedSize = false;

  /// Committed strokes baked into one `ui.Picture` per layer, keyed on
  /// [LayerStack.revision]. During a live stroke only the in-progress
  /// points are re-tessellated each frame; committed strokes replay
  /// from these pictures. Same lifecycle discipline as
  /// `DrawingPreview`: recorded in initState/didUpdateWidget (and at
  /// stroke commit), disposed in dispose() — never managed in build().
  List<ui.Picture> _bakedLayerPictures = const [];
  LayerStack? _bakedStack;
  int _bakedRevision = -1;

  @override
  void initState() {
    super.initState();
    _syncBakedPictures();
    widget.controller?.addListener(_onControllerCancel);
  }

  @override
  void didUpdateWidget(DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBakedPictures();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerCancel);
      widget.controller?.addListener(_onControllerCancel);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerCancel);
    _disposeBakedPictures();
    super.dispose();
  }

  /// [DrawingCanvasController.cancelActiveStroke] fired — discard the wet
  /// stroke exactly like a pointer cancel would, but without touching the
  /// raw pointer itself (see [DrawingCanvasController]'s doc comment).
  void _onControllerCancel() => _discardCurrentStroke();

  void _disposeBakedPictures() {
    for (final picture in _bakedLayerPictures) {
      picture.dispose();
    }
    _bakedLayerPictures = const [];
  }

  /// Re-bake committed strokes if the stack's content changed.
  void _syncBakedPictures() {
    final stack = widget.layerStack;
    if (identical(_bakedStack, stack) && _bakedRevision == stack.revision) {
      return; // Content unchanged — keep the baked pictures.
    }
    _disposeBakedPictures();
    _bakedLayerPictures = [
      for (final layer in stack.layers) _bakeLayer(layer),
    ];
    _bakedStack = stack;
    _bakedRevision = stack.revision;
  }

  /// Record one layer's committed strokes (interleaved ink + eraser,
  /// same order as the un-baked path). saveLayer/opacity/blend are NOT
  /// part of the picture — they're applied at paint time, so layer
  /// property changes don't invalidate stroke tessellation.
  ui.Picture _bakeLayer(DrawingLayer layer) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final stroke in layer.strokes) {
      // resolveStrokeColor bakes the layer's multiply-with-paper blend (if
      // any) into the stroke's own color now, once — see the "Non-additive
      // layer compositing" note in stroke_painter.dart. The baked picture
      // is then always composited with plain srcOver.
      final resolved = resolveStrokeColor(stroke.color, layer.blendMode);
      drawFreehandStroke(
        canvas,
        stroke.points,
        stroke.options,
        paint: stroke.isEraser ? eraserPaint() : inkPaint(resolved),
      );
    }
    return recorder.endRecording();
  }

  /// The pointer currently drawing the in-progress stroke. Events from any
  /// other pointer (second finger, resting palm) are ignored so they cannot
  /// interleave points into the active stroke.
  int? _activePointer;
  PointerDeviceKind? _activePointerKind;

  static bool _isStylus(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) {
      // Palm rejection: a stylus touching down cancels an in-progress
      // touch stroke (the "stroke" was almost certainly a resting palm).
      if (_isStylus(event.kind) && !_isStylus(_activePointerKind)) {
        _discardCurrentStroke();
      } else {
        // A second finger (or a palm while the stylus draws): ignore it.
        return;
      }
    }

    _activePointer = event.pointer;
    _activePointerKind = event.kind;

    final pressure = _normalizePressure(event);
    _lastPressure = pressure;

    setState(() {
      _currentPoints = [
        StrokePoint(
          event.localPosition.dx,
          event.localPosition.dy,
          pressure,
        ),
      ];
    });

    if (widget.debugPressure) {
      debugPrint('DOWN - pressure: ${pressure.toStringAsFixed(3)} '
          'kind: ${event.kind} buttons: ${event.buttons}');
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;

    final pressure = _normalizePressure(event);
    _lastPressure = pressure;

    setState(() {
      _currentPoints.add(
        StrokePoint(
          event.localPosition.dx,
          event.localPosition.dy,
          pressure,
        ),
      );
    });

    if (widget.debugPressure) {
      debugPrint('MOVE - pressure: ${pressure.toStringAsFixed(3)}');
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    _activePointer = null;
    _activePointerKind = null;

    if (_currentPoints.isEmpty) return;

    final stroke = Stroke(
      points: List.from(_currentPoints),
      color: widget.currentColor,
      options: widget.strokeOptions,
      isEraser: widget.isEraserActive,
    );

    widget.layerStack.addStrokeToActiveLayer(stroke);

    setState(() {
      // Fold the freshly committed stroke into the baked pictures now —
      // setState alone rebuilds this State without didUpdateWidget.
      _syncBakedPictures();
      _currentPoints = [];
    });

    widget.onStrokeComplete?.call();

    if (widget.debugPressure) {
      debugPrint('UP - stroke complete with ${stroke.points.length} points');
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    // System cancelled the pointer (palm gesture, notification shade, app
    // switch): discard the in-progress stroke deliberately.
    _discardCurrentStroke();
  }

  void _discardCurrentStroke() {
    _activePointer = null;
    _activePointerKind = null;
    setState(() {
      _currentPoints = [];
    });
  }

  /// Normalize pressure per-device.
  ///
  /// A real stylus reports meaningful pressure — trust it (including an
  /// honest 1.0 at max press; the old heuristic snapped that to 0.5).
  ///
  /// FINGER pressure is trusted too (owner decision 2026-08-06): phone
  /// digitizers report real contact pressure and the resulting organic
  /// width variation is wanted — the earlier hard 0.5 pin threw the
  /// marker's pressure feel away along with the noise. The one recorded
  /// pathological case (a stroke collapsing to threads, "purple thinner"
  /// video 2026-08-05) was diagnosed as one-off reading weirdness —
  /// owner's leading theory: the case magnet skewing the digitizer — and
  /// the owner explicitly chose NO artificial floor; if it recurs, see
  /// the protocol note in pin-and-paper docs/FEATURE_REQUESTS.md.
  ///
  /// Mouse/trackpad report nothing meaningful, so they get a neutral
  /// 0.5; a non-positive reading on any device means "no data", not
  /// "zero press", and falls back the same way.
  double _normalizePressure(PointerEvent event) {
    if (_isStylus(event.kind) || event.kind == PointerDeviceKind.touch) {
      final range = event.pressureMax - event.pressureMin;
      final p = range > 0
          ? (event.pressure - event.pressureMin) / range
          : event.pressure;
      if (p <= 0) return 0.5;
      return p.clamp(0.0, 1.0);
    }
    return 0.5;
  }

  /// Stamp the stack's capture-space size from the canvas's laid-out
  /// dimensions, so a fresh `LayerStack()` can serialize without the
  /// editor remembering to set [LayerStack.size] by hand. Strokes are
  /// recorded in this canvas's local coordinates, so its laid-out size
  /// IS the capture space.
  ///
  /// An explicitly caller-set size is never overwritten. While the
  /// stack is still empty, a re-layout (e.g. device rotation before the
  /// first stroke) re-stamps so the capture space matches where strokes
  /// actually land; once strokes exist the size is frozen.
  void _stampCaptureSize(Size laidOut) {
    if (!laidOut.isFinite || laidOut.isEmpty) return;
    final stack = widget.layerStack;
    if (stack.size == null) {
      stack.size = laidOut;
      _autoStampedSize = true;
    } else if (_autoStampedSize &&
        stack.size != laidOut &&
        stack.layers.every((l) => l.strokes.isEmpty)) {
      stack.size = laidOut;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _stampCaptureSize(constraints.biggest);
      return _buildCanvas();
    });
  }

  Widget _buildCanvas() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        children: [
          // Background image (card texture)
          if (widget.backgroundImage != null)
            Positioned.fill(
              child: Image(
                image: widget.backgroundImage!,
                fit: BoxFit.cover,
              ),
            ),
          
          // Drawing layers
          Positioned.fill(
            child: CustomPaint(
              painter: _DrawingPainter(
                layerStack: widget.layerStack,
                revision: widget.layerStack.revision,
                bakedLayerPictures: _bakedLayerPictures,
                currentPoints: _currentPoints,
                currentColor: widget.currentColor,
                strokeOptions: widget.strokeOptions,
                isEraserActive: widget.isEraserActive,
              ),
              isComplex: true,
              willChange: true,
            ),
          ),

          // Debug overlay
          if (widget.debugPressure)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Pressure: ${_lastPressure.toStringAsFixed(3)}\n'
                  'Points: ${_currentPoints.length}\n'
                  'Layer: ${widget.layerStack.activeLayer.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// CustomPainter that composites the baked committed-stroke pictures
/// and tessellates ONLY the in-progress stroke live.
class _DrawingPainter extends CustomPainter {
  final LayerStack layerStack;
  final int revision;
  final List<ui.Picture> bakedLayerPictures;
  final List<StrokePoint> currentPoints;

  /// [currentPoints] is mutated in place during a stroke; the count
  /// captured at construction lets [shouldRepaint] see growth.
  final int currentPointCount;
  final Color currentColor;
  final StrokeOptions strokeOptions;
  final bool isEraserActive;

  _DrawingPainter({
    required this.layerStack,
    required this.revision,
    required this.bakedLayerPictures,
    required this.currentPoints,
    required this.currentColor,
    required this.strokeOptions,
    this.isEraserActive = false,
  }) : currentPointCount = currentPoints.length;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    paintLayerStack(
      canvas,
      layerStack,
      rect,
      inProgressPoints: currentPoints,
      inProgressColor: currentColor,
      inProgressOptions: strokeOptions,
      inProgressIsEraser: isEraserActive,
      bakedLayerPictures:
          bakedLayerPictures.length == layerStack.layers.length
              ? bakedLayerPictures
              : null,
    );
  }

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      !identical(oldDelegate.layerStack, layerStack) ||
      !identical(oldDelegate.bakedLayerPictures, bakedLayerPictures) ||
      !identical(oldDelegate.currentPoints, currentPoints) ||
      oldDelegate.currentPointCount != currentPointCount ||
      oldDelegate.currentColor != currentColor ||
      oldDelegate.strokeOptions != strokeOptions ||
      oldDelegate.isEraserActive != isEraserActive;
}
