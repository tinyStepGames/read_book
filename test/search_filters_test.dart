import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/search_filters.dart';

void main() {
  group('SearchFilters', () {
    test('なろうの連載状態をAPIパラメーターへ変換する', () {
      expect(
        const SearchFilters(
          serialStatus: SearchSerialStatus.ongoing,
        ).narouTypeParameter,
        'r',
      );

      expect(
        const SearchFilters(
          serialStatus: SearchSerialStatus.completed,
        ).narouTypeParameter,
        'er',
      );

      expect(
        const SearchFilters(
          serialStatus: SearchSerialStatus.shortStory,
        ).narouTypeParameter,
        't',
      );
    });

    test('カクヨムの連載状態を検索パラメーターへ変換する', () {
      expect(
        const SearchFilters(
          serialStatus: SearchSerialStatus.ongoing,
        ).kakuyomuSerialStatusParameter,
        'ONGOING',
      );

      expect(
        const SearchFilters(
          serialStatus: SearchSerialStatus.completed,
        ).kakuyomuSerialStatusParameter,
        'COMPLETED',
      );

      expect(
        const SearchFilters(
          serialStatus: SearchSerialStatus.shortStory,
        ).kakuyomuSerialStatusParameter,
        isNull,
      );
    });

    test('短編・中編・長編・大長編の文字数範囲を返す', () {
      const short = SearchFilters(lengthPreset: SearchLengthPreset.short);
      const medium = SearchFilters(lengthPreset: SearchLengthPreset.medium);
      const long = SearchFilters(lengthPreset: SearchLengthPreset.long);
      const veryLong = SearchFilters(lengthPreset: SearchLengthPreset.veryLong);

      expect(short.minimumLength, isNull);
      expect(short.maximumLength, 20000);

      expect(medium.minimumLength, 20000);
      expect(medium.maximumLength, 100000);

      expect(long.minimumLength, 100000);
      expect(long.maximumLength, isNull);

      expect(veryLong.minimumLength, 500000);
      expect(veryLong.maximumLength, isNull);
    });

    test('任意範囲で最小値が最大値を超える場合は拒否する', () {
      const filters = SearchFilters(
        lengthPreset: SearchLengthPreset.custom,
        customMinimumLength: 100001,
        customMaximumLength: 100000,
      );

      expect(filters.validate(), isNotNull);
    });

    test('連載状態と文字数を同時に絞り込める', () {
      const filters = SearchFilters(
        serialStatus: SearchSerialStatus.completed,
        lengthPreset: SearchLengthPreset.medium,
      );

      expect(
        filters.matches(isShortStory: false, isCompleted: true, length: 50000),
        isTrue,
      );

      expect(
        filters.matches(isShortStory: false, isCompleted: false, length: 50000),
        isFalse,
      );

      expect(
        filters.matches(isShortStory: false, isCompleted: true, length: 150000),
        isFalse,
      );
    });
  });
}
