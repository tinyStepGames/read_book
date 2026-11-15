import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/services/download_refresh_planner.dart';

Download savedEpisode({
  int number = 1,
  String id = 'episode-1',
  String stamp = 'old-version',
  String workId = 'work-1',
}) {
  return Download(
    workId: workId,
    episodeNo: number,
    episodeTitle: '保存済みタイトル',
    body: '保存済み本文',
    downloadedAt: DateTime(2026),
    sourceId: id,
    sourceUpdatedAt: stamp,
  );
}

Map<String, String> latestEpisode({
  int number = 1,
  String id = 'episode-1',
  String stamp = 'new-version',
}) {
  return {
    'episodeNo': number.toString(),
    'title': '最新タイトル',
    'sourceId': id,
    'sourceUpdatedAt': stamp,
  };
}

DownloadRefreshPlan buildPlan({
  required List<Download> downloads,
  required List<Map<String, String>> entries,
  bool force = false,
}) {
  return DownloadRefreshPlanner.build(
    workId: 'work-1',
    downloads: downloads,
    episodeList: entries,
    forceRefresh: force,
  );
}

void main() {
  test('同じ識別子で改稿情報が異なれば更新対象', () {
    final plan = buildPlan(
      downloads: [savedEpisode()],
      entries: [latestEpisode()],
    );

    expect(plan.items.single.decision, DownloadRefreshDecision.refresh);
    expect(plan.refreshCount, 1);
    expect(plan.skippedCount, 0);
  });

  test('既知の改稿情報が一致すれば更新不要', () {
    final plan = buildPlan(
      downloads: [savedEpisode(stamp: 'same')],
      entries: [latestEpisode(stamp: 'same')],
    );

    expect(plan.items.single.decision, DownloadRefreshDecision.unchanged);
    expect(plan.unchangedCount, 1);
  });

  test('強制再取得でも識別子一致が必要', () {
    final matching = buildPlan(
      downloads: [savedEpisode(stamp: 'same')],
      entries: [latestEpisode(stamp: 'same')],
      force: true,
    );
    final mismatching = buildPlan(
      downloads: [savedEpisode()],
      entries: [latestEpisode(id: 'different')],
      force: true,
    );

    expect(matching.items.single.decision, DownloadRefreshDecision.refresh);
    expect(
      mismatching.items.single.decision,
      DownloadRefreshDecision.differentIdentity,
    );
  });

  test('改稿情報不明は通常更新で保留し、明示的な再取得では取得する', () {
    for (final stamps in [
      ['', ''],
      ['', 'known'],
      ['known', ''],
    ]) {
      final plan = buildPlan(
        downloads: [savedEpisode(stamp: stamps[0])],
        entries: [latestEpisode(stamp: stamps[1])],
      );

      expect(
        plan.items.single.decision,
        DownloadRefreshDecision.missingRevision,
      );
      expect(plan.refreshCount, 0);
      expect(plan.unchangedCount, 0);
      expect(plan.skippedCount, 1);

      final forced = buildPlan(
        downloads: [savedEpisode(stamp: stamps[0])],
        entries: [latestEpisode(stamp: stamps[1])],
        force: true,
      );
      expect(forced.items.single.decision, DownloadRefreshDecision.refresh);
    }
  });

  test('識別子のない旧データは強制指定でも保留', () {
    final plan = buildPlan(
      downloads: [savedEpisode(id: '')],
      entries: [latestEpisode()],
      force: true,
    );

    expect(plan.items.single.decision, DownloadRefreshDecision.missingIdentity);
    expect(plan.skippedCount, 1);
  });

  test('最新目次側の識別子が不明でも保留', () {
    final plan = buildPlan(
      downloads: [savedEpisode()],
      entries: [latestEpisode(id: '')],
    );

    expect(plan.items.single.decision, DownloadRefreshDecision.missingIdentity);
  });

  test('同じ識別子が別番号へ移動した場合は保留', () {
    final plan = buildPlan(
      downloads: [savedEpisode()],
      entries: [
        latestEpisode(id: 'inserted-episode'),
        latestEpisode(number: 2),
      ],
    );

    expect(plan.items.single.decision, DownloadRefreshDecision.movedEpisode);
  });

  test('最新目次に該当話がなければ保留し削除しない', () {
    final download = savedEpisode();
    final plan = buildPlan(downloads: [download], entries: []);

    expect(plan.items.single.decision, DownloadRefreshDecision.missingEpisode);
    expect(download.body, '保存済み本文');
  });

  test('新着話は保存済み本文の更新対象へ含めない', () {
    final plan = buildPlan(
      downloads: [savedEpisode()],
      entries: [
        latestEpisode(),
        latestEpisode(number: 2, id: 'episode-2'),
      ],
    );

    expect(plan.items, hasLength(1));
    expect(plan.items.single.episodeNo, 1);
  });

  test('目次の番号不正・番号重複・識別子重複では判定を停止', () {
    final invalidLists = <List<Map<String, String>>>[
      [
        {'episodeNo': 'invalid', 'sourceId': 'episode-1'},
      ],
      [latestEpisode(number: 0)],
      [latestEpisode(), latestEpisode(id: 'another')],
      [latestEpisode(), latestEpisode(number: 2)],
    ];

    for (final entries in invalidLists) {
      expect(
        () => buildPlan(downloads: [savedEpisode()], entries: entries),
        throwsFormatException,
      );
    }
  });

  test('別作品や保存済みデータの重複でも判定を停止', () {
    final invalidDownloads = <List<Download>>[
      [savedEpisode(workId: 'different-work')],
      [savedEpisode(), savedEpisode(id: 'another')],
      [savedEpisode(), savedEpisode(number: 2)],
      [savedEpisode(number: 0)],
    ];

    for (final downloads in invalidDownloads) {
      expect(
        () => buildPlan(downloads: downloads, entries: [latestEpisode()]),
        throwsFormatException,
      );
    }
  });

  test('入力を書き換えず、目次のコピーを変更不可で保持する', () {
    final download = savedEpisode();
    final entry = latestEpisode();
    final plan = buildPlan(downloads: [download], entries: [entry]);

    expect(download.body, '保存済み本文');
    expect(download.episodeTitle, '保存済みタイトル');
    expect(download.sourceUpdatedAt, 'old-version');

    entry['title'] = '呼び出し元で変更';
    expect(plan.items.single.latestEntry['title'], '最新タイトル');

    expect(
      () => plan.items.single.latestEntry['title'] = '変更',
      throwsUnsupportedError,
    );
    expect(() => plan.items.clear(), throwsUnsupportedError);
  });
}
