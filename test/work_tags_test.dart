import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/utils/work_tags.dart';

void main() {
  group('WorkTags', () {
    test('カクヨムタグ内の半角空白を保持する', () {
      final encoded = WorkTags.encode(const <String>['異世界 ファンタジー', '主人公最強']);

      expect(WorkTags.decode(encoded), const <String>['異世界 ファンタジー', '主人公最強']);
    });

    test('カクヨムタグ内の全角空白を保持する', () {
      final encoded = WorkTags.encode(const <String>['現代　ドラマ', '日常']);

      expect(WorkTags.decode(encoded), const <String>['現代　ドラマ', '日常']);
    });

    test('空タグと前後の空白を除去する', () {
      final encoded = WorkTags.encode(const <String>[
        '  タグA  ',
        '',
        '  ',
        'タグB',
      ]);

      expect(WorkTags.decode(encoded), const <String>['タグA', 'タグB']);
    });

    test('既存の空白区切りデータを従来どおり読み込む', () {
      expect(WorkTags.decode('異世界 ファンタジー　主人公最強'), const <String>[
        '異世界',
        'ファンタジー',
        '主人公最強',
      ]);
    });

    test('Work.tagsでも新形式のタグ境界を維持する', () {
      final encoded = WorkTags.encode(const <String>['空白を含む タグ', '別タグ']);

      final work = Work(
        workId: 'work-id',
        siteIndex: Site.kakuyomu.index,
        title: '作品',
        author: '作者',
        genre: 'ファンタジー',
        summary: '概要',
        totalEpisodeCount: 1,
        checkedEpisodeCount: 1,
        lastUpdatedAt: DateTime.utc(2026, 1, 1),
        isCompleted: false,
        keyword: encoded,
      );

      expect(work.tags, const <String>['空白を含む タグ', '別タグ']);
    });
  });
}
