import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/auth/admin_use_web_portal_screen.dart';

void main() {
  testWidgets('renders portal hand-off content and the la_blue artwork',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AdminUseWebPortalScreen()),
    );
    // Let the one-shot entrance animations finish.
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Manage Your School on the Web'), findsOneWidget);
    expect(find.text('Open Web Portal'), findsOneWidget);
    expect(find.text('Copy portal link'), findsOneWidget);
    expect(find.text('https://lumi-school-admin.web.app'), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/staff_characters/la_blue.png',
    );
  });
}
