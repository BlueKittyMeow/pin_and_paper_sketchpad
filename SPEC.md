# Pin & Paper Sketchpad — Design Spec

## Overview

A three-layer drawing system designed for the sketch-ink-color workflow common in illustration. Each layer has distinct rendering characteristics optimized for its role in the process.

## Layer Stack (bottom to top)

| Layer  | Purpose                          | Default Opacity | Blend Mode                        | Stroke Character                                                        |
|--------|----------------------------------|-----------------|-----------------------------------|-------------------------------------------------------------------------|
| Color  | Fill, watercolor, shading        | 100%            | Multiply (shows paper texture)    | Soft, pressure-sensitive, wide strokes — light touch for detail, heavy for fills |
| Sketch | Rough construction, guidelines   | 60%             | Normal                            | Loose, energetic, minimal smoothing — preserves hand's natural movement |
| Ink    | Final linework                   | 100%            | Normal                            | Clean, tapered, moderate smoothing — confident lines without wobble     |

## Core Workflow

1. **Sketch** — Rough out the drawing loosely on Sketch layer (e.g., basic Woolfie shape)
2. **Ink** — Switch to Ink layer, trace clean final lines over sketch
3. **Hide Sketch** — Toggle Sketch layer visibility off, construction lines disappear
4. **Color** — Switch to Color layer, paint underneath the ink. Multiply blend lets strokes interact with paper texture rather than sitting flat on top

## Layer Behaviors

- **Active layer** — All drawing goes to currently selected layer
- **Visibility toggle** — Tap eye icon to toggle visibility; tap layer name to select as active
- **Blend mode** — Per-layer, not exposed in main UI. Defaults: Color=Multiply, Sketch/Ink=Normal. Could be a long-press layer settings menu later
- **Layer-specific tools** — Switching layers auto-selects that layer's default stroke options
- **Z-order fixed** — Color always behind Sketch always behind Ink (no reordering needed)

## Stroke Options by Layer

| Parameter                  | Sketch      | Ink         | Color                |
|----------------------------|-------------|-------------|----------------------|
| Size                       | 2.0         | 3.0         | 16.0                 |
| Thinning (pressure→width)  | 0.4         | 0.6         | 0.8 (very sensitive) |
| Smoothing                  | 0.2 (loose) | 0.5 (clean) | 0.5                  |
| Streamline                 | 0.3         | 0.5         | 0.5                  |
| Taper start                | 0.0         | 0.1         | 0.1 (quick ramp up)  |
| Taper end                  | 0.1         | 0.2         | 0.2 (natural lift)   |

## Per-Layer Eraser

Each layer has its own eraser that only affects strokes on that layer.

### Core Behavior

Eraser paints onto a per-layer alpha mask. When the layer renders:

1. Draw all strokes to layer buffer
2. Apply eraser mask (subtracts alpha where erased)
3. Composite to canvas with layer's blend mode

This allows partial erasing, feathered edges, and refinement.

### Eraser Properties

| Property          | Options                  | Notes                                                        |
|-------------------|--------------------------|--------------------------------------------------------------|
| **Edge type**     | Hard / Soft (feathered)  | Soft uses radial gradient alpha falloff                      |
| **Size**          | Slider (1–100px)         | Base diameter                                                |
| **Pressure mode** | Constant / Tapered       | Constant ignores pressure; Tapered varies width like a brush |
| **Opacity/Flow**  | Future                   | How quickly alpha builds up per pass                         |

### Rendering Model

```
Layer composite:
+-- Stroke buffer (all strokes drawn)
+-- Eraser mask (alpha channel, starts fully opaque)
|   +-- Eraser strokes subtract alpha (paint black)
+-- Final = Stroke buffer x Eraser mask alpha
```

- **Hard edge** = eraser stroke is solid (full erase across entire width)
- **Soft edge** = eraser stroke has falloff gradient (center = full erase, edge = partial)

### Eraser UX

- Eraser mode toggle (button or S-Pen button hold)
- When active, show eraser options: edge type, size slider, pressure toggle
- Cursor/preview shows eraser size and edge softness
- Eraser strokes stored per-layer (enables undo of erasing)

### Implementation Order

1. Hard-edge constant-size eraser (simplest mask implementation)
2. Size slider
3. Pressure-sensitivity toggle (constant vs tapered)
4. Soft edge (gradient brush tip)
5. Polish: cursor preview, S-Pen button detection

## User Controls

- Layer buttons — tap name to select, tap eye icon to toggle visibility
- Color palette
- Undo (per-layer, removes last stroke or eraser stroke)
- Clear (per-layer)
- Eraser toggle with options (edge type, size, pressure mode)

---

