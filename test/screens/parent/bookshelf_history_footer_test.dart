import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/parent/widgets/bookshelf_history_footer.dart';
import 'package:lumi_reading_tracker/theme/lumi_tokens.dart';

void main() {
  Widget buildFooter({
    bool hasMore = true,
    bool loading = false,
    Object? error,
    VoidCallback? onLoadMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: BookshelfHistoryFooter(
          loadedSessionCount: 30,
          hasMore: hasMore,
          loading: loading,
          error: error,
          onLoadMore: onLoadMore ?? () {},
          bottomClearance: 92,
        ),
      ),
    );
  }

  testWidgets('uses the library colour and explains the pagination action',
      (tester) async {
    await tester.pumpWidget(buildFooter());

    expect(find.text('More books may be waiting'), findsOneWidget);
    expect(
      find.text('This shelf uses the 30 most recent reading sessions.'),
      findsOneWidget,
    );
    expect(find.text('Load older history'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      LumiTokens.yellow,
    );
  });

  testWidgets('disables the action and shows progress while loading',
      (tester) async {
    await tester.pumpWidget(buildFooter(loading: true));

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Loading earlier sessions…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('turns a pagination error into a safe retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      buildFooter(
        error: StateError('offline'),
        onLoadMore: () => retried = true,
      ),
    );

    expect(find.text("Older history didn't load"), findsOneWidget);
    expect(find.text('Your current bookshelf is still here.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('shows a quiet completion state when all history is loaded',
      (tester) async {
    await tester.pumpWidget(buildFooter(hasMore: false));

    expect(
      find.text('All 30 reading sessions are included'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });
}
