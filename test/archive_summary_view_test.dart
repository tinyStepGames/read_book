import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/widgets/archive_summary_view.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness: あらすじ枠の背景と外観を確認する', (tester) async {
      final theme = ThemeData(brightness: brightness);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: ArchiveSummaryView(
              title: '作品名',
              summary: '短いあらすじです。',
              previewLines: 6,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('archive-summary-frame')),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(
        decoration.color,
        brightness == Brightness.dark
            ? Colors.black
            : theme.colorScheme.surface,
      );
      expect(container.constraints!.maxHeight, 220);
      expect(container.padding, const EdgeInsets.all(10));
      expect(decoration.borderRadius, BorderRadius.circular(8));

      final body = tester.widget<Text>(
        find.byKey(const ValueKey('archive-inline-summary-body')),
      );
      expect(body.style!.fontSize, 13);
      expect(body.style!.height, 1.6);
      expect(body.maxLines, isNull);

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.thumbVisibility, isFalse);
      expect(scrollbar.trackVisibility, isFalse);
      expect(scrollbar.thickness, 6);

      final scrollable = find.descendant(
        of: find.byType(ArchiveSummaryView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('長いあらすじを枠内で末尾までスクロールできる', (tester) async {
    final summary = List.generate(
      100,
      (index) => '第${index + 1}段落のあらすじです。',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ArchiveSummaryView(
                title: '作品名',
                summary: summary,
                previewLines: 6,
              ),
              const Text('各話一覧'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('各話一覧'), findsOneWidget);

    final body = tester.widget<Text>(
      find.byKey(const ValueKey('archive-inline-summary-body')),
    );
    expect(body.data, summary);
    expect(body.maxLines, isNull);

    final scrollable = find.descendant(
      of: find.byType(ArchiveSummaryView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      find.byKey(const ValueKey('archive-inline-summary-scroll')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.extentAfter, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('狭い画面で文字を拡大しても表示があふれない', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              ArchiveSummaryView(
                title: '作品名',
                summary: List.filled(50, '長いあらすじです。').join('\n'),
                previewLines: 6,
              ),
              const Text('各話一覧'),
            ],
          ),
        ),
      ),
    );

    final scrollable = find.descendant(
      of: find.byType(ArchiveSummaryView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(find.text('各話一覧'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空のあらすじでは枠を表示しない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArchiveSummaryView(
            title: '作品名',
            summary: ' \n ',
            previewLines: 6,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('archive-summary-frame')), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
