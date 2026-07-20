import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A ListTile paints its tileColor and ink splashes onto the nearest Material
// ANCESTOR. If that ancestor sits *below* a decorated background (a Container
// or DecoratedBox with a colour), the background hides both — selected-state
// tints and tap ripples never appear.
//
// Flutter 3.44 asserts on this shape; 3.41 does not. CI is pinned to 3.44 so
// the assertion catches it there, but this test states the invariant directly
// so it also fails on an older local SDK, where the assertion is unavailable
// and the bug is otherwise silent.
//
// It is a characterisation test for the composition rule, not for any one
// screen — the real screens need Firebase to pump, so they are covered by
// their own suites plus the CI assertion.
void main() {
  /// True when a Material sits between [tileFinder] and the decorated
  /// background — i.e. the tile has something to paint on.
  bool tileHasMaterialAboveBackground(WidgetTester tester) {
    final tile = find.byType(ListTile);
    expect(tile, findsOneWidget);

    var sawMaterial = false;
    var ok = false;
    tester.element(tile).visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Material) sawMaterial = true;
      // The first coloured background we meet going up must come *after* a
      // Material, otherwise it is painting over the tile's ink.
      final isColouredBackground = (widget is DecoratedBox &&
              (widget.decoration as BoxDecoration?)?.color != null) ||
          (widget is Container && widget.decoration != null);
      if (isColouredBackground) {
        ok = sawMaterial;
        return false; // stop at the first background
      }
      return true;
    });
    return ok;
  }

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('a bare ListTile inside a decorated Container is the bad shape',
      (tester) async {
    await tester.pumpWidget(host(
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const ListTile(title: Text('row')),
      ),
    ));

    expect(
      tileHasMaterialAboveBackground(tester),
      isFalse,
      reason: 'guard itself must be able to detect the defect',
    );
  });

  testWidgets('adding a transparent Material fixes it', (tester) async {
    await tester.pumpWidget(host(
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Material(
          type: MaterialType.transparency,
          child: ListTile(title: Text('row')),
        ),
      ),
    ));

    expect(tileHasMaterialAboveBackground(tester), isTrue);
  });
}
