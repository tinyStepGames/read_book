import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/app_session_service.dart';
import 'package:read_book/services/blocked_author_service.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_blocked_author_test_',
    );

    Hive.init(temporaryDirectory.path);
    await Hive.openBox<dynamic>(AppSessionService.boxName);
  });

  tearDown(() async {
    await Hive.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('作者IDを使って同じ作者をブロックできる', () async {
    final added = await BlockedAuthorService.block(
      site: Site.kakuyomu,
      authorId: 'example_author',
      authorName: '表示名変更前',
    );

    expect(added, isTrue);

    expect(
      BlockedAuthorService.isBlocked(
        site: Site.kakuyomu,
        authorId: 'example_author',
        authorName: '表示名変更後',
      ),
      isTrue,
    );
  });

  test('同じ作者IDでも掲載サイトが違えばブロックしない', () async {
    await BlockedAuthorService.block(
      site: Site.kakuyomu,
      authorId: 'same-author',
      authorName: '同じ作者',
    );

    expect(
      BlockedAuthorService.isBlocked(
        site: Site.narou,
        authorId: 'same-author',
        authorName: '同じ作者',
      ),
      isFalse,
    );
  });

  test('作者IDがない場合は正規化した作者名を使用する', () async {
    await BlockedAuthorService.block(
      site: Site.narou,
      authorId: '',
      authorName: '  テスト   作者  ',
    );

    expect(
      BlockedAuthorService.isBlocked(
        site: Site.narou,
        authorId: '',
        authorName: 'テスト 作者',
      ),
      isTrue,
    );
  });

  test('ブロックを解除できる', () async {
    await BlockedAuthorService.block(
      site: Site.kakuyomu,
      authorId: 'remove-author',
      authorName: '解除対象',
    );

    final entry = BlockedAuthorService.entries.single;
    final removed = await BlockedAuthorService.unblock(entry.key);

    expect(removed, isTrue);
    expect(BlockedAuthorService.entries, isEmpty);
  });

  test('壊れた保存値を無視する', () async {
    final box = Hive.box<dynamic>(AppSessionService.boxName);

    await box.put('blocked_authors_v1', <Object?>[
      null,
      'invalid',
      <String, Object?>{'key': '', 'siteIndex': -1},
    ]);

    expect(BlockedAuthorService.entries, isEmpty);
  });
}
