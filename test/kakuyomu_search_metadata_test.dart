import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:read_book/utils/kakuyomu_search_metadata.dart';

void main() {
  group('KakuyomuSearchMetadata.episodeCount', () {
    test('紹介文の毎日1話ではなくメタ情報の182話を取得する', () {
      final document = html_parser.parse('''
        <div id="card">
          <a href="/works/example">
            <div class="introduction">
              【毎日1話 20:00投稿！】何処にでもいる少年の物語。
            </div>
          </a>
          <div class="WorkMetaBasicInformation_example">
            <ul>
              <li><div class="Meta_metaItem_example">★58</div></li>
              <li><div class="Meta_metaItem_example">現代ファンタジー</div></li>
              <li><div class="Meta_metaItem_example">連載中 182話</div></li>
              <li><div class="Meta_metaItem_example">576,546文字</div></li>
            </ul>
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      expect(KakuyomuSearchMetadata.episodeCount(container), 182);
    });

    test('完結済み全99話を取得する', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="widget-workCard-meta">
            <ul>
              <li>完結済み 全99話</li>
            </ul>
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      expect(KakuyomuSearchMetadata.episodeCount(container), 99);
    });

    test('カンマ区切りの話数を取得する', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="WorkMetaBasicInformation_example">
            <ul>
              <li>連載中 1,234話</li>
            </ul>
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      expect(KakuyomuSearchMetadata.episodeCount(container), 1234);
    });

    test('紹介文にしか話数がない場合は誤認せず0を返す', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="introduction">
            毎日1話ずつ投稿しています。
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      expect(KakuyomuSearchMetadata.episodeCount(container), 0);
    });
  });
}
