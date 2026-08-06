import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_sketchpad/sketchpad.dart';

/// Minimal host: only the props DrawingToolbar actually reads/reacts to
/// in these tests are wired to mutable state; everything else is a
/// static default sufficient to render.
Widget _host({
  required LayerStack layerStack,
  required StrokeOptions currentOptions,
  required ValueChanged<int> onLayerSelected,
  required ValueChanged<int> onVisibilityToggled,
  required ValueChanged<StrokeOptions> onOptionsChanged,
}) =>
    MaterialApp(
      home: Scaffold(
        body: DrawingToolbar(
          layerStack: layerStack,
          currentColor: const Color(0xFF2D2D2D),
          currentOptions: currentOptions,
          useBlend: false,
          onColorChanged: (_) {},
          onOptionsChanged: onOptionsChanged,
          onBlendChanged: (_) {},
          onLayerSelected: onLayerSelected,
          onVisibilityToggled: onVisibilityToggled,
          onEraserToggled: (_) {},
          onUndo: () {},
          onClear: () {},
        ),
      ),
    );

void main() {
  group('layer chip + eyeball unification (owner 2026-08-06)', () {
    testWidgets('tapping the layer name selects that layer, not visibility',
        (tester) async {
      final stack = LayerStack();
      int? selected;
      bool visibilityToggled = false;

      await tester.pumpWidget(_host(
        layerStack: stack,
        currentOptions: StrokeOptions.ink,
        onLayerSelected: (i) => selected = i,
        onVisibilityToggled: (_) => visibilityToggled = true,
        onOptionsChanged: (_) {},
      ));

      // The layer chip is the only place with implement names now (the
      // duplicate preset-button row was removed in the owner's
      // chip+eyeball unification, 2026-08-06). Displayed as "Pencil" per
      // the implement rename; the layer's serialized name stays 'Sketch'.
      await tester.tap(find.text('Pencil'));
      await tester.pump();

      expect(selected, 1); // Sketch is layers[1] in the default stack
      expect(visibilityToggled, isFalse);
    });

    testWidgets('tapping a layer\'s eye toggles ITS visibility, not layer '
        'selection', (tester) async {
      final stack = LayerStack();
      int? layerSelected;
      int? visibilityIndex;

      await tester.pumpWidget(_host(
        layerStack: stack,
        currentOptions: StrokeOptions.ink,
        onLayerSelected: (i) => layerSelected = i,
        onVisibilityToggled: (i) => visibilityIndex = i,
        onOptionsChanged: (_) {},
      ));

      // Three eye icons, one per layer (display order Sketch, Ink, Color).
      final eyeIcons = find.byIcon(Icons.visibility);
      expect(eyeIcons, findsNWidgets(3));

      // Tap the first one (Sketch, layers[1] in display order).
      await tester.tap(eyeIcons.first);
      await tester.pump();

      expect(visibilityIndex, 1);
      expect(layerSelected, isNull, reason: 'The eye never selects a layer');
    });
  });

  group('stroke size control (owner 2026-08-06: every implement)', () {
    testWidgets('dragging the slider reports a new size via onOptionsChanged',
        (tester) async {
      final stack = LayerStack();
      StrokeOptions? changed;

      await tester.pumpWidget(_host(
        layerStack: stack,
        currentOptions: StrokeOptions.ink, // size 3.0
        onLayerSelected: (_) {},
        onVisibilityToggled: (_) {},
        onOptionsChanged: (o) => changed = o,
      ));

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pump();

      expect(changed, isNotNull);
      expect(changed!.size, greaterThan(StrokeOptions.ink.size));
      // Only size changed — the rest of the active tool's tuning is
      // preserved by copyWith.
      expect(changed!.thinning, StrokeOptions.ink.thinning);
      expect(changed!.smoothing, StrokeOptions.ink.smoothing);
    });

    testWidgets('reset-to-default restores the active layer\'s default '
        'size and is disabled once already there', (tester) async {
      final stack = LayerStack(); // active layer defaults to Ink
      StrokeOptions? changed;

      // Start already off-default (bigger than Ink's 3.0).
      const customized = StrokeOptions(size: 10, thinning: 0.6, smoothing: 0.5, taperStart: 0.1, taperEnd: 0.2, streamline: 0.5);
      await tester.pumpWidget(_host(
        layerStack: stack,
        currentOptions: customized,
        onLayerSelected: (_) {},
        onVisibilityToggled: (_) {},
        onOptionsChanged: (o) => changed = o,
      ));

      final resetButton = find.byIcon(Icons.replay);
      expect(resetButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(find.ancestor(
          of: resetButton,
          matching: find.byType(IconButton),
        )).onPressed,
        isNotNull,
        reason: 'Off-default: reset button is enabled',
      );

      await tester.tap(resetButton);
      await tester.pump();

      expect(changed!.size, stack.activeLayer.defaultOptions.size);

      // Re-pump at the now-default size: the button disables itself.
      await tester.pumpWidget(_host(
        layerStack: stack,
        currentOptions: StrokeOptions.ink,
        onLayerSelected: (_) {},
        onVisibilityToggled: (_) {},
        onOptionsChanged: (_) {},
      ));
      expect(
        tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.replay),
          matching: find.byType(IconButton),
        )).onPressed,
        isNull,
        reason: 'At tool default: reset button has nothing to do',
      );
    });

    testWidgets('the size row is present regardless of which implement is '
        'active (every implement gets a size control)', (tester) async {
      final stack = LayerStack();
      for (final options in [
        StrokeOptions.sketch,
        StrokeOptions.ink,
        StrokeOptions.watercolor,
      ]) {
        await tester.pumpWidget(_host(
          layerStack: stack,
          currentOptions: options,
          onLayerSelected: (_) {},
          onVisibilityToggled: (_) {},
          onOptionsChanged: (_) {},
        ));
        expect(find.byType(Slider), findsOneWidget);
        expect(find.text(options.size.toStringAsFixed(1)), findsOneWidget);
      }
    });
  });
}
