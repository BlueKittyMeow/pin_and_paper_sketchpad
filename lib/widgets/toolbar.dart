import 'package:flutter/material.dart';
import '../models/stroke.dart';
import '../models/layer.dart';

class DrawingToolbar extends StatelessWidget {
  final LayerStack layerStack;
  final Color currentColor;
  final StrokeOptions currentOptions;
  final bool useBlend;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<StrokeOptions> onOptionsChanged;
  final ValueChanged<bool> onBlendChanged;
  final ValueChanged<int> onLayerSelected;
  final ValueChanged<int> onVisibilityToggled;
  final bool isEraserActive;
  final ValueChanged<bool> onEraserToggled;

  /// Cross-layer chronological undo (see [LayerStack.undo]); the button
  /// is disabled while [canUndo] is false.
  final VoidCallback onUndo;
  final bool canUndo;

  /// Cross-layer redo (see [LayerStack.redo]); the button only appears
  /// when a callback is wired, and disables while [canRedo] is false.
  final VoidCallback? onRedo;
  final bool canRedo;

  final VoidCallback onClear;

  // Pin and Paper color palette
  static const _colors = [
    Color(0xFF2D2D2D), // Near black (ink)
    Color(0xFF4A3F35), // Deep shadow
    Color(0xFF8B7355), // Warm wood
    Color(0xFF9B8FA5), // Muted lavender
    Color(0xFFD4B896), // Kraft paper
    Color(0xFFC75B4A), // Rust red
    Color(0xFF5B8C7A), // Muted green
    Color(0xFF7A9BBF), // Dusty blue
  ];

