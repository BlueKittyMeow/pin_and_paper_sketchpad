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

  /// Serialization format v1. Enums are serialized by name (survives
  /// Flutter upgrades better than indices).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'blendMode': blendMode.name,
        'defaultOptions': defaultOptions.toJson(),
        'strokes': [for (final s in strokes) s.toJson()],
      };

  factory DrawingLayer.fromJson(Map<String, dynamic> json) {
    final blendName = json['blendMode'] as String? ?? 'srcOver';
    final BlendMode blend;
    try {
      blend = BlendMode.values.byName(blendName);
    } on ArgumentError {
      throw FormatException('Unknown blend mode: "$blendName"');
    }
    return DrawingLayer(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Layer',
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: blend,
      defaultOptions: json['defaultOptions'] != null
          ? StrokeOptions.fromJson(
              json['defaultOptions'] as Map<String, dynamic>)
          : StrokeOptions.ink,
      strokes: [
        for (final s in json['strokes'] as List<dynamic>? ?? const [])
          Stroke.fromJson(s as Map<String, dynamic>),
      ],
    );
  }
}

/// A single undoable mutation in a [LayerStack]'s chronological history.
sealed class _StackAction {
  _StackAction(this.layerId);

  /// The layer the action happened on (undo/redo target it by id, so
  /// the currently active layer is irrelevant).
  final String layerId;
}

/// A stroke was committed to a layer.
class _StrokeAdded extends _StackAction {
  _StrokeAdded(super.layerId, this.stroke);
  final Stroke stroke;
}

/// A layer was cleared; keeps the removed strokes for undo.
class _LayerCleared extends _StackAction {
  _LayerCleared(super.layerId, this.removedStrokes);
  final List<Stroke> removedStrokes;
}

/// Manages the layer stack for a card
class LayerStack {
  final List<DrawingLayer> layers;

  /// Capture-space size: the logical size of the surface the strokes were
  /// recorded against (e.g. the editor surface). Required for
  /// serialization (format v1) so consumers can scale strokes to any
  /// target size.
  Size? size;

  int _activeLayerIndex = 0;

  LayerStack({List<DrawingLayer>? layers, this.size})
      : layers = layers ?? _defaultLayers() {
    if (this.layers.isEmpty) {
      throw ArgumentError('LayerStack requires at least one layer');
    }
    // Default to the top layer, valid for any layer count.
    _activeLayerIndex = this.layers.length - 1;
  }

  static List<DrawingLayer> _defaultLayers() => [
    DrawingLayer.color(),   // Bottom - watercolor/fill
    DrawingLayer.sketch(),  // Middle - rough sketch
    DrawingLayer.ink(),     // Top - final lines
  ];

  DrawingLayer get activeLayer => layers[_activeLayerIndex];
  int get activeLayerIndex => _activeLayerIndex;

  /// Monotonic content revision. Bumped by every mutation that changes
  /// rendered output; cached renderers (e.g. `DrawingPreview`) compare it
  /// to decide when to re-record. If you mutate a [DrawingLayer] directly
  /// (bypassing the LayerStack methods), call [markChanged] yourself.
  int get revision => _revision;
  int _revision = 0;

  /// Record that rendered content changed (see [revision]).
  void markChanged() {
    _revision++;
  }

  void setActiveLayer(int index) {
    if (index >= 0 && index < layers.length) {
      _activeLayerIndex = index;
    }
  }

  // Cross-layer chronological history (agy M-D2.5 item 6, owner L3:
  // full three-layer toolbar makes this REQUIRED). Every committed
  // stroke and every layer clear is one entry, in the order it
  // happened, regardless of which layer it landed on. Strokes restored
  // by [LayerStack.fromJson] predate the session and are not undoable.
  final List<_StackAction> _undoHistory = [];
  final List<_StackAction> _redoHistory = [];

  /// Whether [undo] has anything to step back through.
  bool get canUndo => _undoHistory.isNotEmpty;

  /// Whether [redo] has anything to restore.
  bool get canRedo => _redoHistory.isNotEmpty;

