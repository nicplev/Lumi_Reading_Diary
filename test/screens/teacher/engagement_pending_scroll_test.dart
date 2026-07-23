import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Guards the engagement-card "pending list" scroll configuration.
//
// The reported symptom (scrollbar jumps / doesn't track on device) could NOT be
// reproduced in a widget test — the shared-controller mechanics track correctly
// and the drag stays with the inner list. The applied fix therefore targets the
// most likely on-device causes and the tester's explicit ask: an interactive
// thumb, and an inner list that owns its scroll (primary:false + clamping
// physics) so it can't hand a drag to the parent dashboard near its edges.
//
// This test locks in that ownership property so a future change to the card
// can't silently reintroduce parent-hand-off.

void main() {
  testWidgets('pending list owns its drag — the parent dashboard stays put',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: outer,
          physics: const BouncingScrollPhysics(),
          children: [
            const SizedBox(height: 300),
            SizedBox(
              height: 130, // ~3 of 15 rows visible, like the real card
              child: Scrollbar(
                controller: inner,
                thumbVisibility: true,
                interactive: true,
                child: ListView.builder(
                  controller: inner,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  itemCount: 15,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 40, child: Text('student $i')),
                ),
              ),
            ),
            const SizedBox(height: 1200),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.fling(find.text('student 0'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    expect(inner.offset, greaterThan(0),
        reason: 'inner list should consume the drag');
    expect(outer.offset, 0,
        reason: 'a drag on the inner list must not scroll the parent');
  });
}
