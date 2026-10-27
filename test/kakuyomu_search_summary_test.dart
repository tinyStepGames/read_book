import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:read_book/utils/kakuyomu_search_summary.dart';

void main() {
  group('KakuyomuSearchSummary.extract', () {
    test('右側のキャッチコピーではなくタイトル下の説明を取得する', () {
      final document = html_parser.parse('''
        <div id="card">
          <h3>
            <a title="テスト作品" href="/works/1234567890">
              テスト作品
            </a>
          </h3>

          <a
            href="/works/1234567890"
            class="LinkAppearance_block"
          >
            <div class="partialGiftWidgetWeakText WeakText_weakText__example">
              【毎日1話 20:00投稿！】
              何処にでもいる少年が冒険者になる物語です。
            </div>
          </a>

          <div class="AdjustableWorkItem_catchphrases">
            <div class="EyeCatch_catchphrase__example">
              <a href="/works/1234567890">
                弱くても、無力でも、誰かを守れる人になりたい
              </a>
            </div>
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      final summary = KakuyomuSearchSummary.extract(
        container: container,
        workId: '1234567890',
      );

      expect(summary, '【毎日1話 20:00投稿！】 何処にでもいる少年が冒険者になる物語です。');
      expect(summary, isNot(contains('弱くても、無力でも')));
    });

    test('別作品の説明を誤って取得しない', () {
      final document = html_parser.parse('''
        <div id="card">
          <a href="/works/other-work">
            <div class="WeakText_weakText__example">
              別作品の説明です。
            </div>
          </a>

          <a href="/works/target-work">
            <div class="WeakText_weakText__example">
              対象作品の説明です。
            </div>
          </a>
        </div>
      ''');

      final container = document.querySelector('#card');

      final summary = KakuyomuSearchSummary.extract(
        container: container,
        workId: 'target-work',
      );

      expect(summary, '対象作品の説明です。');
    });

    test('キャッチコピーしかない場合は空文字を返す', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="EyeCatch_catchphrase__example">
            <a href="/works/1234567890">
              これは右側のキャッチコピーです。
            </a>
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      final summary = KakuyomuSearchSummary.extract(
        container: container,
        workId: '1234567890',
      );

      expect(summary, isEmpty);
    });

    test('旧形式の説明要素にも対応する', () {
      final document = html_parser.parse('''
        <div id="card">
          <div class="widget-workCard-introduction">
            旧形式の短い作品説明です。
          </div>
        </div>
      ''');

      final container = document.querySelector('#card');

      final summary = KakuyomuSearchSummary.extract(
        container: container,
        workId: '1234567890',
      );

      expect(summary, '旧形式の短い作品説明です。');
    });
  });
}
