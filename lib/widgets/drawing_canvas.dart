import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/stroke.dart';
import '../models/layer.dart';
import '../rendering/stroke_painter.dart';

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

  /// Whether this canvas (not the caller) set the stack's capture size.
  bool _autoStampedSize = false;

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

    paintLayerStack(
      canvas,
      layerStack,
      rect,
      inProgressPoints: currentPoints,
      inProgressColor: currentColor,
      inProgressOptions: strokeOptions,
      inProgressIsEraser: isEraserActive,
    );
  }

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) {
    return true; // Always repaint during active drawing
  }
}
