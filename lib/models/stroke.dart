import 'dart:ui';

/// A single point in a stroke with pressure data
class StrokePoint {
  final double x;
  final double y;
  final double pressure;

  const StrokePoint(this.x, this.y, this.pressure);

  Offset get offset => Offset(x, y);
}

/// A complete stroke with all its points and styling
class Stroke {
  final List<StrokePoint> points;
  final Color color;
  final StrokeOptions options;

  const Stroke({
    required this.points,
    required this.color,
    required this.options,
  });

  bool get isEmpty => points.isEmpty;
}

/// Parameters for perfect_freehand tuning
class StrokeOptions {
  final double size;
  final double thinning;
  final double smoothing;
  final double streamline;
  final double taperStart;
  final double taperEnd;
  final bool simulatePressure;

  const StrokeOptions({
    this.size = 4.0,
    this.thinning = 0.5,      // How much pressure affects width
    this.smoothing = 0.5,     // Path smoothing (lower = more energy)
    this.streamline = 0.5,    // Pull toward running average
    this.taperStart = 0.0,    // Taper at stroke start
    this.taperEnd = 0.0,      // Taper at stroke end
    this.simulatePressure = false,
  });

  /// Preset for confident ink lines (like your art style)
  static const ink = StrokeOptions(
    size: 3.0,
    thinning: 0.6,       // Noticeable pressure variation
    smoothing: 0.3,      // Low - preserve stroke energy
    streamline: 0.4,
    taperStart: 0.1,
    taperEnd: 0.2,
  );

  /// Preset for loose sketching
  static const sketch = StrokeOptions(
    size: 2.0,
    thinning: 0.4,
    smoothing: 0.2,      // Very low - keep it loose
    streamline: 0.3,
    taperStart: 0.0,
    taperEnd: 0.1,
  );

  /// Preset for brush/watercolor feel
  static const watercolor = StrokeOptions(
    size: 16.0,
    thinning: 0.8,       // Very pressure sensitive — light=fine, heavy=broad
    smoothing: 0.5,
    streamline: 0.5,
    taperStart: 0.1,     // Quick ramp up
    taperEnd: 0.2,       // Natural lift-off
  );
}