  DrawingLayer? _layerById(String id) {
    for (final layer in layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  void addStrokeToActiveLayer(Stroke stroke) {
    activeLayer.addStroke(stroke);
    _undoHistory.add(_StrokeAdded(activeLayer.id, stroke));
    _redoHistory.clear();
    markChanged();
  }

  /// Undo the most recent action (stroke or layer clear) anywhere in
  /// the stack — chronological, regardless of the active layer.
  /// Returns false (and bumps nothing) when there is no history.
  bool undo() {
    if (_undoHistory.isEmpty) return false;
    final action = _undoHistory.removeLast();
    final layer = _layerById(action.layerId);
    if (layer != null) {
      switch (action) {
        case _StrokeAdded(:final stroke):
          layer.strokes.remove(stroke);
        case _LayerCleared(:final removedStrokes):
          // All actions after the clear were undone first, so the layer
          // holds no post-clear strokes: restoring in place preserves
          // the original interleave (eraser ordering matters).
          layer.strokes.insertAll(0, removedStrokes);
      }
    }
    _redoHistory.add(action);
    markChanged();
    return true;
  }

  /// Redo the most recently undone action, restoring the stroke (or
  /// re-clearing the layer) it recorded. Returns false when there is
  /// nothing to redo.
  bool redo() {
    if (_redoHistory.isEmpty) return false;
    final action = _redoHistory.removeLast();
    final layer = _layerById(action.layerId);
    if (layer != null) {
      switch (action) {
        case _StrokeAdded(:final stroke):
          layer.strokes.add(stroke);
        case _LayerCleared(:final removedStrokes):
          for (final stroke in removedStrokes) {
            layer.strokes.remove(stroke);
          }
      }
    }
    _undoHistory.add(action);
    markChanged();
    return true;
  }

  /// Clear all strokes from the active layer.
  ///
  /// Semantics decision (M-D2.5 item 6): the clear is one **undoable
  /// batch** — [undo] restores every removed stroke at once, [redo]
  /// re-clears. Like any new action it resets the redo history.
  /// Clearing an already-empty layer is a no-op (no history entry, no
  /// revision bump).
  void clearActiveLayer() {
    if (activeLayer.strokes.isEmpty) return;
    _undoHistory.add(
        _LayerCleared(activeLayer.id, List.of(activeLayer.strokes)));
    activeLayer.clear();
    _redoHistory.clear();
    markChanged();
  }

  void toggleLayerVisibility(int index) {
    if (index >= 0 && index < layers.length) {
      layers[index].visible = !layers[index].visible;
      markChanged();
    }
  }

  /// Toggle between multiply blend (paper texture shows) and srcOver (opaque)
  void toggleBlendMode(int index) {
    if (index >= 0 && index < layers.length) {
      final layer = layers[index];
      layer.blendMode = layer.blendMode == BlendMode.multiply
          ? BlendMode.srcOver
          : BlendMode.multiply;
      markChanged();
    }
  }

  /// Get layers in render order (bottom to top)
  Iterable<DrawingLayer> get visibleLayers =>
      layers.where((l) => l.visible);

  /// Serialization format v1:
  /// `{"v": 1, "size": [w, h], "activeLayer": n, "layers": [...]}`.
  ///
  /// [size] (capture space) is required — set it before serializing.
  Map<String, dynamic> toJson() {
    final captureSize = size;
    if (captureSize == null) {
      throw StateError(
          'LayerStack.size is unset: format v1 requires the capture-space '
          'size so drawings can be scaled to their render target. '
          'DrawingCanvas stamps it automatically from its laid-out '
          'dimensions once it builds; if this stack never reached a '
          'DrawingCanvas, set LayerStack.size yourself before calling '
          'toJson().');
    }
    return {
      'v': 1,
      'size': [round2(captureSize.width), round2(captureSize.height)],
      'activeLayer': _activeLayerIndex,
      'layers': [for (final l in layers) l.toJson()],
    };
  }

  /// Deserialize format v1. Throws [FormatException] for any other
  /// version or a missing/invalid `size` field.
  factory LayerStack.fromJson(Map<String, dynamic> json) {
    final version = json['v'];
    if (version != 1) {
      throw FormatException(
          'Unsupported drawing format version: $version (expected "v": 1)');
    }
    final rawSize = json['size'];
    if (rawSize is! List || rawSize.length != 2) {
      throw const FormatException(
          'Drawing format v1 requires a "size": [w, h] field');
    }
    final layers = [
      for (final l in json['layers'] as List<dynamic>? ?? const [])
        DrawingLayer.fromJson(l as Map<String, dynamic>),
    ];
    if (layers.isEmpty) {
      throw const FormatException(
          'Drawing format v1 requires at least one layer');
    }
    final stack = LayerStack(
      layers: layers,
      size: Size(
        (rawSize[0] as num).toDouble(),
        (rawSize[1] as num).toDouble(),
      ),
    );
    final active = json['activeLayer'];
    if (active is int) {
      stack.setActiveLayer(active);
    }
    return stack;
  }
}