# Project Vision & Roadmap

## Vision

Pin & Paper is a visual task app built around notecards and bullet journaling. Drawing and task management are **equal-weight pillars** — the sketchpad is not an afterthought bolted onto a to-do list, and the task system is not a sidebar to a drawing app. They are designed together.

The sketchpad module lives as a self-contained component that can be **embedded within any notecard**. A card can contain one or multiple drawings, each pinned at its own XY position. Drawings can also exist as **freestanding doodles on the background**, independent of any card — just ink on the workspace.

## Drawing Placement Model

- Each drawing instance has an **XY position** — it stays where it's placed
- A card can link to **one or multiple drawings**, each at its own position on the card
- Drawings can exist **independently of cards** as background doodles on the workspace
- **Group/ungroup** (stretch goal) — select multiple drawings and manipulate them as a single unit, à la Zinnia
- The parent app owns placement and linking; the sketchpad module exposes position/bounds and supports being embedded at arbitrary coordinates

## Module Architecture

The sketchpad is designed as a **self-contained Flutter package** with a clean boundary between itself and the host app.

### What the host app provides
- Card/container dimensions
- Save/load callbacks (persistence is the host's responsibility)
- Asset references (background images, paper textures)
- Position and transform (where the drawing sits in the workspace)

### What the module exposes
- `SketchpadWidget` — the drawing surface, embeddable anywhere
- Serialization — full drawing state to/from structured data
- State management — internal, no coupling to host state
- Bounds — the module knows its own size, the host handles placement

### Principles
- No dependency on parent app state management (Provider, Bloc, etc.)
- Serializable state: any drawing can be saved, restored, duplicated
- Position-aware but not position-owning: the module reports its bounds, the parent decides where it goes

## Near-Term Roadmap

### M1: Eraser System
Per the eraser spec above. Implementation order:
1. Hard-edge constant-size eraser
2. Size slider
3. Pressure-sensitivity toggle (constant vs tapered)
4. Soft edge (gradient brush tip)
5. Cursor preview, S-Pen button detection

### M2: Color Selection
- **Color spectrum picker** — an additional circle/wheel selector beyond the fixed palette swatches
- **Custom palettes** — user-created palettes saved per-project or globally, swappable in the toolbar

### M3: Tool Controls (size slider, pressure toggle, soft edge)
- **Size slider** for all brush presets (adjust size at runtime, not just presets)
- **Pressure sensitivity toggle** (on/off per tool — useful for mouse/trackpad users)
- **Soft edge gradient brush tip** (not just for eraser — applies to Color layer brush too)

### M4: Canvas Manipulation
- **Move** the drawing/image around the canvas
- **Resize** (pinch-to-zoom or handles)
- **Rotate** (two-finger rotation or rotation handle)
- These apply to the background reference image and potentially to individual layer content

### M5: Cursor Preview
- Show brush/eraser **size and shape** on S-Pen hover (before touching the surface)
- Preview updates in real-time as pen approaches at different pressures
- Visual indicator for current tool mode (draw vs erase)

### M6: Serialization
- Save/load full drawing state (all layers, strokes, options, eraser masks)
- Format: structured JSON or binary — needs to be compact enough for many drawings per workspace
- Enables undo history persistence, card duplication, template drawings

### M7: Module Extraction
- Extract sketchpad into a clean Flutter package
- Define the embed API for notecard integration
- Ensure no hard dependencies on the prototype app's structure

### M8: Export
- Flatten all visible layers to a single PNG
- Supports sharing, embedding as card thumbnail, printing

## Long-Term Vision

- **Custom brushes / stamp tools** — user-defined brush tips, pattern stamps
- **Animation / onion skinning** — flip-book style frame-by-frame on cards
- **Collaboration / sync** — real-time or async shared drawing surfaces
- **Asset library** — stickers, reference images, templates, reusable drawing components
- **Layer enhancements** — opacity slider per layer, user-created layers, layer merge/flatten, layer settings via long-press menu
- **Eraser opacity/flow** — control how quickly alpha builds up per eraser pass
- **Group/ungroup drawings** — select multiple drawings, move/scale/rotate as one unit

---

# Shape Correction System Spec

## Overview

A Procreate-style QuickShape system that detects when users are drawing geometric shapes and offers to snap them to perfect geometry, with an interactive adjustment phase before committing.

**Priority:** Phase 5+
**Complexity:** Medium-High
**Dependencies:** Core drawing system complete, multi-touch support

---

## Core UX Flow

```
DRAW → HOLD → SNAP → ADJUST → LIFT (confirm)
                 ↓
              UNDO → raw stroke preserved
```

The key insight: snapping is not the end state. After snap, the user enters an **interactive adjustment mode** where they can refine the shape before lifting to confirm. Undo always returns the original hand-drawn stroke, not the snapped version.

---

## Shape Behaviors

### Line

| Phase | Behavior |
|-------|----------|
| Draw | User draws a stroke |
| Hold | Pause at endpoint ~500ms without lifting |
| Snap | Stroke becomes a straight line from start → end point |
| Adjust | **Start point anchored.** Without lifting, user drags to move endpoint freely — any angle, any length. Like the end of a string pinned at one end. |
| Confirm | Lift pen to commit |
| Undo | Reverts to original raw stroke |

**Optional modifier:** Second finger tap snaps line to angle increments (0°, 15°, 30°, 45°, 90°, etc.)

---

### Arc

| Phase | Behavior |
|-------|----------|
| Draw | User draws a curved stroke |
| Hold | Pause at endpoint ~500ms |
| Snap | Stroke becomes a smooth arc (fitted to curve) |
| Adjust | Start point anchored. User drags endpoint; arc curvature/radius adjusts proportionally. |
| Confirm | Lift to commit |
| Undo | Reverts to original raw stroke |

**Optional modifier:** Second finger tap snaps to semicircle or quarter-circle

---

### Circle / Ellipse

| Phase | Behavior |
|-------|----------|
| Draw | User draws a roughly closed shape (endpoint near start point) |
| Hold | Pause near starting point ~500ms |
| Snap | Stroke becomes an ellipse fitted to the rough shape |
| Adjust | Without lifting, drag to **scale uniformly from center** — shape grows or shrinks |
| Modifier | **Tap with second finger → constrains to perfect circle** (maintains 1:1 aspect ratio) |
| Confirm | Lift to commit |
| Undo | Reverts to original raw stroke |

---

### Rectangle (Future)

| Phase | Behavior |
|-------|----------|
| Draw | User draws a roughly closed shape with 4 detected corners |
| Hold | Pause near starting point ~500ms |
| Snap | Stroke becomes a rectangle fitted to corners |
| Adjust | Drag to scale from center |
| Modifier | **Tap with second finger → constrains to perfect square** |
| Confirm | Lift to commit |
| Undo | Reverts to original raw stroke |

---

## Detection Heuristics

### Hold Detection
- Movement velocity drops below threshold
- Position stays within small radius (~5px) for ~500ms
- Timer cancels if user moves or lifts

### Shape Recognition

| Shape | Detection Criteria |
|-------|---------------------|
| Line | All points have low perpendicular variance from start→end vector |
| Arc | Points fit a circular arc segment (open stroke, curved) |
| Ellipse | Stroke is closed (end within ~30px of start) + points roughly equidistant from centroid |
| Circle | Ellipse where fitted radii are nearly equal (auto-detected, or forced via modifier) |
| Rectangle | Closed stroke + 4 corners detected (sharp direction changes ~90°) |

### Corner Detection (for rectangles)
- Identify points where stroke direction changes sharply (>60° over short distance)
- Cluster nearby corners
- Validate roughly perpendicular angles

---

## Shape Fitting Algorithms

### Line
```
start = first point
end = last point (or current drag position in adjust mode)
```

### Circle / Ellipse
Least-squares fitting:
1. Compute centroid of all points
2. For circle: average distance from centroid = radius
3. For ellipse: fit major/minor axes using covariance matrix

### Arc
1. Fit a circle to the points
2. Arc is the segment of that circle from start to end angle

### Rectangle
1. Detect 4 corners
2. Compute bounding quadrilateral
3. Optionally rotate to align with dominant edge angle

---

## Adjustment Mode Mechanics

### Anchored Endpoint (Lines/Arcs)
```
anchor = stroke start point (fixed)
drag_point = current pen position
shape = recompute line/arc from anchor → drag_point
```

### Center Scaling (Circles/Ellipses/Rectangles)
```
center = shape center (fixed)
original_radius = fitted radius at snap time
current_distance = distance from center to current pen position
scale_factor = current_distance / original_radius
new_shape = original_shape scaled by scale_factor around center
```

### Constraint Modifier (Second Finger Tap)
- Ellipse → Circle: set both radii to average of major/minor
- Rectangle → Square: set both dimensions to average

---

## State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  IDLE ──(pen down)──► DRAWING ──(hold detected)──► SNAPPED     │
│                          │                            │         │
│                          │                            ▼         │
│                     (pen lift)                    ADJUSTING     │
│                          │                         │     │      │
│                          ▼                         │     │      │
│                     RAW STROKE ◄──(undo)───────────┘     │      │
│                                                          │      │
│                     CONFIRMED ◄────(pen lift)────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Model

```dart
enum ShapeType { line, arc, circle, ellipse, rectangle }

class RecognizedShape {
  final ShapeType type;
  final List<StrokePoint> rawPoints;     // Original hand-drawn points
  final ShapeGeometry geometry;           // Computed perfect geometry
  final Offset anchor;                    // Fixed point during adjustment
  final bool isConstrained;               // e.g., circle vs ellipse

  RecognizedShape adjusted(Offset newDragPoint);
  RecognizedShape constrain();            // Apply modifier (circle/square)
}

abstract class ShapeGeometry {
  Path toPath();
}

class LineGeometry extends ShapeGeometry {
  final Offset start;
  final Offset end;
}

class CircleGeometry extends ShapeGeometry {
  final Offset center;
  final double radius;
}

class EllipseGeometry extends ShapeGeometry {
  final Offset center;
  final double radiusX;
  final double radiusY;
  final double rotation;
}

class ArcGeometry extends ShapeGeometry {
  final Offset center;
  final double radius;
  final double startAngle;
  final double sweepAngle;
}
```

---

## Multi-Touch Handling

The modifier gesture (second finger tap) requires detecting:
- S-Pen is down and in ADJUSTING state
- A finger touches screen briefly (tap, not drag)
- Trigger constraint toggle

**Android consideration:** Verify S-Pen + finger simultaneous input is reported correctly. Most Samsung devices support this, but needs testing.

```dart
// Pseudocode
void onPointerDown(PointerEvent event) {
  if (state == ShapeState.adjusting && event.kind == PointerDeviceKind.touch) {
    // Finger tap while pen is adjusting
    toggleConstraint();
    event.consume(); // Don't treat as drawing input
  }
}
```

---

## Undo Behavior

Shape correction creates a special undo state:

```dart
class ShapeStroke extends Stroke {
  final List<StrokePoint> rawPoints;      // What user actually drew
  final ShapeGeometry snappedGeometry;    // The perfect shape

  // Undo replaces this stroke with a regular Stroke using rawPoints
}
```

When user undoes a shape-corrected stroke:
1. Remove the snapped shape
2. Replace with raw hand-drawn stroke
3. (Second undo removes the raw stroke entirely)

---

## Visual Feedback

### During Hold Detection
- Subtle pulsing or highlight at pen position
- Optional: progress indicator (circular wipe around cursor)

### On Snap
- Brief animation morphing raw stroke → geometry (~150ms)
- Haptic feedback (short pulse)
- Visual indicator that adjustment mode is active

### During Adjustment
- Shape renders in real-time following drag
- Anchor point could show a subtle pin/dot
- If constrained (circle/square), show indicator

### On Confirm
- Shape finalizes
- Standard stroke appearance

---

## Configuration Options

```dart
class ShapeRecognitionSettings {
  bool enabled = true;                    // Master toggle
  Duration holdDuration = Duration(milliseconds: 500);
  double closedShapeThreshold = 30.0;     // Max distance end→start for "closed"
  double lineVarianceThreshold = 10.0;    // Max deviation for line detection
  bool hapticFeedback = true;
  bool snapToAngles = true;               // Line angle snapping
  double angleSnapIncrement = 15.0;       // Degrees
}
```

---

## Implementation Phases

### Phase 1: Lines Only
- Hold detection
- Line snapping
- Anchored endpoint adjustment
- Basic undo support

### Phase 2: Circles/Ellipses
- Closed shape detection
- Circle/ellipse fitting
- Center-based scaling adjustment
- Second finger constraint modifier

### Phase 3: Arcs
- Arc detection and fitting
- Endpoint adjustment preserving curvature

### Phase 4: Rectangles (Optional)
- Corner detection
- Rectangle fitting
- Square constraint

### Phase 5: Polish
- Animations
- Haptic feedback
- Angle snapping for lines
- Settings/preferences

---

## Testing Checklist

- [ ] Hold detection triggers at correct timing
- [ ] Line snap looks correct
- [ ] Line adjustment pivots around anchor
- [ ] Circle/ellipse detection works for rough shapes
- [ ] Scaling from center feels natural
- [ ] Second finger tap toggles circle ↔ ellipse
- [ ] Undo restores raw stroke, not snapped
- [ ] Multi-touch works correctly (S-Pen + finger)
- [ ] Performance acceptable (no lag during adjustment)
- [ ] Works on all target layers

---

## References

- Procreate QuickShape behavior (primary reference)
- Concepts app shape detection
- Apple PencilKit shape recognition (for comparison)

---

*This feature makes the app significantly more powerful for diagrams, clean boxes around tasks, geometric doodles, and UI sketching. It's a "delight" feature that rewards users who discover it.*
