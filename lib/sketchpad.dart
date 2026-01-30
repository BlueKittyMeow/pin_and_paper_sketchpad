/// Pin and Paper Sketchpad
/// 
/// Pressure-sensitive drawing system with layers for the 
/// sketch → ink → color workflow.
/// 
/// ## Usage
/// 
/// ```dart
/// import 'package:pin_and_paper_sketchpad/sketchpad.dart';
/// 
/// // Create a layer stack
/// final layerStack = LayerStack();
/// 
/// // Use in a widget
/// DrawingCanvas(
///   layerStack: layerStack,
///   currentColor: Colors.black,
///   strokeOptions: StrokeOptions.ink,
///   onStrokeComplete: () => setState(() {}),
/// )
/// ```
/// 
/// ## Layers
/// 
/// Default layer stack (bottom to top):
/// - **Color**: Wide strokes, multiply blend, for fills
/// - **Sketch**: Loose strokes, 60% opacity, for rough work  
/// - **Ink**: Clean strokes, for final linework
/// 
/// ## Specs
/// 
/// See `pin_and_paper_dev_harness/docs/module_specs/SKETCHPAD_SPEC.md`
/// for full documentation.
library sketchpad;

// Models
export 'models/stroke.dart';
export 'models/layer.dart';

// Widgets
export 'widgets/drawing_canvas.dart';
export 'widgets/toolbar.dart';
