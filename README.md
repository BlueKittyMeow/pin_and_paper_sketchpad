# Pin & Paper Sketchpad Prototype 🎨

A standalone prototype for testing S-Pen pressure sensitivity and stroke rendering before integrating into the main Pin and Paper app.

## Purpose

This prototype exists to answer one question: **Can we get Zinnia-quality drawing feel in Flutter on Android?**

Specifically testing:
- S-Pen pressure data capture
- `perfect_freehand` stroke rendering and taper
- Layer system (sketch → ink → color workflow)
- Blend modes (multiply for paper texture integration)

## Quick Start

```bash
flutter pub get
flutter run
```

## Testing Checklist

1. ☐ **Pressure values** - Watch the debug overlay. Values should vary 0.0-1.0 as you press harder. If stuck at 0.5, pressure isn't being captured.

2. ☐ **Stroke taper** - Lines should be thicker where you press hard, thinner at light pressure and stroke ends.

3. ☐ **Line energy** - Does the stroke preserve your hand's energy/confidence, or does it feel over-smoothed and mushy?

4. ☐ **Layer visibility** - Long-press layer buttons to toggle. Sketch layer should hide/show.

5. ☐ **Blend modes** - Toggle "Blend" switch. Multiply should let background texture show through; off should be opaque.

6. ☐ **The Woolfie Test** - Can you sketch a recognizable dachshund without frustration?

## Tuning Stroke Feel

Edit `lib/models/stroke.dart` → `StrokeOptions` presets:

```dart
static const ink = StrokeOptions(
  size: 3.0,        // Base stroke width
  thinning: 0.6,    // Pressure → width (higher = more variation)
  smoothing: 0.3,   // Path smoothing (lower = more energy)
  streamline: 0.4,  // Pull toward average (lower = more responsive)
  taperStart: 0.1,  // Taper at stroke start
  taperEnd: 0.2,    // Taper at stroke end
);
```

## Adding Card Texture

1. Place your scanned card PNG in `assets/`
2. Uncomment this line in `main.dart`:
   ```dart
   backgroundImage: const AssetImage('assets/kraft_card.png'),
   ```
3. Hot reload and test blend modes

## Project Structure

```
lib/
├── main.dart                 # App scaffold
├── models/
│   ├── stroke.dart          # Stroke data + tuning presets
│   └── layer.dart           # Layer management
└── widgets/
    ├── drawing_canvas.dart  # Core drawing + pressure capture
    └── toolbar.dart         # UI for testing options
```

## Integration Plan

Once this feels right:

**Option A: Local package**
```yaml
# In pin_and_paper/pubspec.yaml
dependencies:
  sketchpad:
    path: ../pin_and_paper_sketchpad
```

**Option B: Copy into main project**
Copy `lib/models/` and `lib/widgets/` into `pin_and_paper/lib/features/sketchpad/`

## Known Limitations

- No eraser yet
- No stroke undo granularity (just removes whole stroke)
- Layer opacity not exposed in UI
- No export/save

These are all solvable — the question is whether the *feel* is right first.

---

🐾 *If the Woolfie test passes, we're good to integrate.*
