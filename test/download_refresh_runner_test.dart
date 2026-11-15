import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/download_refresh_planner.dart';
import 'package:read_book/services/download_refresh_runner.dart';

DownloadRefreshItem item(
  int number, [
  DownloadRefreshDecision decision = DownloadRefreshDecision.refresh,
]) {
  return DownloadRefreshItem(
    episodeNo: number,
    decision: decision,
    latestEntry: Map<String, String>.unmodifiable({
      'episodeNo': number.toString(),
      'sourceId': 'episode-$number',
    }),
  );
}

void main() {
  test('成功・失敗・保留・更新不要を集計し、失敗後も続ける', () async {
    final calls = <int>[];
    final waits = <Duration>[];
    final progress = <int>[];

    final runner = DownloadRefreshRunner(
      delay: (duration) async {
        waits.add(duration);
      },
    );

    final result = await runner.run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([
        item(1),
        item(2),
        item(3),
        item(4, DownloadRefreshDecision.unchanged),
        item(5, DownloadRefreshDecision.missingIdentity),
        item(6),
      ]),
      refreshItem: (entry) async {
        calls.add(entry.episodeNo);
        if (entry.episodeNo == 2) {
          throw StateError('test failure');
        }
        return entry.episodeNo != 3;
      },
      onProgress: (completed, total) {
        expect(total, 6);
        progress.add(completed);
      },
    );

    expect(calls, [1, 2, 3, 6]);
    expect(waits, List.filled(3, const Duration(seconds: 1)));
    expect(progress, [1, 2, 3, 4, 5, 6]);
    expect(result.updatedCount, 2);
    expect(result.failedCount, 1);
    expect(result.skippedCount, 2);
    expect(result.unchangedCount, 1);
    expect(result.canceledCount, 0);
    expect(result.totalCount, 6);
  });

  test('各更新処理の完了を待って次の話へ進む', () async {
    var active = 0;
    var maximumActive = 0;

    final runner = DownloadRefreshRunner(interval: Duration.zero);
    final result = await runner.run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([item(1), item(2), item(3)]),
      refreshItem: (entry) async {
        active++;
        if (active > maximumActive) {
          maximumActive = active;
        }
        await Future<void>.delayed(Duration.zero);
        active--;
        return true;
      },
    );

    expect(maximumActive, 1);
    expect(result.updatedCount, 3);
  });

  test('キャンセル要求後も実行中の1話は結果を保持する', () async {
    final cancellation = DownloadRefreshCancellation();
    final calls = <int>[];
    final runner = DownloadRefreshRunner(interval: Duration.zero);

    final result = await runner.run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([item(1), item(2), item(3)]),
      cancellation: cancellation,
      refreshItem: (entry) async {
        calls.add(entry.episodeNo);
        cancellation.cancel();
        return true;
      },
    );

    expect(calls, [1]);
    expect(result.updatedCount, 1);
    expect(result.canceledCount, 2);
    expect(result.totalCount, 3);
  });

  test('待機中のキャンセルでは次の更新を開始しない', () async {
    final cancellation = DownloadRefreshCancellation();
    final calls = <int>[];

    final runner = DownloadRefreshRunner(
      delay: (_) async {
        cancellation.cancel();
      },
    );

    final result = await runner.run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([item(1), item(2), item(3)]),
      cancellation: cancellation,
      refreshItem: (entry) async {
        calls.add(entry.episodeNo);
        return true;
      },
    );

    expect(calls, [1]);
    expect(result.updatedCount, 1);
    expect(result.canceledCount, 2);
  });

  test('開始前のキャンセルでは更新処理を呼ばない', () async {
    final cancellation = DownloadRefreshCancellation()..cancel();
    var calls = 0;

    final result = await DownloadRefreshRunner().run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([item(1), item(2)]),
      cancellation: cancellation,
      refreshItem: (_) async {
        calls++;
        return true;
      },
    );

    expect(calls, 0);
    expect(result.canceledCount, 2);
  });

  test('同じインスタンスの同作品重複実行を拒否し、完了後は再実行可能', () async {
    final runner = DownloadRefreshRunner(interval: Duration.zero);
    final plan = DownloadRefreshPlan([item(1)]);
    var checked = false;

    Future<bool> refresh(DownloadRefreshItem entry) async {
      if (!checked) {
        checked = true;
        await expectLater(
          runner.run(
            workId: 'work-1',
            plan: plan,
            refreshItem: (_) async => true,
          ),
          throwsStateError,
        );
      }
      return true;
    }

    final first = await runner.run(
      workId: 'work-1',
      plan: plan,
      refreshItem: refresh,
    );
    final second = await runner.run(
      workId: 'work-1',
      plan: plan,
      refreshItem: refresh,
    );

    expect(checked, isTrue);
    expect(first.updatedCount, 1);
    expect(second.updatedCount, 1);
  });

  test('進捗通知の例外を本文更新の失敗として集計しない', () async {
    final runner = DownloadRefreshRunner(interval: Duration.zero);

    final result = await runner.run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([item(1), item(2)]),
      refreshItem: (_) async => true,
      onProgress: (_, _) {
        throw StateError('test progress failure');
      },
    );

    expect(result.updatedCount, 2);
    expect(result.failedCount, 0);
  });

  test('不正または重複した話番号を実行前に拒否する', () async {
    var calls = 0;
    final runner = DownloadRefreshRunner();

    for (final entries in [
      [item(0)],
      [item(1), item(1)],
    ]) {
      await expectLater(
        runner.run(
          workId: 'work-1',
          plan: DownloadRefreshPlan(entries),
          refreshItem: (_) async {
            calls++;
            return true;
          },
        ),
        throwsFormatException,
      );
    }

    expect(calls, 0);
  });

  test('空計画を処理でき、結果一覧は変更不可', () async {
    final result = await DownloadRefreshRunner().run(
      workId: 'work-1',
      plan: DownloadRefreshPlan([]),
      refreshItem: (_) async => true,
    );

    expect(result.totalCount, 0);
    expect(result.updatedCount, 0);
    expect(() => result.items.clear(), throwsUnsupportedError);
  });
}
