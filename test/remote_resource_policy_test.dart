import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/utils/remote_resource_policy.dart';

void main() {
  group('RemoteResourcePolicy', () {
    test('なろうのHTTPS話URLを受け入れる', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'https://ncode.syosetu.com/n3380le/1/',
      );

      expect(uri, isNotNull);
      expect(uri.toString(), 'https://ncode.syosetu.com/n3380le/1/');
    });

    test('カクヨムのHTTPS話URLを受け入れる', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.kakuyomu,
        source: 'https://kakuyomu.jp/works/123/episodes/456',
      );

      expect(uri, isNotNull);
      expect(uri.toString(), 'https://kakuyomu.jp/works/123/episodes/456');
    });

    test('フラグメントを除去する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'https://ncode.syosetu.com/n3380le/1/#section',
      );

      expect(uri, isNotNull);
      expect(uri.toString(), 'https://ncode.syosetu.com/n3380le/1/');
    });

    test('平文HTTPを拒否する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'http://ncode.syosetu.com/n3380le/1/',
      );

      expect(uri, isNull);
    });

    test('許可ホストに見せかけた別ドメインを拒否する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'https://ncode.syosetu.com.example.com/n3380le/1/',
      );

      expect(uri, isNull);
    });

    test('対象サイトと異なるホストを拒否する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.kakuyomu,
        source: 'https://ncode.syosetu.com/n3380le/1/',
      );

      expect(uri, isNull);
    });

    test('ユーザー情報を含むURLを拒否する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'https://user@ncode.syosetu.com/n3380le/1/',
      );

      expect(uri, isNull);
    });

    test('443以外の明示的なポートを拒否する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'https://ncode.syosetu.com:8443/n3380le/1/',
      );

      expect(uri, isNull);
    });

    test('空のパスを拒否する', () {
      final uri = RemoteResourcePolicy.normalizeEpisodeUri(
        site: Site.narou,
        source: 'https://ncode.syosetu.com/',
      );

      expect(uri, isNull);
    });
  });
}
