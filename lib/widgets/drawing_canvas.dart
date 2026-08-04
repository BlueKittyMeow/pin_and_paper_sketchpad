import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;
import '../models/stroke.dart';
import '../models/layer.dart';

/// The main drawing canvas widget
class DrawingCanvas extends StatefulWidget {
  final LayerStack layerStack;
  final Color currentColor;
  final StrokeOptions strokeOptions;
  final bool isEraserActive;
  final VoidCallback? onStrokeComplete;
  final ImageProvider? backgroundImage;
  final bool debugPressure; // Show pressure values for testing

  const DrawingCanvas({
    super.key,
    required this.layerStack,
    required this.currentColor,
    required this.strokeOptions,
    this.isEraserActive = false,
    this.onStrokeComplete,
    this.backgroundImage,
    this.debugPressure = false,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<StrokePoint> _currentPoints = [];
  double _lastPressure = 0.0;

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
  /// Touch/mouse pressure readings are unreliable, so use a neutral 0.5.
  double _normalizePressure(PointerEvent event) {
    if (_isStylus(event.kind)) {
      final range = event.pressureMax - event.pressureMin;
      if (range > 0) {
        return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
      }
      return event.pressure.clamp(0.0, 1.0);
    }
    return 0.5;
  }

  @override
  Widget build(BuildContext context) {
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

/// CustomPainter that renders all layers and strokes
class _DrawingPainter extends CustomPainter {
  final LayerStack layerStack;
  final List<StrokePoint> currentPoints;
  final Color currentColor;
  final StrokeOptions strokeOptions;
  final bool isEraserActive;

  _DrawingPainter({
    required this.layerStack,
    required this.currentPoints,
    required this.currentColor,
    required this.strokeOptions,
    this.isEraserActive = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Render each visible layer
    for (final layer in layerStack.visibleLayers) {
      // Save canvas state for layer opacity/blend
      canvas.saveLayer(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: layer.opacity)
          ..blendMode = layer.blendMode,
      );

      // Draw strokes interleaved — eraser strokes use dstOut to cut holes
      for (final stroke in layer.strokes) {
        if (stroke.isEraser) {
          _drawStroke(canvas, stroke.points, stroke.options,
              paint: Paint()
                ..blendMode = BlendMode.dstOut
                ..color = Colors.white
                ..style = PaintingStyle.fill
                ..isAntiAlias = true);
        } else {
          _drawStroke(canvas, stroke.points, stroke.options,
              paint: Paint()
                ..color = stroke.color
                ..style = PaintingStyle.fill
                ..isAntiAlias = true);
        }
      }

      // Draw current stroke in-progress inside its own layer
      final isActiveLayer = layer == layerStack.activeLayer;
      if (isActiveLayer && currentPoints.isNotEmpty) {
        if (isEraserActive) {
          _drawStroke(canvas, currentPoints, strokeOptions,
              paint: Paint()
                ..blendMode = BlendMode.dstOut
                ..color = Colors.white
                ..style = PaintingStyle.fill
                ..isAntiAlias = true);
        } else {
          _drawStroke(canvas, currentPoints, strokeOptions,
              paint: Paint()
                ..color = currentColor
                ..style = PaintingStyle.fill
                ..isAntiAlias = true);
        }
      }

      canvas.restore();
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<StrokePoint> points,
    StrokeOptions options, {
    required Paint paint,
  }) {
    if (points.isEmpty) return;

    // Convert to perfect_freehand input format
    final pfPoints = points
        .map((p) => pf.PointVector(p.x, p.y, p.pressure))
        .toList();

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

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) {
    return true; // Always repaint during active drawing
  }
}
