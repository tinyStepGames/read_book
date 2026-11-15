import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/screens/download_refresh_dialog.dart';
import 'package:read_book/services/download_refresh_planner.dart';

DownloadRefreshPlan createPlan({bool hasRefresh = true}) {
  return DownloadRefreshPlan([
    if (hasRefresh)
      const DownloadRefreshItem(
        episodeNo: 1,
        decision: DownloadRefreshDecision.refresh,
        latestEntry: {},
      ),
    const DownloadRefreshItem(
      episodeNo: 2,
      decision: DownloadRefreshDecision.unchanged,
      latestEntry: {},
    ),
    const DownloadRefreshItem(
      episodeNo: 3,
      decision: DownloadRefreshDecision.missingRevision,
      latestEntry: {},
    ),
    const DownloadRefreshItem(
      episodeNo: 4,
      decision: DownloadRefreshDecision.missingIdentity,
      latestEntry: {},
    ),
  ]);
}

void main() {
  Future<void> showHost(
    WidgetTester tester,
    DownloadRefreshPlan plan,
    void Function(bool) completed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final accepted = await confirmDownloadRefreshPlan(
                  context: context,
                  plan: plan,
                );
                completed(accepted);
              },
              child: const Text('予定を確認'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('予定を確認'));
    await tester.pumpAndSettle();
  }

  testWidgets('予定件数を区別して表示し承認を返す', (tester) async {
    bool? accepted;
    await showHost(tester, createPlan(), (value) => accepted = value);

    expect(accepted, isNull);
    expect(find.text('保存済みの照合対象: 4話'), findsOneWidget);
    expect(find.text('本文の再取得予定: 1話'), findsOneWidget);
    expect(find.text('既知の同じ版・本文取得なし: 1話'), findsOneWidget);
    expect(find.text('更新日時不明・本文未確認で保留: 1話'), findsOneWidget);
    expect(find.text('その他の保留予定: 1話'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('accept-download-refresh-plan')),
    );
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('実行しない操作でfalseを返す', (tester) async {
    bool? accepted;
    await showHost(tester, createPlan(), (value) => accepted = value);

    await tester.tap(
      find.byKey(const ValueKey('decline-download-refresh-plan')),
    );
    await tester.pumpAndSettle();

    expect(accepted, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('本文再取得0話なら追加ダイアログを出さない', (tester) async {
    bool? accepted;
    await showHost(
      tester,
      createPlan(hasRefresh: false),
      (value) => accepted = value,
    );

    expect(accepted, isTrue);
    expect(find.text('本文再取得の予定'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
