# Pin & Paper Sketchpad

Pressure-sensitive drawing module for the Pin & Paper app. Three-layer system (sketch → ink → color) with per-layer eraser, blend modes, and S-Pen support.

## Quick Start

```bash
flutter pub get
flutter run
```

## Usage as a Package

```dart
import 'package:pin_and_paper_sketchpad/sketchpad.dart';

final layerStack = LayerStack();

DrawingCanvas(
  layerStack: layerStack,
  currentColor: Colors.black,
  strokeOptions: StrokeOptions.ink,
  onStrokeComplete: () => setState(() {}),
)
```

## Project Structure

```
lib/
├── main.dart                 # Prototype app entry point
├── sketchpad.dart            # Public API exports
├── models/
│   ├── stroke.dart           # Stroke data + tuning presets
│   └── layer.dart            # Layer management
└── widgets/
    ├── drawing_canvas.dart   # Core drawing + pressure capture
    └── toolbar.dart          # UI controls
```

## Adding a Background Texture

1. Place image in `assets/`
2. Reference in `main.dart`:
   ```dart
   backgroundImage: const AssetImage('assets/your_texture.png'),
   ```

## Documentation

Full specs live in the dev harness: `pin_and_paper_dev_harness/docs/module_specs/SKETCHPAD_SPEC.md`
