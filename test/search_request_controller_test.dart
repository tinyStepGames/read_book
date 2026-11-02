import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/search_filters.dart';
import 'package:read_book/services/search_request_controller.dart';

void main() {
  group('SearchRequest', () {
    test('既定値では絞り込みなし', () {
      const request = SearchRequest(keyword: '異世界');

      expect(request.filters.isActive, isFalse);
    });

    test('連載状態と文字数条件を保持する', () {
      const filters = SearchFilters(
        serialStatus: SearchSerialStatus.completed,
        lengthPreset: SearchLengthPreset.custom,
        customMinimumLength: 20000,
        customMaximumLength: 100000,
      );

      const request = SearchRequest(
        keyword: '異世界',
        siteIndex: 1,
        filters: filters,
      );

      expect(request.filters.serialStatus, SearchSerialStatus.completed);
      expect(request.filters.lengthPreset, SearchLengthPreset.custom);
      expect(request.filters.minimumLength, 20000);
      expect(request.filters.maximumLength, 100000);
    });
  });

  group('SearchRequestController', () {
    test('リクエストを保持して消費できる', () {
      final controller = SearchRequestController();

      const request = SearchRequest(
        keyword: 'ファンタジー',
        filters: SearchFilters(
          serialStatus: SearchSerialStatus.ongoing,
          lengthPreset: SearchLengthPreset.veryLong,
        ),
      );

      controller.request(request);

      expect(controller.value, same(request));
      expect(
        controller.value?.filters.serialStatus,
        SearchSerialStatus.ongoing,
      );
      expect(controller.value?.filters.minimumLength, 500000);

      controller.consume();

      expect(controller.value, isNull);
      controller.dispose();
    });
  });
}
