import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:read_book/utils/episode_source_metadata.dart';

Element updateElement(String content) {
  return html_parser
      .parse('<div class="p-eplist__update">$content</div>')
      .querySelector('.p-eplist__update')!;
}

void main() {
  group('なろうの改稿情報', () {
    test('公開日ではなく改稿属性を読み取り、日本標準時からUTCへ変換する', () {
      final element = updateElement(
        '2026/10/01 10:00'
        '<span title="2026/11/15 12:34 改稿">（<u>改</u>）</span>',
      );

      expect(
        EpisodeSourceMetadata.narouUpdatedAt(element),
        '2026-11-15T03:34:00.000Z',
      );
    });

    test('秒がある場合は保持する', () {
      final element = updateElement(
        '<span title="2026/11/15 12:34:56 改稿">改</span>',
      );

      expect(
        EpisodeSourceMetadata.narouUpdatedAt(element),
        '2026-11-15T03:34:56.000Z',
      );
    });

    test('公開日だけなら改稿日時は不明', () {
      expect(
        EpisodeSourceMetadata.narouUpdatedAt(updateElement('2026/11/15 12:34')),
        isEmpty,
      );
    });

    test('title属性に改稿の明示がなければ使用しない', () {
      expect(
        EpisodeSourceMetadata.narouUpdatedAt(
          updateElement('<span title="2026/11/15 12:34">掲載</span>'),
        ),
        isEmpty,
      );
    });

    test('不正な日付や時刻を繰り上げて採用しない', () {
      for (final date in [
        '2026/02/30 12:00',
        '2026/13/01 12:00',
        '2026/11/15 25:00',
        '2026/11/15 12:60',
        '2026/11/15 12:00:60',
      ]) {
        expect(
          EpisodeSourceMetadata.narouUpdatedAt(
            updateElement('<span title="$date 改稿">改</span>'),
          ),
          isEmpty,
          reason: date,
        );
      }
    });

    test('異なる改稿日時が複数あれば推測しない', () {
      expect(
        EpisodeSourceMetadata.narouUpdatedAt(
          updateElement(
            '<span title="2026/11/14 12:00 改稿">改</span>'
            '<span title="2026/11/15 12:00 改稿">改</span>',
          ),
        ),
        isEmpty,
      );
    });

    test('要素がなくても空文字', () {
      expect(EpisodeSourceMetadata.narouUpdatedAt(null), isEmpty);
    });
  });

  group('カクヨムの改稿情報', () {
    test('Unix秒をUTCとして変換する', () {
      expect(
        EpisodeSourceMetadata.kakuyomuUpdatedAt(1700000000),
        '2023-11-14T22:13:20.000Z',
      );
    });

    test('整数文字列も受け入れる', () {
      expect(
        EpisodeSourceMetadata.kakuyomuUpdatedAt(' 1700000000 '),
        '2023-11-14T22:13:20.000Z',
      );
    });

    test('1秒の差を保持する', () {
      expect(
        EpisodeSourceMetadata.kakuyomuUpdatedAt(1700000001),
        '2023-11-14T22:13:21.000Z',
      );
    });

    test('不明・不正・ミリ秒・小数を日時として採用しない', () {
      for (final value in <Object?>[
        null,
        '',
        'null',
        'invalid',
        true,
        0,
        -1,
        1700000000.5,
        '1700000000.5',
        1700000000000,
        '999999999999999999999999999',
      ]) {
        expect(
          EpisodeSourceMetadata.kakuyomuUpdatedAt(value),
          isEmpty,
          reason: '$value',
        );
      }
    });
  });
}
