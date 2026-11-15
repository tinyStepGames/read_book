import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/utils/work_metadata_merger.dart';

Work createWork({
  String workId = 'work-id',
  int? siteIndex,
  String title = '作品名',
  String author = '作者',
  String genre = 'ファンタジー',
  String summary = '正式なあらすじ',
  int totalEpisodeCount = 10,
  int checkedEpisodeCount = 4,
  DateTime? lastUpdatedAt,
  bool isCompleted = false,
  DateTime? firstOpenedAt,
  String? authorId = 'author-id',
  String? keyword = 'タグ',
}) {
  return Work(
    workId: workId,
    siteIndex: siteIndex ?? Site.kakuyomu.index,
    title: title,
    author: author,
    genre: genre,
    summary: summary,
    totalEpisodeCount: totalEpisodeCount,
    checkedEpisodeCount: checkedEpisodeCount,
    lastUpdatedAt: lastUpdatedAt ?? DateTime.utc(2026, 1, 1),
    isCompleted: isCompleted,
    firstOpenedAt: firstOpenedAt,
    authorId: authorId,
    keyword: keyword,
  );
}

void main() {
  group('mergeRefreshedDetails', () {
    test('短く修正された正式なあらすじと作品情報を反映する', () {
      final existing = createWork(summary: '以前のとても長い正式なあらすじです');
      final incoming = createWork(
        title: '新しい作品名',
        author: '新しい作者名',
        genre: 'SF',
        summary: '短い新版',
        authorId: 'new-author',
        keyword: '新しいタグ',
      );

      final result = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: incoming,
        existing: existing,
      );

      expect(result.title, '新しい作品名');
      expect(result.author, '新しい作者名');
      expect(result.genre, 'SF');
      expect(result.summary, '短い新版');
      expect(result.authorId, 'new-author');
      expect(result.keyword, '新しいタグ');
      expect(result.workId, existing.workId);
      expect(result.siteIndex, existing.siteIndex);
    });

    test('空または未取得の文字列で既存情報を消さない', () {
      final existing = createWork();
      final incoming = createWork(
        title: ' ',
        author: '',
        genre: '\n',
        summary: ' \n ',
        authorId: null,
        keyword: ' ',
      );

      final result = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: incoming,
        existing: existing,
      );

      expect(result.title, existing.title);
      expect(result.author, existing.author);
      expect(result.genre, existing.genre);
      expect(result.summary, existing.summary);
      expect(result.authorId, existing.authorId);
      expect(result.keyword, existing.keyword);
    });

    test('総話数が増えても確認済み話数と読書開始日時を維持する', () {
      final opened = DateTime.utc(2025, 12, 1);
      final existing = createWork(
        checkedEpisodeCount: 3,
        firstOpenedAt: opened,
      );
      final incoming = createWork(
        totalEpisodeCount: 12,
        checkedEpisodeCount: 12,
        firstOpenedAt: DateTime.utc(2026, 2, 1),
      );

      final result = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: incoming,
        existing: existing,
      );

      expect(result.totalEpisodeCount, 12);
      expect(result.checkedEpisodeCount, 3);
      expect(result.firstOpenedAt, opened);
    });

    test('未設定の読書開始日時も取得情報から補完しない', () {
      final result = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: createWork(firstOpenedAt: DateTime.utc(2026, 2, 1)),
        existing: createWork(),
      );

      expect(result.firstOpenedAt, isNull);
    });

    test('取得した総話数が減少・ゼロ・負数でも保存済み話数を減らさない', () {
      for (final count in [9, 0, -1]) {
        final result = WorkMetadataMerger.mergeRefreshedDetails(
          incoming: createWork(totalEpisodeCount: count),
          existing: createWork(totalEpisodeCount: 10),
        );

        expect(result.totalEpisodeCount, 10);
      }
    });

    test('新しい更新日時は反映し古い日時では巻き戻さない', () {
      final existing = createWork(lastUpdatedAt: DateTime.utc(2026, 2, 1));

      for (final month in [1, 2, 3]) {
        final result = WorkMetadataMerger.mergeRefreshedDetails(
          incoming: createWork(lastUpdatedAt: DateTime.utc(2026, month, 1)),
          existing: existing,
        );

        expect(
          result.lastUpdatedAt,
          DateTime.utc(2026, month > 2 ? month : 2, 1),
        );
      }
    });

    test('完結と連載中の両方向の変更を反映する', () {
      for (final completed in [true, false]) {
        final result = WorkMetadataMerger.mergeRefreshedDetails(
          incoming: createWork(isCompleted: completed),
          existing: createWork(isCompleted: !completed),
        );

        expect(result.isCompleted, completed);
      }
    });

    test('異なる作品ID・サイト・空IDは拒否する', () {
      final existing = createWork();

      for (final incoming in [
        createWork(workId: 'other-work'),
        createWork(siteIndex: Site.narou.index),
        createWork(workId: ''),
      ]) {
        expect(
          () => WorkMetadataMerger.mergeRefreshedDetails(
            incoming: incoming,
            existing: existing,
          ),
          throwsArgumentError,
        );
      }

      expect(
        () => WorkMetadataMerger.mergeRefreshedDetails(
          incoming: createWork(workId: ' '),
          existing: createWork(workId: ' '),
        ),
        throwsArgumentError,
      );
    });

    test('入力を変更せず新しい未保存オブジェクトを返す', () {
      final existing = createWork(title: '旧題', summary: '長い旧あらすじ');
      final incoming = createWork(
        title: '新題',
        summary: '新版',
        checkedEpisodeCount: 99,
      );

      final result = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: incoming,
        existing: existing,
      );

      expect(identical(result, existing), isFalse);
      expect(identical(result, incoming), isFalse);
      expect(result.isInBox, isFalse);
      expect(existing.title, '旧題');
      expect(existing.summary, '長い旧あらすじ');
      expect(existing.checkedEpisodeCount, 4);
      expect(incoming.title, '新題');
      expect(incoming.summary, '新版');
      expect(incoming.checkedEpisodeCount, 99);

      result.title = '結果だけ変更';
      expect(existing.title, '旧題');
      expect(incoming.title, '新題');
    });
  });
}
