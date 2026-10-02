import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/background_episode_parser.dart';
import 'package:read_book/utils/novel_body_codec.dart';

void main() {
  group('BackgroundEpisodeParser', () {
    test('なろうの画像だけの本文を保持する', () {
      const html = '''
<html>
  <body>
    <div class="p-novel__body">
      <div class="p-novel__text">
        <img
          src="//img1.mitemin.net/example/illustration.jpg"
          alt="挿絵(By みてみん)"
        >
      </div>
    </div>
  </body>
</html>
''';

      final body = BackgroundEpisodeParser.parse(site: Site.narou, html: html);

      expect(NovelBodyCodec.isRichBody(body), isTrue);
      expect(
        body,
        contains('src="https://img1.mitemin.net/example/illustration.jpg"'),
      );
      expect(body, contains('alt="挿絵(By みてみん)"'));
    });

    test('なろうの前書きが画像だけでもセクションを保持する', () {
      const html = '''
<html>
  <body>
    <div class="p-novel__body">
      <div class="p-novel__text p-novel__text--preface">
        <img
          src="https://img1.mitemin.net/example/preface.png"
          alt="前書きの挿絵"
        >
      </div>
      <div class="p-novel__text">
        本文です。
      </div>
    </div>
  </body>
</html>
''';

      final body = BackgroundEpisodeParser.parse(site: Site.narou, html: html);

      expect(body, contains('<strong>【前書き】</strong>'));
      expect(
        body,
        contains('src="https://img1.mitemin.net/example/preface.png"'),
      );
      expect(body, contains('<strong>【本文】</strong>'));
      expect(body, contains('本文です。'));
    });

    test('許可されていない画像だけの本文は空として拒否する', () {
      const html = '''
<html>
  <body>
    <div class="p-novel__body">
      <div class="p-novel__text">
        <img
          src="https://example.com/not-allowed.jpg"
          alt="外部画像"
        >
      </div>
    </div>
  </body>
</html>
''';

      expect(
        () => BackgroundEpisodeParser.parse(site: Site.narou, html: html),
        throwsStateError,
      );
    });
  });
}
