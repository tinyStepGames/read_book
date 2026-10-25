import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/utils/kakuyomu_author_search.dart';

void main() {
  group('KakuyomuAuthorSearch', () {
    test('作者作品一覧URLを生成する', () {
      final uri = KakuyomuAuthorSearch.buildWorksUri(
        authorId: 'example_author-1',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'kakuyomu.jp');
      expect(uri.path, '/users/example_author-1/works');
      expect(uri.queryParameters, isEmpty);
    });

    test('2ページ目以降ではpageを付ける', () {
      final uri = KakuyomuAuthorSearch.buildWorksUri(
        authorId: 'example_author',
        page: 3,
      );

      expect(uri.queryParameters, <String, String>{'page': '3'});
    });

    test('作者IDの前後の空白を除去する', () {
      final uri = KakuyomuAuthorSearch.buildWorksUri(
        authorId: '  example_author  ',
      );

      expect(uri.path, '/users/example_author/works');
    });

    test('危険な作者IDを拒否する', () {
      for (final authorId in <String>[
        '',
        '   ',
        '../example',
        'example/works',
        r'example\works',
        'example:443',
        'example?x=1',
        'example#fragment',
        '作者名',
      ]) {
        expect(
          () => KakuyomuAuthorSearch.buildWorksUri(authorId: authorId),
          throwsFormatException,
          reason: authorId,
        );
      }
    });
  });
}
