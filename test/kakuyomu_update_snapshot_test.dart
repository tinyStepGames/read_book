import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/kakuyomu_scraper.dart';

void main() {
  group('KakuyomuUpdateSnapshot', () {
    test('公式APIの公開話数と連載中状態を取得する', () {
      final snapshot = KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
        'public_episode_count': 71,
        'is_completed': false,
        'episodes': <Object>[],
      });

      expect(snapshot.episodeCount, 71);
      expect(snapshot.isCompleted, isFalse);
    });

    test('公式APIの完結状態を取得する', () {
      final snapshot = KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
        'public_episode_count': 99,
        'is_completed': true,
      });

      expect(snapshot.episodeCount, 99);
      expect(snapshot.isCompleted, isTrue);
    });

    test('公開話数が文字列でも取得できる', () {
      final snapshot = KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
        'public_episode_count': '123',
        'is_completed': false,
      });

      expect(snapshot.episodeCount, 123);
      expect(snapshot.isCompleted, isFalse);
    });

    test('公開話数がない旧形式ではエピソード配列を使用する', () {
      final snapshot = KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
        'is_completed': false,
        'episodes': <Object>[
          <String, dynamic>{'id': 'episode-1'},
          <String, dynamic>{'id': 'episode-2'},
        ],
      });

      expect(snapshot.episodeCount, 2);
      expect(snapshot.isCompleted, isFalse);
    });

    test('公開話数とエピソード配列が両方なければ拒否する', () {
      expect(
        () => KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
          'public_episode_count': 0,
          'is_completed': false,
        }),
        throwsFormatException,
      );
    });

    test('完結状態が欠けていれば拒否する', () {
      expect(
        () => KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
          'public_episode_count': 71,
        }),
        throwsFormatException,
      );
    });

    test('文字列の完結状態は誤変換せず拒否する', () {
      expect(
        () => KakuyomuUpdateSnapshot.fromJson(<String, dynamic>{
          'public_episode_count': 71,
          'is_completed': 'false',
        }),
        throwsFormatException,
      );
    });
  });
}
