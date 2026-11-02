import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/saved_search.dart';
import 'package:read_book/models/search_filters.dart';

void main() {
  SavedSearch createSavedSearch({
    int serialStatusIndex = 0,
    int lengthPresetIndex = 0,
    int? customMinimumLength,
    int? customMaximumLength,
  }) {
    return SavedSearch(
      id: 'saved-search',
      siteIndex: 1,
      keyword: '異世界',
      order: 'new',
      serialStatusIndex: serialStatusIndex,
      lengthPresetIndex: lengthPresetIndex,
      customMinimumLength: customMinimumLength,
      customMaximumLength: customMaximumLength,
    );
  }

  group('SavedSearch filters', () {
    test('既存データ相当の既定値は絞り込みなし', () {
      final saved = createSavedSearch();

      expect(saved.serialStatus, SearchSerialStatus.all);
      expect(saved.lengthPreset, SearchLengthPreset.all);
      expect(saved.filters.isActive, isFalse);
    });

    test('連載状態と大長編を復元する', () {
      final saved = createSavedSearch(
        serialStatusIndex: SearchSerialStatus.ongoing.index,
        lengthPresetIndex: SearchLengthPreset.veryLong.index,
      );

      expect(saved.filters.serialStatus, SearchSerialStatus.ongoing);
      expect(saved.filters.lengthPreset, SearchLengthPreset.veryLong);
      expect(saved.filters.minimumLength, 500000);
      expect(saved.filters.maximumLength, isNull);
    });

    test('任意の文字数範囲を復元する', () {
      final saved = createSavedSearch(
        lengthPresetIndex: SearchLengthPreset.custom.index,
        customMinimumLength: 10000,
        customMaximumLength: 50000,
      );

      expect(saved.filters.lengthPreset, SearchLengthPreset.custom);
      expect(saved.filters.minimumLength, 10000);
      expect(saved.filters.maximumLength, 50000);
    });

    test('範囲外のenum番号は絞り込みなしとして扱う', () {
      final saved = createSavedSearch(
        serialStatusIndex: 999,
        lengthPresetIndex: -1,
      );

      expect(saved.serialStatus, SearchSerialStatus.all);
      expect(saved.lengthPreset, SearchLengthPreset.all);
    });

    test('同じフィルター条件を一致と判定する', () {
      final saved = createSavedSearch(
        serialStatusIndex: SearchSerialStatus.completed.index,
        lengthPresetIndex: SearchLengthPreset.custom.index,
        customMinimumLength: 20000,
        customMaximumLength: 100000,
      );

      const filters = SearchFilters(
        serialStatus: SearchSerialStatus.completed,
        lengthPreset: SearchLengthPreset.custom,
        customMinimumLength: 20000,
        customMaximumLength: 100000,
      );

      expect(saved.matchesFilters(filters), isTrue);
    });

    test('文字数範囲が違えば別の条件と判定する', () {
      final saved = createSavedSearch(
        lengthPresetIndex: SearchLengthPreset.custom.index,
        customMinimumLength: 20000,
        customMaximumLength: 100000,
      );

      const filters = SearchFilters(
        lengthPreset: SearchLengthPreset.custom,
        customMinimumLength: 20001,
        customMaximumLength: 100000,
      );

      expect(saved.matchesFilters(filters), isFalse);
    });
  });
}
