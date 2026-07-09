# Fable — Sketchpad Module Review

**Date:** 2026-07-09
**Scope:** All code in `lib/` (~1,000 lines). The prototype works and the layer/eraser architecture is sound. Findings below are ordered by how much they matter for integration (see `pin_and_paper_dev_harness/docs/fable-integration-review.md`).

---

## 1. Bugs in current code

### 1.1 `LayerStack` crashes with custom layers
`lib/models/layer.dart:69-71` — the constructor accepts any `layers` list but hardcodes `_activeLayerIndex = 2`. `LayerStack(layers: [DrawingLayer.ink()])` → `RangeError` on the first `activeLayer` access. Fix:

```dart
LayerStack({List<DrawingLayer>? layers})
    : layers = layers ?? _defaultLayers() {
  _activeLayerIndex = this.layers.length - 1; // top layer
}
```

### 1.2 No pointer-ID tracking → multi-touch corrupts strokes
`lib/widgets/drawing_canvas.dart` — the `Listener` appends every `PointerMoveEvent` to `_currentPoints` regardless of which pointer it came from. A second finger (or a resting palm — this is an S-Pen device!) interleaves its points into the active stroke, producing zigzag garbage. Fix:

- Record `event.pointer` on down; ignore move/up events from other pointers.
- Add basic palm rejection: when a `PointerDownEvent` with `kind == PointerDeviceKind.stylus` arrives, cancel any in-progress touch stroke; optionally add a `stylusOnly` flag to the widget so card/journal contexts can require the pen.

### 1.3 No `onPointerCancel` handling
If the system cancels a pointer (palm gesture, notification shade, app switch), `_currentPoints` is silently abandoned — the partial stroke ghost-renders until the next down. Add `onPointerCancel:` that either commits or discards the stroke (discard is fine; pick one deliberately).

---

## 2. API alignment with the spec

The harness spec (`SKETCHPAD_SPEC.md`, `ARCHITECTURE_AND_HARNESS.md`) names the public widget `Sketchpad` with an `onChanged` callback; the code exports `DrawingCanvas` with `onStrokeComplete`. Either is fine — **pick one and update the other**, because canvas/card_renderer models will be implemented against the spec text. Suggested minimal move: add `typedef`-level compatibility by renaming `DrawingCanvas` → `Sketchpad` and keeping `onStrokeComplete` (more precise name), then fix the spec.

Also: `toolbar.dart` and `main.dart` are demo/prototype UI. Move them under `example/` (per the harness testing strategy: "run module's example/ app") so the package's `lib/` exports only the reusable surface: models + `Sketchpad`.

---

## 3. Serialization — the blocker for everything downstream

`CardDrawingSource` and `JournalDataSource` both persist `LayerStack`, which currently cannot be serialized. This blocks card drawings (Phase 4.5) and the journal (Phase 6). Implement before any drawing-persistence work:

```jsonc
// LayerStack.toJson() — format v1
{
  "v": 1,
  "activeLayer": 2,
  "layers": [
    {
      "id": "ink_...",
      "name": "Ink",
      "visible": true,
      "opacity": 1.0,
      "blendMode": "srcOver",          // enum name, not index (survives Flutter upgrades)
      "strokes": [
        {
          "color": "#FF4A3F35",         // ARGB hex
          "isEraser": false,
          "options": {"size": 4.0, "thinning": 0.6, "smoothing": 0.5,
                       "streamline": 0.5, "taperStart": 0, "taperEnd": 0,
                       "simulatePressure": false},
          "points": [[x, y, pressure], ...]   // arrays, not objects — 3× smaller
        }
      ]
    }
  ]
}
```

Rules for the implementer:
- Round-trip test required: `LayerStack.fromJson(stack.toJson())` reproduces identical rendering.
- Store points as `[x, y, p]` triples rounded to 2 decimals — stroke JSON dominates payload size.
- Version field (`"v": 1`) from day one; `fromJson` must reject/upgrade unknown versions explicitly.
- Serialize `BlendMode` and any enums by **name**.

---

## 4. Undo/redo

Current undo is `removeLastStroke()` on the *active layer only* — undo after switching layers removes the wrong thing, and there is no redo. Replace with a single history stack on `LayerStack`:

```dart
// Each entry: (layerId, stroke). Undo pops and removes from that layer;
// redo re-adds. Cap at ~100 entries. Clearing a layer pushes a composite entry.
```

This is ~40 lines and makes behavior match user expectation ("undo undoes my last action, wherever it was").

---

## 5. Performance path for embedding (read before Phase 4.5)

The current painter re-tessellates **every stroke of every layer on every frame** (`shouldRepaint => true`, `getStroke()` per stroke in `paint()`). Fine for one full-screen pad; fatal for a desk of 30 cards each carrying a doodle. The embedding strategy (also in the integration review §4):

1. **Completed drawings are images.** When a drawing is saved/closed, render the `LayerStack` to a `ui.Image` (via `PictureRecorder` at 2× logical resolution) and cache it (memory + PNG on disk keyed by content hash). The canvas/journal display the image only.
2. **Only the live editor runs the painter**, and even there: keep committed strokes in a cached `ui.Picture` rebuilt on stroke-complete, and paint only the in-progress stroke per frame. This turns per-frame cost from O(all strokes) to O(current stroke).
3. Wrap the editor in a `RepaintBoundary`.

Do not ship 4.5 card-drawing integration without step 1; it's the difference between "works in the harness demo" and "works with a real desk".

---

## 6. Minor

- `withOpacity` is deprecated in current Flutter (`drawing_canvas.dart:197`) → `.withValues(alpha: ...)`.
- `_normalizePressure` treats exactly `1.0` as "no pressure support" — a real stylus at max pressure gets snapped to 0.5 mid-stroke. Better: decide per-*stroke* (if every point so far is 0.0 or 1.0, treat as unsupported), or per-device via `event.kind == stylus`.
- Layer IDs use `DateTime.now().millisecondsSinceEpoch` — two layers created in the same millisecond collide. Use a counter or `Object().hashCode`; matters once serialization keys on IDs.
- Tests: only a smoke test exists. Highest-value additions: LayerStack constructor edge cases (§1.1), serialization round-trip (§3), undo/redo ordering (§4). Pointer logic can be tested with `WidgetTester.createGesture(kind: stylus)`.

## Suggested order

§1 fixes (an hour) → §2 API rename + example/ split → §3 serialization → §4 undo stack → §5 raster cache when card integration starts.
