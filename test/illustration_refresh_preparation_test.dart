import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/utils/novel_body_codec.dart';

void main() {
  late Directory directory;
  late Uint8List bytes;
  late int loadCount;
  int? failAt;

  const firstUrl = 'https://img1.mitemin.net/example/first.jpg';
  const secondUrl = 'https://img1.mitemin.net/example/second.jpg';
  const body = '${NovelBodyCodec.prefix}<img src="$firstUrl">';

  String localPath(String value) {
    return html_parser
        .parseFragment(NovelBodyCodec.payloadOf(value))
        .querySelector('img')!
        .attributes['data-local-src']!;
  }

  IllustrationStorageService createService({
    int imageLimit = 20,
    int imageBytes = 20 * 1024 * 1024,
    int episodeBytes = 60 * 1024 * 1024,
  }) {
    return IllustrationStorageService(
      rootDirectoryProvider: () async => directory,
      maximumImagesPerEpisode: imageLimit,
      maximumImageBytes: imageBytes,
      maximumEpisodeBytes: episodeBytes,
      loader: (uri, maximumBytes) async {
        loadCount++;
        if (loadCount == failAt) {
          throw StateError('test image failure');
        }
        return IllustrationPayload(bytes: bytes, contentType: 'image/jpeg');
      },
    );
  }

  Future<String> prepare(IllustrationStorageService service, String value) {
    return service.prepareRefreshedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: value,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'read_book_illustration_refresh_test_',
    );
    bytes = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
    loadCount = 0;
    failAt = null;
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('同じURLで画像内容が変わっても通常保存の旧画像を上書きしない', () async {
    final service = createService();
    final originalBytes = Uint8List.fromList(bytes);

    final oldBody = await service.localizeDownloadedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: body,
    );
    final oldPath = localPath(oldBody);
    final oldFile = (await service.resolveLocalFile(oldPath))!;

    bytes = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x20]);

    final refreshed = await prepare(service, body);
    final newPath = localPath(refreshed);
    final newFile = (await service.resolveLocalFile(newPath))!;

    expect(newPath, isNot(oldPath));
    expect(await oldFile.readAsBytes(), orderedEquals(originalBytes));
    expect(await newFile.readAsBytes(), orderedEquals(bytes));
    expect(loadCount, 2);
  });

  test('更新準備済み画像でも内容が変われば別ファイルを使う', () async {
    final service = createService();
    final first = await prepare(service, body);
    final firstPath = localPath(first);
    final firstBytes = Uint8List.fromList(bytes);

    bytes = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x30]);
    final second = await prepare(service, first);

    expect(localPath(second), isNot(firstPath));
    expect(
      await (await service.resolveLocalFile(firstPath))!.readAsBytes(),
      orderedEquals(firstBytes),
    );
    expect(loadCount, 2);
  });

  test('同じ内容は同じ保存先を使うが毎回取得する', () async {
    final service = createService();
    final first = await prepare(service, body);
    final second = await prepare(service, first);

    expect(localPath(second), localPath(first));
    expect(loadCount, 2);
  });

  test('同じ本文内の重複URLは1回だけ取得する', () async {
    final service = createService();
    final refreshed = await prepare(
      service,
      '${NovelBodyCodec.prefix}'
      '<img src="$firstUrl"><img src="$firstUrl">',
    );

    final images = html_parser
        .parseFragment(NovelBodyCodec.payloadOf(refreshed))
        .querySelectorAll('img');

    expect(loadCount, 1);
    expect(images, hasLength(2));
    expect(
      images.first.attributes['data-local-src'],
      images.last.attributes['data-local-src'],
    );
  });

  test('途中の画像取得に失敗しても旧画像を残す', () async {
    final service = createService();
    final oldBody = await service.localizeDownloadedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: body,
    );
    final oldFile = (await service.resolveLocalFile(localPath(oldBody)))!;
    final oldBytes = await oldFile.readAsBytes();

    bytes = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x40]);
    failAt = loadCount + 2;

    await expectLater(
      prepare(
        service,
        '${NovelBodyCodec.prefix}'
        '<img src="$firstUrl"><img src="$secondUrl">',
      ),
      throwsStateError,
    );

    expect(await oldFile.exists(), isTrue);
    expect(await oldFile.readAsBytes(), orderedEquals(oldBytes));
  });

  test('画像形式が不正なら準備を失敗として返す', () async {
    bytes = Uint8List.fromList('invalid image'.codeUnits);

    await expectLater(prepare(createService(), body), throwsFormatException);
  });

  test('画像件数・単体容量・合計容量の上限を適用する', () async {
    await expectLater(
      prepare(createService(imageLimit: 0), body),
      throwsStateError,
    );
    await expectLater(
      prepare(createService(imageBytes: 5), body),
      throwsStateError,
    );
    await expectLater(
      prepare(
        createService(episodeBytes: 10),
        '${NovelBodyCodec.prefix}'
        '<img src="$firstUrl"><img src="$secondUrl">',
      ),
      throwsStateError,
    );
  });

  test('許可外URLでは画像を取得しない', () async {
    await expectLater(
      prepare(
        createService(),
        '${NovelBodyCodec.prefix}'
        '<img src="https://example.invalid/image.jpg">',
      ),
      throwsFormatException,
    );
    expect(loadCount, 0);
  });

  test('画像のない通常本文はそのまま返す', () async {
    expect(await prepare(createService(), '画像のない本文'), '画像のない本文');
    expect(loadCount, 0);
  });

  test('空本文は更新用として受け入れない', () async {
    await expectLater(prepare(createService(), '   '), throwsStateError);
  });
}
