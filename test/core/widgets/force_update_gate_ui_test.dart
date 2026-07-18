import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/force_update_gate.dart';
import 'package:lumi_reading_tracker/theme/lumi_tokens.dart';

void main() {
  testWidgets('version gate uses the new Lumi UI and welcome artwork',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VersionGateLayout(
          title: 'Lumi needs a quick version check',
          message: 'Test version message',
          actions: SizedBox.shrink(),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, LumiTokens.cream);

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, versionGateArtwork);
    expect(image.semanticLabel, 'Lumi welcome illustration');

    final heading = tester.widget<Text>(
      find.text('Lumi needs a quick version check'),
    );
    expect(heading.style?.color, LumiTokens.ink);
  });
}