  const DrawingToolbar({
    super.key,
    required this.layerStack,
    required this.currentColor,
    required this.currentOptions,
    required this.useBlend,
    required this.onColorChanged,
    required this.onOptionsChanged,
    required this.onBlendChanged,
    required this.onLayerSelected,
    required this.onVisibilityToggled,
    this.isEraserActive = false,
    required this.onEraserToggled,
    required this.onUndo,
    this.canUndo = true,
    this.onRedo,
    this.canRedo = false,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8), // Cream paper
        border: Border(
          top: BorderSide(color: Colors.brown.shade200),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Layer controls
          _buildLayerRow(),
          const SizedBox(height: 8),

          // Color palette
          _buildColorRow(),
          const SizedBox(height: 8),

          // Stroke size (owner 2026-08-06: every implement gets a size
          // control + reset-to-default, not just some).
          _buildSizeRow(context),
          const SizedBox(height: 8),

          // Tool presets and actions
          _buildToolRow(),
        ],
      ),
    );
  }

  Widget _buildLayerRow() {
    return Row(
      children: [
        const Text(
          'Layer: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4A3F35),
          ),
        ),
        const SizedBox(width: 8),
        // Display order: Sketch(1), Ink(2), Brush/Color(0)
        ...[1, 2, 0].map((index) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildLayerChipGroup(index),
            )),
        const Spacer(),
        // Blend mode toggle
        Row(
          children: [
            const Text(
              'Blend:',
              style: TextStyle(fontSize: 11, color: Color(0xFF4A3F35)),
            ),
            Switch(
              value: useBlend,
              onChanged: onBlendChanged,
              activeThumbColor: const Color(0xFF8B7355),
            ),
          ],
        ),
      ],
    );
  }

  /// One layer's go-to-layer chip + its own visibility eyeball, tapped
  /// independently (owner 2026-08-06): tapping the name switches to that
  /// layer (selecting it AND applying its default tool options, exactly
  /// what the old Sketch/Ink/Color preset buttons in the tool row did —
  /// this row REPLACES them, completing the owner's unification: one
  /// place with the layer names, eyeball adjacent); tapping the eye
  /// toggles that layer's visibility via [onVisibilityToggled].
  /// Previously the names lived twice — a visibility-only row up here
  /// and the selecting preset buttons below. A light-opacity ring around
  /// both pieces together is the "these two belong to each other"
  /// grouping cue, so ownership reads at a glance even though they're
  /// separately tappable.
  /// Display labels for the standard layers (owner rename 2026-08-06:
  /// physical implement names — "Color" collided with the color palette
  /// concept and never stuck). Serialized layer names are untouched, so
  /// old drawings load unchanged and still get the new labels; a custom
  /// layer name passes through as-is.
  static const _displayNames = {
    'Sketch': 'Pencil',
    'Ink': 'Pen',
    'Color': 'Marker',
  };

  static String _displayName(String layerName) =>
      _displayNames[layerName] ?? layerName;

  Widget _buildLayerChipGroup(int index) {
    final layer = layerStack.layers[index];
    final isActive = index == layerStack.activeLayerIndex;
    const wood = Color(0xFF8B7355);
    const ink = Color(0xFF4A3F35);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        // The "light-opacity ring" binding chip + eyeball as one unit.
        border: Border.all(color: wood.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Go-to-layer chip. Fires both callbacks the old preset
          // buttons fired, so consumers that only listen to
          // onOptionsChanged keep working.
          GestureDetector(
            onTap: () {
              onLayerSelected(index);
              onOptionsChanged(layer.defaultOptions);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? wood : Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _displayName(layer.name),
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? Colors.white : ink,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Visibility eyeball — its own tap target, right next to the
          // chip it owns.
          GestureDetector(
            onTap: () => onVisibilityToggled(index),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: layer.visible ? Colors.white : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                layer.visible ? Icons.visibility : Icons.visibility_off,
                size: 16,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorRow() {
    return Row(
      children: [
        const Text(
          'Color: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4A3F35),
          ),
        ),
        const SizedBox(width: 8),
        ..._colors.map((color) {
          final isSelected = color.toARGB32() == currentColor.toARGB32();
          return GestureDetector(
            onTap: () => onColorChanged(color),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Practical size range shared by every implement (sketch/ink/watercolor
  /// presets run 2.0-16.0; the eraser reuses whatever tool size was active
  /// when toggled — see [_buildToolRow]'s eraser button). Not the
  /// SKETCHPAD_SPEC's future 1-100px alpha-mask eraser range: today's
  /// eraser is literally an ink stroke that cuts a hole (dstOut), so it
  /// shares ink's size semantics, not a separate diameter concept.
  static const double _minSize = 1.0;
  static const double _maxSize = 40.0;

  /// Stroke size control for whichever implement is currently active
  /// (owner 2026-08-06: every implement, not just some) plus a
  /// reset-to-tool-default affordance. "Tool default" is the active
  /// layer's own [DrawingLayer.defaultOptions.size] — the size baked into
  /// its Sketch/Ink/Color preset — regardless of whether the eraser is
  /// currently toggled on, since the eraser isn't a separate tool with
  /// its own default; it's a modifier on top of whatever tool/size is
  /// current.
  Widget _buildSizeRow(BuildContext context) {
    final size = currentOptions.size;
    final defaultSize = layerStack.activeLayer.defaultOptions.size;
    final atDefault = (size - defaultSize).abs() < 0.05;

    return Row(
      children: [
        const Text(
          'Size: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4A3F35),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            size.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A3F35)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: size.clamp(_minSize, _maxSize),
              min: _minSize,
              max: _maxSize,
              activeColor: const Color(0xFF8B7355),
              inactiveColor: const Color(0xFF8B7355).withValues(alpha: 0.25),
              onChanged: (v) =>
                  onOptionsChanged(currentOptions.copyWith(size: v)),
            ),
          ),
        ),
        IconButton(
          onPressed: atDefault
              ? null
              : () => onOptionsChanged(
                  currentOptions.copyWith(size: defaultSize)),
          icon: const Icon(Icons.replay, size: 18),
          tooltip: atDefault
              ? 'At tool default (${defaultSize.toStringAsFixed(1)})'
              : 'Reset to tool default (${defaultSize.toStringAsFixed(1)})',
          color: const Color(0xFF4A3F35),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildToolRow() {
    return Row(
      children: [
        // Layer/tool selection lives in the layer-chip row now (owner
        // 2026-08-06 unification) — this row keeps the eraser + actions.
        _buildEraserButton(),

        const Spacer(),

        // Actions — undo/redo step through the cross-layer
        // chronological history, not just the active layer.
        IconButton(
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
          color: const Color(0xFF4A3F35),
        ),
        if (onRedo != null)
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            color: const Color(0xFF4A3F35),
          ),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Clear layer',
          color: const Color(0xFF4A3F35),
        ),
      ],
    );
  }

  Widget _buildEraserButton() {
    return ElevatedButton(
      onPressed: () => onEraserToggled(!isEraserActive),
      style: ElevatedButton.styleFrom(
        backgroundColor: isEraserActive
            ? const Color(0xFFC75B4A)
            : Colors.white,
        foregroundColor: isEraserActive
            ? Colors.white
            : const Color(0xFF4A3F35),
        elevation: isEraserActive ? 2 : 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_fix_high, size: 14),
          SizedBox(width: 4),
          Text('Eraser', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

}
