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
  final VoidCallback onUndo;
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
    required this.onUndo,
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
          'Layers: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4A3F35),
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(layerStack.layers.length, (index) {
          final layer = layerStack.layers[index];
          final isActive = index == layerStack.activeLayerIndex;
          
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => layerStack.setActiveLayer(index),
              onLongPress: () => layerStack.toggleLayerVisibility(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive 
                      ? const Color(0xFF8B7355) 
                      : Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF8B7355),
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      layer.visible ? Icons.visibility : Icons.visibility_off,
                      size: 14,
                      color: isActive ? Colors.white : const Color(0xFF4A3F35),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      layer.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? Colors.white : const Color(0xFF4A3F35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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
              activeColor: const Color(0xFF8B7355),
            ),
          ],
        ),
      ],
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
          final isSelected = color.value == currentColor.value;
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
                          color: color.withOpacity(0.5),
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

  Widget _buildToolRow() {
    return Row(
      children: [
        // Preset buttons
        _buildPresetButton('Ink', StrokeOptions.ink),
        _buildPresetButton('Sketch', StrokeOptions.sketch),
        _buildPresetButton('Brush', StrokeOptions.watercolor),
        
        const Spacer(),
        
        // Actions
        IconButton(
          onPressed: onUndo,
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
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

  Widget _buildPresetButton(String label, StrokeOptions options) {
    final isSelected = currentOptions == options;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton(
        onPressed: () => onOptionsChanged(options),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected 
              ? const Color(0xFF8B7355) 
              : Colors.white,
          foregroundColor: isSelected 
              ? Colors.white 
              : const Color(0xFF4A3F35),
          elevation: isSelected ? 2 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
