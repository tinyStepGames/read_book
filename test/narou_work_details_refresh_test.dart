import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/narou_api_client.dart';
import 'package:read_book/services/novel_repository.dart';

class _TestNarouClient extends NarouApiClient {
  int calls = 0;
  late Future<NarouSearchResult?> Function(String) handler;

  @override
  Future<NarouSearchResult?> fetchByNcode(String ncode) {
    calls++;
    return handler(ncode);
  }
}

NarouSearchResult result({
  String ncode = 'N3380LE',
  String title = '新題',
  String author = '新作者',
  String summary = '新版',
  int count = 12,
  int end = 0,
  int novelType = 1,
  int biggenre = 4,
  Site site = Site.narou,
}) {
  return NarouSearchResult(
    title: title,
    ncode: ncode,
    authorId: 'new-author',
    author: author,
    summary: summary,
    biggenre: biggenre,
    genre: 401,
    keyword: '新しいタグ',
    generalFirstup: '',
    generalLastup: '2026-11-15 12:00:00',
    end: end,
    length: 1000,
    favNovelCnt: 10,
    generalAllNo: count,
    novelType: novelType,
    site: site,
  );
}

void main() {
  late Directory directory;
  late Box<Work> works;
  late _TestNarouClient client;
  late NovelRepository repository;
  late Work original;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'narou_work_details_refresh_test_',
    );
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WorkAdapter());
    }
    works = await Hive.openBox<Work>('works');
    client = _TestNarouClient();
    client.handler = (_) async => result();
    repository = NovelRepository(narouApiClient: client);
    original = Work(
      workId: 'n3380le',
      siteIndex: Site.narou.index,
      title: '旧題',
      author: '旧作者',
      genre: 'ファンタジー',
      summary: '以前のとても長い正式なあらすじです',
      totalEpisodeCount: 10,
      checkedEpisodeCount: 3,
      lastUpdatedAt: DateTime(2026, 1, 1),
      isCompleted: false,
      firstOpenedAt: DateTime.utc(2025, 12, 1),
      authorId: 'old-author',
      keyword: '旧タグ',
    );
    await works.put(original.workId, original);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('APIの作品情報を保存し確認済み話数と読書開始日時を維持する', () async {
    client.handler = (id) async {
      expect(id, 'n3380le');
      return result();
    };

    expect(
      await repository.refreshStoredNarouWorkDetails(work: original),
      isTrue,
    );

    final saved = works.get('n3380le')!;
    expect(saved.title, '新題');
    expect(saved.author, '新作者');
    expect(saved.summary, '新版');
    expect(saved.genre, 'SF');
    expect(saved.totalEpisodeCount, 12);
    expect(saved.checkedEpisodeCount, 3);
    expect(saved.firstOpenedAt, DateTime.utc(2025, 12, 1));
    expect(saved.isCompleted, isTrue);
    expect(saved.authorId, 'new-author');
    expect(saved.keyword, '新しいタグ');
    expect(saved.lastUpdatedAt, DateTime.parse('2026-11-15 12:00:00'));
    expect(identical(saved, original), isFalse);
    expect(original.title, '旧題');
    expect(original.summary, '以前のとても長い正式なあらすじです');

    await works.close();
    works = await Hive.openBox<Work>('works');
    expect(works.get('n3380le')!.title, '新題');
    expect(works.get('n3380le')!.checkedEpisodeCount, 3);
  });

  test('空のあらすじと減少した話数では既存情報を消さない', () async {
    client.handler = (_) async => result(summary: ' ', count: 9);

    expect(
      await repository.refreshStoredNarouWorkDetails(work: original),
      isTrue,
    );
    final saved = works.get('n3380le')!;
    expect(saved.summary, original.summary);
    expect(saved.totalEpisodeCount, 10);
  });

  test('通信失敗では元オブジェクトを変更せず再試行できる', () async {
    client.handler = (_) async => throw StateError('test network failure');

    await expectLater(
      repository.refreshStoredNarouWorkDetails(work: original),
      throwsStateError,
    );
    expect(identical(works.get('n3380le'), original), isTrue);
    expect(original.title, '旧題');

    client.handler = (_) async => result();
    expect(
      await repository.refreshStoredNarouWorkDetails(work: original),
      isTrue,
    );
  });

  test('作品なし・別作品・不正な応答を保存しない', () async {
    final responses = <NarouSearchResult?>[
      null,
      result(ncode: 'N9999ZZ'),
      result(site: Site.kakuyomu),
      result(title: ' '),
      result(author: ''),
      result(count: 0),
      result(end: 2),
      result(novelType: 0),
      result(biggenre: 0),
    ];

    for (final response in responses) {
      client.handler = (_) async => response;
      await expectLater(
        repository.refreshStoredNarouWorkDetails(work: original),
        throwsFormatException,
      );
      expect(identical(works.get('n3380le'), original), isTrue);
      expect(original.title, '旧題');
    }
  });

  test('通信中に削除された作品を復活させない', () async {
    client.handler = (_) async {
      await works.delete('n3380le');
      return result();
    };

    expect(
      await repository.refreshStoredNarouWorkDetails(work: original),
      isFalse,
    );
    expect(works.containsKey('n3380le'), isFalse);
  });

  test('通信中の同一オブジェクトの変更を上書きしない', () async {
    client.handler = (_) async {
      original.checkedEpisodeCount = 8;
      await original.save();
      return result();
    };

    expect(
      await repository.refreshStoredNarouWorkDetails(work: original),
      isFalse,
    );
    expect(works.get('n3380le')!.title, '旧題');
    expect(works.get('n3380le')!.checkedEpisodeCount, 8);
  });

  test('通信中に別オブジェクトへ置換された作品を上書きしない', () async {
    client.handler = (_) async {
      final replacement = Work(
        workId: original.workId,
        siteIndex: original.siteIndex,
        title: '別処理で保存した題名',
        author: original.author,
        genre: original.genre,
        summary: original.summary,
        totalEpisodeCount: original.totalEpisodeCount,
        checkedEpisodeCount: original.checkedEpisodeCount,
        lastUpdatedAt: original.lastUpdatedAt,
        isCompleted: original.isCompleted,
      );
      await works.put(original.workId, replacement);
      return result();
    };

    expect(
      await repository.refreshStoredNarouWorkDetails(work: original),
      isFalse,
    );
    expect(works.get('n3380le')!.title, '別処理で保存した題名');
  });

  test('同じ作品の重複実行を拒否し完了後は再実行できる', () async {
    final pending = Completer<NarouSearchResult?>();
    client.handler = (_) => pending.future;

    final first = repository.refreshStoredNarouWorkDetails(work: original);

    await expectLater(
      repository.refreshStoredNarouWorkDetails(work: original),
      throwsStateError,
    );
    expect(client.calls, 1);

    pending.complete(result());
    expect(await first, isTrue);

    client.handler = (_) async => result();
    expect(
      await repository.refreshStoredNarouWorkDetails(
        work: works.get('n3380le')!,
      ),
      isTrue,
    );
    expect(client.calls, 2);
  });

  test('未登録・別サイト・不正IDでは通信しない', () async {
    await works.delete('n3380le');

    await expectLater(
      repository.refreshStoredNarouWorkDetails(work: original),
      throwsStateError,
    );

    original.siteIndex = Site.kakuyomu.index;
    await expectLater(
      repository.refreshStoredNarouWorkDetails(work: original),
      throwsArgumentError,
    );

    original.siteIndex = Site.narou.index;
    original.workId = 'invalid';
    await expectLater(
      repository.refreshStoredNarouWorkDetails(work: original),
      throwsArgumentError,
    );

    expect(client.calls, 0);
  });
}
