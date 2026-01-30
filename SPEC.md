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
| Streamline                 | 0.3         | 0.4         | 0.5                  |
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

## Future Considerations

- Opacity slider per layer
- Additional layers (user-created)
- Layer merge/flatten
- Layer settings menu (blend mode, opacity) via long-press
- Export flattened PNG
- Eraser opacity/flow control
