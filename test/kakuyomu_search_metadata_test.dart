import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:read_book/utils/kakuyomu_search_metadata.dart';

void main() {
  group('KakuyomuSearchMetadata', () {
    test('紹介文の毎日1話ではなく公式メタ情報の182話を取得する', () {
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

      final metadata = KakuyomuSearchMetadata.read(
        document.querySelector('#card'),
      );

      expect(metadata.episodeCount, 182);
      expect(metadata.characterCount, 576546);
      expect(metadata.starCount, 58);
      expect(metadata.serialStatus, KakuyomuSerialStatus.ongoing);
    });

    test('レビューの完結という語を無視して連載中と判定する', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="review">
            コメント失礼します。完結作品のエラーについて。
            ★999を目指します。全500,000文字の予定です。
          </div>
          <div class="WorkMetaBasicInformation_example">
            <ul>
              <li><div class="Meta_metaItem_example">★135</div></li>
              <li><div class="Meta_metaItem_example">連載中 71話</div></li>
              <li><div class="Meta_metaItem_example">126,429文字</div></li>
            </ul>
          </div>
        </div>
      ''');

      final metadata = KakuyomuSearchMetadata.read(
        document.querySelector('#card'),
      );

      expect(metadata.episodeCount, 71);
      expect(metadata.characterCount, 126429);
      expect(metadata.starCount, 135);
      expect(metadata.serialStatus, KakuyomuSerialStatus.ongoing);
    });

    test('完結済み全99話を完結として取得する', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="widget-workCard-meta">
            <ul>
              <li>完結済み 全99話</li>
              <li>100,000文字</li>
              <li>★1,234</li>
            </ul>
          </div>
        </div>
      ''');

      final metadata = KakuyomuSearchMetadata.read(
        document.querySelector('#card'),
      );

      expect(metadata.episodeCount, 99);
      expect(metadata.characterCount, 100000);
      expect(metadata.starCount, 1234);
      expect(metadata.serialStatus, KakuyomuSerialStatus.completed);
    });

    test('公式メタ情報がなければ紹介文を誤認しない', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="introduction">
            毎日1話ずつ投稿します。
            完結保証、全500,000文字、★999を目標にしています。
          </div>
        </div>
      ''');

      final metadata = KakuyomuSearchMetadata.read(
        document.querySelector('#card'),
      );

      expect(metadata.episodeCount, 0);
      expect(metadata.characterCount, 0);
      expect(metadata.starCount, 0);
      expect(metadata.serialStatus, KakuyomuSerialStatus.unknown);
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

      expect(
        KakuyomuSearchMetadata.episodeCount(document.querySelector('#card')),
        1234,
      );
    });
  });
}
