import 'dart:ui';
import 'stroke.dart';

/// A drawing layer containing multiple strokes
class DrawingLayer {
  final String id;
  String name;
  bool visible;
  double opacity;
  BlendMode blendMode;
  final StrokeOptions defaultOptions;
  final List<Stroke> strokes;

  DrawingLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.blendMode = BlendMode.srcOver,
    this.defaultOptions = StrokeOptions.ink,
    List<Stroke>? strokes,
  }) : strokes = strokes ?? [];

  /// Create a standard ink layer (top, opaque)
  factory DrawingLayer.ink() => DrawingLayer(
    id: 'ink_${DateTime.now().millisecondsSinceEpoch}',
    name: 'Ink',
    blendMode: BlendMode.srcOver,
    defaultOptions: StrokeOptions.ink,
  );

  /// Create a sketch layer (middle, can be hidden)
  factory DrawingLayer.sketch() => DrawingLayer(
    id: 'sketch_${DateTime.now().millisecondsSinceEpoch}',
    name: 'Sketch',
    opacity: 0.6,
    blendMode: BlendMode.srcOver,
    defaultOptions: StrokeOptions.sketch,
  );

  /// Create a color/watercolor layer (bottom, multiply blend)
  factory DrawingLayer.color() => DrawingLayer(
    id: 'color_${DateTime.now().millisecondsSinceEpoch}',
    name: 'Color',
    blendMode: BlendMode.multiply,
    defaultOptions: StrokeOptions.watercolor,
  );

  void addStroke(Stroke stroke) {
    strokes.add(stroke);
  }

  void removeLastStroke() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
    }
  }

  void clear() {
    strokes.clear();
  }
}

/// Manages the layer stack for a card
class LayerStack {
  final List<DrawingLayer> layers;
  int _activeLayerIndex;

  LayerStack({List<DrawingLayer>? layers})
      : layers = layers ?? _defaultLayers(),
        _activeLayerIndex = 2; // Default to ink layer (top)

  static List<DrawingLayer> _defaultLayers() => [
    DrawingLayer.color(),   // Bottom - watercolor/fill
    DrawingLayer.sketch(),  // Middle - rough sketch
    DrawingLayer.ink(),     // Top - final lines
  ];

  DrawingLayer get activeLayer => layers[_activeLayerIndex];
  int get activeLayerIndex => _activeLayerIndex;

  void setActiveLayer(int index) {
    if (index >= 0 && index < layers.length) {
      _activeLayerIndex = index;
    }
  }

  void addStrokeToActiveLayer(Stroke stroke) {
    activeLayer.addStroke(stroke);
  }

  void undoOnActiveLayer() {
    activeLayer.removeLastStroke();
  }

  void toggleLayerVisibility(int index) {
    if (index >= 0 && index < layers.length) {
      layers[index].visible = !layers[index].visible;
    }
  }

  /// Toggle between multiply blend (paper texture shows) and srcOver (opaque)
  void toggleBlendMode(int index) {
    if (index >= 0 && index < layers.length) {
      final layer = layers[index];
      layer.blendMode = layer.blendMode == BlendMode.multiply
          ? BlendMode.srcOver
          : BlendMode.multiply;
    }
  }

  /// Get layers in render order (bottom to top)
  Iterable<DrawingLayer> get visibleLayers =>
      layers.where((l) => l.visible);
}
