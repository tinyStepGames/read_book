import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/services/download_refresh_planner.dart';
import 'package:read_book/services/download_refresh_runner.dart';

DownloadRefreshPlan unknownPlan(int count, {bool force = false}) {
  return DownloadRefreshPlanner.build(
    workId: 'work-1',
    downloads: [
      for (var number = 1; number <= count; number++)
        Download(
          workId: 'work-1',
          episodeNo: number,
          episodeTitle: '保存済み$number',
          body: '保存済み本文',
          downloadedAt: DateTime.utc(2026),
          sourceId: 'episode-$number',
        ),
    ],
    episodeList: [
      for (var number = 1; number <= count; number++)
        {
          'episodeNo': '$number',
          'sourceId': 'episode-$number',
          'title': '最新$number',
          'sourceUpdatedAt': '',
        },
    ],
    forceRefresh: force,
  );
}

void main() {
  test('日時不明1000話の通常更新では本文取得も通信間隔の待機も行わない', () async {
    var calls = 0;
    var waits = 0;
    final runner = DownloadRefreshRunner(
      delay: (_) async {
        waits++;
      },
    );

    final result = await runner.run(
      workId: 'work-1',
      plan: unknownPlan(1000),
      refreshItem: (_) async {
        calls++;
        return true;
      },
    );

    expect(calls, 0);
    expect(waits, 0);
    expect(result.totalCount, 1000);
    expect(result.updatedCount, 0);
    expect(result.unchangedCount, 0);
    expect(result.skippedCount, 1000);
    expect(result.unknownRevisionCount, 1000);
  });

  test('日時不明でも明示的な再取得なら取得し、通信間隔は維持する', () async {
    var calls = 0;
    var waits = 0;
    final runner = DownloadRefreshRunner(
      delay: (_) async {
        waits++;
      },
    );

    final result = await runner.run(
      workId: 'work-1',
      plan: unknownPlan(2, force: true),
      refreshItem: (_) async {
        calls++;
        return true;
      },
    );

    expect(calls, 2);
    expect(waits, 1);
    expect(result.updatedCount, 2);
    expect(result.unknownRevisionCount, 0);
  });

  test('日時不明と識別情報不足を混同しない', () async {
    final plan = DownloadRefreshPlanner.build(
      workId: 'work-1',
      downloads: [
        Download(
          workId: 'work-1',
          episodeNo: 1,
          episodeTitle: '保存済み',
          body: '本文',
          downloadedAt: DateTime.utc(2026),
        ),
      ],
      episodeList: [
        {'episodeNo': '1', 'sourceId': 'episode-1'},
      ],
      forceRefresh: true,
    );

    var calls = 0;
    final result = await DownloadRefreshRunner().run(
      workId: 'work-1',
      plan: plan,
      refreshItem: (_) async {
        calls++;
        return true;
      },
    );

    expect(calls, 0);
    expect(result.skippedCount, 1);
    expect(result.unknownRevisionCount, 0);
  });
}
