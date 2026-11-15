import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/kakuyomu_work_metadata.dart';
import 'package:read_book/utils/work_tags.dart';

const workId = '2912051605992818100';

Map<String, dynamic> fixture() => <String, dynamic>{
  'id': workId,
  'title': '更新された作品名',
  'introduction': '第一段落\r\n\r\n第二段落',
  'author': <String, dynamic>{
    'id': '16818093081708477601',
    'activity_name': '作者の表示名',
    'permalink': 'https://kakuyomu.jp/users/example_author',
  },
  'alternate_author_name': null,
  'genre': <String, dynamic>{'name': 'action', 'label': '現代ファンタジー'},
  'public_episode_count': 12,
  'is_completed': false,
  'tags': <dynamic>[
    <String, dynamic>{'label': '日本語 タグ'},
    <String, dynamic>{'label': '冒険'},
  ],
};

KakuyomuWorkMetadata parse(Map<String, dynamic> json) {
  return KakuyomuWorkMetadata.fromJson(json, expectedWorkId: workId);
}

void main() {
  test('JSON応答から作品情報と作者ページIDを取り出す', () {
    final decoded = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
    final value = parse(decoded);

    expect(value.workId, workId);
    expect(value.title, '更新された作品名');
    expect(value.author, '作者の表示名');
    expect(value.summary, '第一段落\n\n第二段落');
    expect(value.genre, '現代ファンタジー');
    expect(value.episodeCount, 12);
    expect(value.isCompleted, isFalse);
    expect(value.authorId, 'example_author');
    expect(WorkTags.decode(value.keyword), ['日本語 タグ', '冒険']);
  });

  test('作者の別名が明示されていれば優先する', () {
    final json = fixture()..['alternate_author_name'] = '作品での作者名';
    expect(parse(json).author, '作品での作者名');
  });

  test('短い正式なあらすじもそのまま扱う', () {
    final json = fixture()..['introduction'] = '短い新版';
    expect(parse(json).summary, '短い新版');
  });

  test('あらすじ中の続きを読むという本文を勝手に削除しない', () {
    final json = fixture()..['introduction'] = '「続きを読む」と書かれた扉。';
    expect(parse(json).summary, '「続きを読む」と書かれた扉。');
  });

  test('空のあらすじと省略可能な情報の欠落を許可する', () {
    final json = fixture()
      ..['introduction'] = ''
      ..remove('genre')
      ..remove('tags');
    (json['author'] as Map<String, dynamic>).remove('permalink');

    final value = parse(json);
    expect(value.summary, '');
    expect(value.genre, '');
    expect(value.keyword, '');
    expect(value.authorId, isNull);
  });

  test('完結状態のtrueも扱う', () {
    expect(parse(fixture()..['is_completed'] = true).isCompleted, isTrue);
  });

  test('作品IDの欠落・型違い・別作品を拒否する', () {
    for (final id in <Object?>[null, 123, '', '999']) {
      expect(() => parse(fixture()..['id'] = id), throwsFormatException);
    }
    expect(
      () => KakuyomuWorkMetadata.fromJson(
        fixture(),
        expectedWorkId: '../invalid',
      ),
      throwsFormatException,
    );
  });

  test('必須のタイトル・作者・あらすじの型違いや欠落を拒否する', () {
    for (final key in ['title', 'introduction']) {
      for (final value in <Object?>[null, 123, <String>[]]) {
        expect(() => parse(fixture()..[key] = value), throwsFormatException);
      }
    }
    expect(() => parse(fixture()..['title'] = ' '), throwsFormatException);
    expect(() => parse(fixture()..['author'] = null), throwsFormatException);
    final json = fixture();
    (json['author'] as Map<String, dynamic>)['activity_name'] = ' ';
    expect(() => parse(json), throwsFormatException);
  });

  test('公開話数は正の整数だけ許可する', () {
    for (final count in <Object?>[null, 0, -1, 1.5, 12.0, '12', true]) {
      expect(
        () => parse(fixture()..['public_episode_count'] = count),
        throwsFormatException,
      );
    }
  });

  test('完結状態を文字列や数値から推測しない', () {
    for (final value in <Object?>[null, 'false', 'true', 0, 1]) {
      expect(
        () => parse(fixture()..['is_completed'] = value),
        throwsFormatException,
      );
    }
  });

  test('不正な作者ページURLを拒否する', () {
    for (final url in [
      'http://kakuyomu.jp/users/example',
      'https://example.com/users/example',
      'https://user@kakuyomu.jp/users/example',
      'https://kakuyomu.jp:444/users/example',
      'https://kakuyomu.jp/users/example/works',
      'https://kakuyomu.jp/users/example?x=1',
      'https://kakuyomu.jp/users/example#fragment',
      'https://kakuyomu.jp/users/bad%2Fid',
    ]) {
      final json = fixture();
      (json['author'] as Map<String, dynamic>)['permalink'] = url;
      expect(() => parse(json), throwsFormatException);
    }
  });

  test('不正なジャンルやタグを拒否する', () {
    expect(() => parse(fixture()..['genre'] = 'ジャンル'), throwsFormatException);
    for (final tags in <Object>[
      'タグ',
      <dynamic>['タグ'],
      <dynamic>[
        <String, dynamic>{'label': 123},
      ],
      <dynamic>[
        <String, dynamic>{'label': ''},
      ],
      <dynamic>[
        <String, dynamic>{'label': '不正${WorkTags.separator}タグ'},
      ],
    ]) {
      expect(() => parse(fixture()..['tags'] = tags), throwsFormatException);
    }
  });

  test('入力を変更せずタグの重複をまとめる', () {
    final json = fixture();
    (json['tags'] as List<dynamic>).add(<String, dynamic>{'label': '冒険'});
    final before = jsonEncode(json);
    final value = parse(json);

    expect(jsonEncode(json), before);
    expect(WorkTags.decode(value.keyword), ['日本語 タグ', '冒険']);

    json['title'] = '呼び出し側で変更';
    expect(value.title, '更新された作品名');
  });
}
