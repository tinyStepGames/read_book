import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/narou_api_client.dart';

void main() {
  test('なろうのnovel_typeが2なら短編と表示する', () {
    final result = NarouSearchResult.fromJson(<String, dynamic>{
      'title': '短編作品',
      'ncode': 'N0000AA',
      'userid': 1,
      'writer': '作者',
      'story': 'あらすじ',
      'biggenre': 99,
      'genre': 9999,
      'keyword': '',
      'general_firstup': '2026-10-01 00:00:00',
      'general_lastup': '2026-10-01 00:00:00',
      'end': 0,
      'length': 5000,
      'fav_novel_cnt': 0,
      'general_all_no': 1,
      'noveltype': 2,
    });

    expect(result.isShortStory, isTrue);
    expect(result.isCompleted, isFalse);
    expect(result.statusLabel, '短編');
  });

  test('完結済み連載1話は短編へ誤変換しない', () {
    final result = NarouSearchResult.fromJson(<String, dynamic>{
      'title': '全1話の連載作品',
      'ncode': 'N0001AA',
      'userid': 1,
      'writer': '作者',
      'story': 'あらすじ',
      'biggenre': 99,
      'genre': 9999,
      'keyword': '',
      'general_firstup': '2026-10-01 00:00:00',
      'general_lastup': '2026-10-01 00:00:00',
      'end': 0,
      'length': 5000,
      'fav_novel_cnt': 0,
      'general_all_no': 1,
      'novel_type': 1,
    });

    expect(result.isShortStory, isFalse);
    expect(result.isCompleted, isTrue);
    expect(result.statusLabel, '連載完結 全1話');
  });
}
