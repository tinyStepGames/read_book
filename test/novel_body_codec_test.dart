import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:read_book/utils/novel_body_codec.dart';

void main() {
  group('NovelBodyCodec', () {
    test('みてみんのプロトコル相対URLをHTTPSで保持する', () {
      final document = html_parser.parseFragment(
        '<div>本文'
        '<img src="//img1.mitemin.net/example/test.jpg" '
        'alt="挿絵(By みてみん)">'
        '</div>',
      );
      final element = document.querySelector('div')!;

      final encoded = NovelBodyCodec.encodeElement(element);

      expect(NovelBodyCodec.isRichBody(encoded), isTrue);
      expect(
        encoded,
        contains('src="https://img1.mitemin.net/example/test.jpg"'),
      );
      expect(encoded, contains('alt="挿絵(By みてみん)"'));
      expect(NovelBodyCodec.containsSafeIllustration(encoded), isTrue);
    });

    test('altがない安全な画像には既定の代替テキストを設定する', () {
      final document = html_parser.parseFragment(
        '<div><img src="https://img1.mitemin.net/example/test.png"></div>',
      );

      final encoded = NovelBodyCodec.encodeElement(
        document.querySelector('div')!,
      );

      expect(encoded, contains('alt="挿絵"'));
    });

    test('みてみん以外の画像を除去する', () {
      final document = html_parser.parseFragment(
        '<div>前'
        '<img src="https://example.com/image.jpg" alt="危険な画像">'
        '後</div>',
      );

      final encoded = NovelBodyCodec.encodeElement(
        document.querySelector('div')!,
      );

      expect(encoded, isNot(contains('<img')));
      expect(encoded, contains('前後'));
      expect(NovelBodyCodec.containsSafeIllustration(encoded), isFalse);
    });

    test('HTTP、data、JavaScriptスキームを拒否する', () {
      expect(
        NovelBodyCodec.normalizeIllustrationUri(
          'http://img1.mitemin.net/test.jpg',
        ),
        isNull,
      );
      expect(
        NovelBodyCodec.normalizeIllustrationUri('data:image/png;base64,AAAA'),
        isNull,
      );
      expect(
        NovelBodyCodec.normalizeIllustrationUri('javascript:alert(1)'),
        isNull,
      );
    });

    test('mitemin.netに見せかけた別ドメインを拒否する', () {
      expect(
        NovelBodyCodec.normalizeIllustrationUri(
          'https://evil-mitemin.net/test.jpg',
        ),
        isNull,
      );
      expect(
        NovelBodyCodec.normalizeIllustrationUri(
          'https://mitemin.net.example.com/test.jpg',
        ),
        isNull,
      );
    });

    test('スクリプトなどの危険な要素を保持しない', () {
      final document = html_parser.parseFragment(
        '<div>本文<script>alert(1)</script>'
        '<iframe src="https://example.com"></iframe></div>',
      );

      final encoded = NovelBodyCodec.encodeElement(
        document.querySelector('div')!,
      );

      expect(encoded, isNot(contains('script')));
      expect(encoded, isNot(contains('iframe')));
      expect(encoded, contains('本文'));
    });
  });
}
