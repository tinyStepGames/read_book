import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/screens/download_refresh_dialog.dart';
import 'package:read_book/services/download_refresh_planner.dart';
import 'package:read_book/services/download_refresh_runner.dart';

DownloadRefreshBatchResult resultWith(List<DownloadRefreshOutcome> outcomes) {
  return DownloadRefreshBatchResult([
    for (var index = 0; index < outcomes.length; index++)
      DownloadRefreshItemResult(
        item: DownloadRefreshItem(
          episodeNo: index + 1,
          decision: DownloadRefreshDecision.refresh,
          latestEntry: const {},
        ),
        outcome: outcomes[index],
      ),
  ]);
}

Future<void> openDialog(
  WidgetTester tester,
  RunDownloadRefresh run, {
  void Function(DownloadRefreshBatchResult?)? onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showDownloadRefreshDialog(
                context: context,
                run: run,
              );
              onClosed?.call(result);
            },
            child: const Text('開く'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('開く'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('取得・照合中と各話の進捗を表示する', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    late void Function(int, int) progress;
    var calls = 0;

    await openDialog(tester, (cancellation, onProgress) {
      calls++;
      progress = onProgress;
      return pending.future;
    });

    expect(find.text('目次を取得・照合しています…'), findsOneWidget);
    expect(calls, 1);

    progress(1, 3);
    await tester.pump();
    expect(find.text('確認済み: 1/3話'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1 / 3, 0.0001),
    );

    pending.complete(resultWith([DownloadRefreshOutcome.updated]));
    await tester.pumpAndSettle();
    expect(find.text('本文更新の結果'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });

  testWidgets('全種類の結果を分けて表示し結果を呼び出し元へ返す', (tester) async {
    final result = resultWith(DownloadRefreshOutcome.values);
    DownloadRefreshBatchResult? returned;

    await openDialog(
      tester,
      (_, onProgress) async => result,
      onClosed: (value) => returned = value,
    );
    await tester.pumpAndSettle();

    for (final text in [
      '対象: 6話',
      '本文更新: 1話',
      'タイトルのみ更新: 1話',
      '変更なし: 1話',
      '保留: 1話',
      '失敗: 1話',
      '中止: 1話',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('失敗した話があります。すべての話が更新されたわけではありません。'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(identical(returned, result), isTrue);
  });

  testWidgets('中止は要求だけ行い処理完了まではダイアログを維持する', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    late DownloadRefreshCancellation cancellation;

    await openDialog(tester, (token, onProgress) {
      cancellation = token;
      return pending.future;
    });

    await tester.tap(find.text('中止'));
    await tester.pump();

    expect(cancellation.isRequested, isTrue);
    expect(find.text('中止要求済み'), findsOneWidget);
    expect(find.text('閉じる'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '中止要求済み'))
          .onPressed,
      isNull,
    );

    pending.complete(
      resultWith([
        DownloadRefreshOutcome.updated,
        DownloadRefreshOutcome.canceled,
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('本文更新: 1話'), findsOneWidget);
    expect(find.text('中止: 1話'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });

  testWidgets('処理中は戻る操作と外側タップでは閉じない', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    await openDialog(tester, (_, onProgress) => pending.future);

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.byType(DownloadRefreshDialog), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DownloadRefreshDialog), findsOneWidget);

    pending.complete(resultWith([]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });

  testWidgets('全体エラーを成功扱いしない', (tester) async {
    var closed = false;
    DownloadRefreshBatchResult? returned;

    await openDialog(
      tester,
      (_, onProgress) async => throw StateError('test refresh failure'),
      onClosed: (value) {
        closed = true;
        returned = value;
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('本文更新を完了できませんでした'), findsOneWidget);
    expect(find.text('本文更新の結果'), findsNothing);
    expect(find.text('中止'), findsNothing);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(returned, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('対象ゼロを表示する', (tester) async {
    await openDialog(tester, (_, onProgress) async => resultWith([]));
    await tester.pumpAndSettle();

    expect(find.text('対象: 0話'), findsOneWidget);
    expect(find.text('更新対象の保存済み本文はありません。'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });

  testWidgets('不正な進捗値を表示へ反映しない', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    late void Function(int, int) progress;
    await openDialog(tester, (_, onProgress) {
      progress = onProgress;
      return pending.future;
    });

    progress(1, 3);
    await tester.pump();
    progress(4, 3);
    progress(-1, 3);
    progress(0, -1);
    await tester.pump();

    expect(find.text('確認済み: 1/3話'), findsOneWidget);

    pending.complete(resultWith([]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('強制破棄時は中止要求し遅れて届く通知を無視する', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    late DownloadRefreshCancellation cancellation;
    late void Function(int, int) progress;

    await openDialog(tester, (token, onProgress) {
      cancellation = token;
      progress = onProgress;
      return pending.future;
    });

    await tester.pumpWidget(const SizedBox.shrink());
    expect(cancellation.isRequested, isTrue);

    progress(1, 2);
    pending.complete(resultWith([DownloadRefreshOutcome.updated]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
