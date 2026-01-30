import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;
import '../models/stroke.dart';
import '../models/layer.dart';

/// The main drawing canvas widget
class DrawingCanvas extends StatefulWidget {
  final LayerStack layerStack;
  final Color currentColor;
  final StrokeOptions strokeOptions;
  final VoidCallback? onStrokeComplete;
  final ImageProvider? backgroundImage;
  final bool debugPressure; // Show pressure values for testing

  const DrawingCanvas({
    super.key,
    required this.layerStack,
    required this.currentColor,
    required this.strokeOptions,
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

  void _onPointerDown(PointerDownEvent event) {
    final pressure = _normalizePressure(event.pressure);
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
    final pressure = _normalizePressure(event.pressure);
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
    if (_currentPoints.isEmpty) return;

    final stroke = Stroke(
      points: List.from(_currentPoints),
      color: widget.currentColor,
      baseWidth: widget.strokeOptions.size,
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

  /// Normalize pressure value - handles devices that don't report pressure
  double _normalizePressure(double pressure) {
    // pressure == 0 often means "not supported" or "not pressed"
    // pressure == 1 is sometimes the default for non-pressure devices
    // S-Pen should report actual 0.0-1.0 values
    
    if (pressure == 0.0 || pressure == 1.0) {
      // Likely no pressure support, use default
      return 0.5;
    }
    return pressure.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
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

  _DrawingPainter({
    required this.layerStack,
    required this.currentPoints,
    required this.currentColor,
    required this.strokeOptions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Render each visible layer
    for (final layer in layerStack.visibleLayers) {
      // Save canvas state for layer opacity/blend
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = Colors.white.withOpacity(layer.opacity)
          ..blendMode = layer.blendMode,
      );

      // Draw all completed strokes in this layer
      for (final stroke in layer.strokes) {
        _drawStroke(canvas, stroke.points, stroke.color, stroke.baseWidth);
      }

      canvas.restore();
    }

    // Draw current stroke in progress (always on top, active layer)
    if (currentPoints.isNotEmpty) {
      _drawStroke(canvas, currentPoints, currentColor, strokeOptions.size);
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<StrokePoint> points,
    Color color,
    double baseWidth,
  ) {
    if (points.isEmpty) return;

    // Convert to perfect_freehand input format
    final pfPoints = points
        .map((p) => pf.Point(p.x, p.y, p.pressure))
        .toList();

    // Get the outline points from perfect_freehand
    final outlinePoints = pf.getStroke(
      pfPoints,
      size: strokeOptions.size,
      thinning: strokeOptions.thinning,
      smoothing: strokeOptions.smoothing,
      streamline: strokeOptions.streamline,
      taperStart: strokeOptions.taperStart,
      taperEnd: strokeOptions.taperEnd,
      simulatePressure: strokeOptions.simulatePressure,
    );

    if (outlinePoints.isEmpty) return;

    // Build path from outline points
    final path = Path();
    path.moveTo(outlinePoints.first.x, outlinePoints.first.y);
    
    for (int i = 1; i < outlinePoints.length; i++) {
      path.lineTo(outlinePoints[i].x, outlinePoints[i].y);
    }
    path.close();

    // Draw filled path
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) {
    return true; // Always repaint during active drawing
  }
}
