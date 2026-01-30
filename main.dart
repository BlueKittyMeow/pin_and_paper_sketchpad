import 'package:flutter/material.dart';
import 'models/stroke.dart';
import 'models/layer.dart';
import 'widgets/drawing_canvas.dart';
import 'widgets/toolbar.dart';

void main() {
  runApp(const SketchpadApp());
}

class SketchpadApp extends StatelessWidget {
  const SketchpadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pin & Paper Sketchpad Prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B7355), // Warm wood
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SketchpadScreen(),
    );
  }
}

class SketchpadScreen extends StatefulWidget {
  const SketchpadScreen({super.key});

  @override
  State<SketchpadScreen> createState() => _SketchpadScreenState();
}

class _SketchpadScreenState extends State<SketchpadScreen> {
  late LayerStack _layerStack;
  Color _currentColor = const Color(0xFF2D2D2D); // Near black
  StrokeOptions _currentOptions = StrokeOptions.ink;
  bool _useBlend = true;
  bool _debugPressure = true; // Start with debug on for testing

  @override
  void initState() {
    super.initState();
    _layerStack = LayerStack();
  }

  void _handleUndo() {
    setState(() {
      _layerStack.undoOnActiveLayer();
    });
  }

  void _handleClear() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear layer?'),
        content: Text('Clear all strokes from "${_layerStack.activeLayer.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _layerStack.activeLayer.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sketchpad Prototype'),
        backgroundColor: const Color(0xFFD4B896), // Kraft paper
        actions: [
          // Debug toggle
          IconButton(
            icon: Icon(_debugPressure ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _debugPressure = !_debugPressure),
            tooltip: 'Toggle pressure debug',
          ),
          // Info button
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfo,
            tooltip: 'Info',
          ),
        ],
      ),
      body: Column(
        children: [
          // Drawing area
          Expanded(
            child: Container(
              color: const Color(0xFFF5F1E8), // Cream paper background
              child: DrawingCanvas(
                layerStack: _layerStack,
                currentColor: _currentColor,
                strokeOptions: _currentOptions,
                debugPressure: _debugPressure,
                onStrokeComplete: () => setState(() {}),
                // TODO: Add your scanned card texture here
                // backgroundImage: const AssetImage('assets/VintagePaper8.png'),
              ),
            ),
          ),
          
          // Toolbar
          DrawingToolbar(
            layerStack: _layerStack,
            currentColor: _currentColor,
            currentOptions: _currentOptions,
            useBlend: _useBlend,
            onColorChanged: (color) => setState(() => _currentColor = color),
            onOptionsChanged: (options) => setState(() => _currentOptions = options),
            onBlendChanged: (blend) {
              setState(() {
                _useBlend = blend;
                // Update active layer's blend mode
                _layerStack.activeLayer.blendMode = 
                    blend ? BlendMode.multiply : BlendMode.srcOver;
              });
            },
            onUndo: _handleUndo,
            onClear: _handleClear,
          ),
        ],
      ),
    );
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sketchpad Prototype'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Testing S-Pen pressure & stroke rendering\n',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('• Draw to test pressure sensitivity'),
            Text('• Watch the debug overlay for pressure values'),
            Text('• Tap layer buttons to switch layers'),
            Text('• Long-press layer to toggle visibility'),
            Text('• Try different tool presets (Ink/Sketch/Brush)'),
            Text('• Toggle Blend to see multiply vs opaque'),
            SizedBox(height: 12),
            Text(
              'Checklist:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('☐ Pressure values changing (not stuck at 0.5)?'),
            Text('☐ Stroke taper looks natural?'),
            Text('☐ Line quality feels good?'),
            Text('☐ Layers work (visibility toggle)?'),
            Text('☐ Would you draw a Woolfie with this?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}
