import 'dart:ui';

/// Round to 2 decimals — stroke point JSON dominates payload size.
double round2(double value) => (value * 100).roundToDouble() / 100;

/// Serialize a color as an ARGB hex string, e.g. `#FF4A3F35`.
///
/// The `& 0xFFFFFFFF` mask is belt-and-braces: `toARGB32()` already
/// returns a non-negative value for every color (Dart ints are not
/// Java ints — verified by test), so the mask never changes the result;
/// it just makes "the radix string can never be negative" a local
/// guarantee instead of an upstream contract.
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Parse an ARGB hex string produced by [colorToHex].
Color colorFromHex(String hex) {
  final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null || cleaned.length != 8) {
    throw FormatException('Invalid color hex string: "$hex"');
  }
  return Color(value);
}

/// A single point in a stroke with pressure data
class StrokePoint {
  final double x;
  final double y;
  final double pressure;

  const StrokePoint(this.x, this.y, this.pressure);

  Offset get offset => Offset(x, y);

  @override
  bool operator ==(Object other) =>
      other is StrokePoint &&
      other.x == x &&
      other.y == y &&
      other.pressure == pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);
}

/// A complete stroke with all its points and styling
class Stroke {
  final List<StrokePoint> points;
  final Color color;
  final StrokeOptions options;
  final bool isEraser;

  const Stroke({
    required this.points,
    required this.color,
    required this.options,
    this.isEraser = false,
  });

  bool get isEmpty => points.isEmpty;

  /// Serialization format v1: points as `[x, y, p]` triples rounded to
  /// 2 decimals (arrays, not objects — 3x smaller).
  Map<String, dynamic> toJson() => {
        'color': colorToHex(color),
        'isEraser': isEraser,
        'options': options.toJson(),
        'points': [
          for (final p in points)
            [round2(p.x), round2(p.y), round2(p.pressure)],
        ],
      };

  /// Throws [FormatException] for malformed point entries (anything
  /// that is not an `[x, y, pressure]` array of at least 3 numbers)
  /// instead of leaking a RangeError/TypeError from blind indexing.
  factory Stroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? const [];
    final points = <StrokePoint>[];
    for (final p in rawPoints) {
      if (p is! List ||
          p.length < 3 ||
          p[0] is! num ||
          p[1] is! num ||
          p[2] is! num) {
        throw FormatException(
            'Invalid stroke point: expected an [x, y, pressure] array of '
            'numbers, got: $p');
      }
      points.add(StrokePoint(
        (p[0] as num).toDouble(),
        (p[1] as num).toDouble(),
        (p[2] as num).toDouble(),
      ));
    }
    return Stroke(
      points: points,
      color: colorFromHex(json['color'] as String),
      options:
          StrokeOptions.fromJson(json['options'] as Map<String, dynamic>),
      isEraser: json['isEraser'] as bool? ?? false,
    );
  }
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
    smoothing: 0.5,      // Moderate - clean lines without wobble
    streamline: 0.5,
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

  Map<String, dynamic> toJson() => {
        'size': size,
        'thinning': thinning,
        'smoothing': smoothing,
        'streamline': streamline,
        'taperStart': taperStart,
        'taperEnd': taperEnd,
        'simulatePressure': simulatePressure,
      };

  factory StrokeOptions.fromJson(Map<String, dynamic> json) => StrokeOptions(
        size: (json['size'] as num?)?.toDouble() ?? 4.0,
        thinning: (json['thinning'] as num?)?.toDouble() ?? 0.5,
        smoothing: (json['smoothing'] as num?)?.toDouble() ?? 0.5,
        streamline: (json['streamline'] as num?)?.toDouble() ?? 0.5,
        taperStart: (json['taperStart'] as num?)?.toDouble() ?? 0.0,
        taperEnd: (json['taperEnd'] as num?)?.toDouble() ?? 0.0,
        simulatePressure: json['simulatePressure'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is StrokeOptions &&
      other.size == size &&
      other.thinning == thinning &&
      other.smoothing == smoothing &&
      other.streamline == streamline &&
      other.taperStart == taperStart &&
      other.taperEnd == taperEnd &&
      other.simulatePressure == simulatePressure;

  @override
  int get hashCode => Object.hash(size, thinning, smoothing, streamline,
      taperStart, taperEnd, simulatePressure);
}
