import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/kakuyomu_scraper.dart';
import 'package:read_book/services/novel_repository.dart';
import 'package:read_book/utils/work_tags.dart';

const workId = '2912051605992818100';

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  late Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> fixture() => <String, dynamic>{
  'id': workId,
  'title': '新題',
  'introduction': '短い新版',
  'author': <String, dynamic>{
    'activity_name': '新作者',
    'permalink': 'https://kakuyomu.jp/users/new_author',
  },
  'genre': <String, dynamic>{'label': '現代ファンタジー'},
  'public_episode_count': 12,
  'is_completed': true,
  'tags': <dynamic>[
    <String, dynamic>{'label': '空白 あり'},
    <String, dynamic>{'label': '冒険'},
  ],
  'edited_at': 1794111469,
};

ResponseBody response(String raw, {int status = 200}) {
  return ResponseBody.fromString(
    raw,
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    },
  );
}

void main() {
  late Directory directory;
  late Box<Work> works;
  late Dio dio;
  late _Adapter adapter;
  late KakuyomuScraper scraper;
  late NovelRepository repository;
  late Work original;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'kakuyomu_work_details_refresh_test_',
    );
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WorkAdapter());
    }
    works = await Hive.openBox<Work>('works');

    adapter = _Adapter();
    adapter.handler = (_) async => response(jsonEncode(fixture()));
    dio = Dio()..httpClientAdapter = adapter;
    scraper = KakuyomuScraper(dio: dio);
    repository = NovelRepository(kakuyomuScraper: scraper);

    original = Work(
      workId: workId,
      siteIndex: Site.kakuyomu.index,
      title: '旧題',
      author: '旧作者',
      genre: '旧ジャンル',
      summary: '以前のとても長い正式なあらすじです',
      totalEpisodeCount: 10,
      checkedEpisodeCount: 3,
      lastUpdatedAt: DateTime.utc(2026, 1, 1),
      isCompleted: false,
      firstOpenedAt: DateTime.utc(2025, 12, 1),
      authorId: 'old_author',
      keyword: '旧タグ',
    );
    await works.put(workId, original);
  });

  tearDown(() async {
    dio.close(force: true);
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('API取得から解析・保存まで接続し端末側の状態を維持する', () async {
    expect(
      await repository.refreshStoredKakuyomuWorkDetails(work: original),
      isTrue,
    );

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://kakuyomu.jp/api/app/works/$workId');
    expect(request.method, 'GET');
    expect(request.followRedirects, isFalse);

    final saved = works.get(workId)!;
    expect(saved.title, '新題');
    expect(saved.author, '新作者');
    expect(saved.summary, '短い新版');
    expect(saved.genre, '現代ファンタジー');
    expect(saved.totalEpisodeCount, 12);
    expect(saved.checkedEpisodeCount, 3);
    expect(saved.firstOpenedAt, original.firstOpenedAt);
    expect(saved.lastUpdatedAt, original.lastUpdatedAt);
    expect(saved.isCompleted, isTrue);
    expect(saved.authorId, 'new_author');
    expect(WorkTags.decode(saved.keyword!), ['空白 あり', '冒険']);
    expect(identical(saved, original), isFalse);
    expect(original.title, '旧題');
    expect(original.summary, '以前のとても長い正式なあらすじです');

    await works.close();
    works = await Hive.openBox<Work>('works');
    expect(works.get(workId)!.title, '新題');
    expect(works.get(workId)!.checkedEpisodeCount, 3);
  });

  test('省略された任意情報と空あらすじで既存情報を消さない', () async {
    final json = fixture()
      ..['introduction'] = ''
      ..['public_episode_count'] = 9
      ..remove('genre')
      ..remove('tags');
    (json['author'] as Map<String, dynamic>).remove('permalink');
    adapter.handler = (_) async => response(jsonEncode(json));

    expect(
      await repository.refreshStoredKakuyomuWorkDetails(work: original),
      isTrue,
    );

    final saved = works.get(workId)!;
    expect(saved.summary, original.summary);
    expect(saved.genre, original.genre);
    expect(saved.totalEpisodeCount, 10);
    expect(saved.authorId, original.authorId);
    expect(saved.keyword, original.keyword);
  });

  test('APIの不正応答をHTMLで補わず保存もしない', () async {
    final invalidJson = fixture()..['id'] = '999';
    for (final raw in [
      '',
      '<html>作品ページ</html>',
      '[]',
      '{"broken":',
      jsonEncode(invalidJson),
    ]) {
      final before = adapter.requests.length;
      adapter.handler = (_) async => response(raw);

      await expectLater(
        repository.refreshStoredKakuyomuWorkDetails(work: original),
        throwsFormatException,
      );

      expect(adapter.requests.length, before + 1);
      expect(identical(works.get(workId), original), isTrue);
      expect(original.title, '旧題');
    }
  });

  test('HTTPエラーでは保存せず後から再試行できる', () async {
    adapter.handler = (_) async => response('{}', status: 503);

    await expectLater(
      repository.refreshStoredKakuyomuWorkDetails(work: original),
      throwsA(isA<DioException>()),
    );
    expect(identical(works.get(workId), original), isTrue);

    adapter.handler = (_) async => response(jsonEncode(fixture()));
    expect(
      await repository.refreshStoredKakuyomuWorkDetails(work: original),
      isTrue,
    );
  });

  test('許可外ホストへのリダイレクトを拒否する', () async {
    adapter.handler = (_) async => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['https://example.com/work'],
      },
    );

    await expectLater(
      repository.refreshStoredKakuyomuWorkDetails(work: original),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(1));
    expect(identical(works.get(workId), original), isTrue);
  });

  test('取得中に削除された作品を復活させない', () async {
    adapter.handler = (_) async {
      await works.delete(workId);
      return response(jsonEncode(fixture()));
    };

    expect(
      await repository.refreshStoredKakuyomuWorkDetails(work: original),
      isFalse,
    );
    expect(works.containsKey(workId), isFalse);
  });

  test('取得中の同一オブジェクトの変更を上書きしない', () async {
    adapter.handler = (_) async {
      original.checkedEpisodeCount = 8;
      await original.save();
      return response(jsonEncode(fixture()));
    };

    expect(
      await repository.refreshStoredKakuyomuWorkDetails(work: original),
      isFalse,
    );
    expect(works.get(workId)!.title, '旧題');
    expect(works.get(workId)!.checkedEpisodeCount, 8);
  });

  test('取得中に別オブジェクトへ置換された作品を上書きしない', () async {
    adapter.handler = (_) async {
      final replacement = Work(
        workId: workId,
        siteIndex: Site.kakuyomu.index,
        title: '別処理の題名',
        author: original.author,
        genre: original.genre,
        summary: original.summary,
        totalEpisodeCount: original.totalEpisodeCount,
        checkedEpisodeCount: original.checkedEpisodeCount,
        lastUpdatedAt: original.lastUpdatedAt,
        isCompleted: original.isCompleted,
      );
      await works.put(workId, replacement);
      return response(jsonEncode(fixture()));
    };

    expect(
      await repository.refreshStoredKakuyomuWorkDetails(work: original),
      isFalse,
    );
    expect(works.get(workId)!.title, '別処理の題名');
  });

  test('同一作品の重複実行を拒否し完了後は再実行できる', () async {
    final started = Completer<void>();
    final pending = Completer<ResponseBody>();
    adapter.handler = (_) {
      started.complete();
      return pending.future;
    };

    final first = repository.refreshStoredKakuyomuWorkDetails(work: original);
    await started.future;

    await expectLater(
      repository.refreshStoredKakuyomuWorkDetails(work: original),
      throwsStateError,
    );
    expect(adapter.requests, hasLength(1));

    pending.complete(response(jsonEncode(fixture())));
    expect(await first, isTrue);

    adapter.handler = (_) async => response(jsonEncode(fixture()));
    expect(
      await repository.refreshStoredKakuyomuWorkDetails(
        work: works.get(workId)!,
      ),
      isTrue,
    );
    expect(adapter.requests, hasLength(2));
  });

  test('不正な作品IDでは通信しない', () async {
    for (final id in ['', '0', '../invalid', ' $workId']) {
      await expectLater(scraper.fetchWorkMetadata(id), throwsFormatException);
    }
    expect(adapter.requests, isEmpty);
  });

  test('未登録・別サイトでは通信しない', () async {
    await works.delete(workId);

    await expectLater(
      repository.refreshStoredKakuyomuWorkDetails(work: original),
      throwsStateError,
    );

    original.siteIndex = Site.narou.index;
    await expectLater(
      repository.refreshStoredKakuyomuWorkDetails(work: original),
      throwsArgumentError,
    );

    expect(adapter.requests, isEmpty);
  });
}
