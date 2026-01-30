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
