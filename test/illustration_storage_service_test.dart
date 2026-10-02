import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/utils/novel_body_codec.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_illustrations_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('画像を保存して本文へ相対パスを設定する', () async {
    var loadCount = 0;
    final service = IllustrationStorageService(
      rootDirectoryProvider: () async => temporaryDirectory,
      loader: (uri, maximumBytes) async {
        loadCount++;
        return IllustrationPayload(
          bytes: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]),
          contentType: 'image/jpeg',
        );
      },
    );

    const remoteUrl = 'https://img1.mitemin.net/example/image.jpg';
    const body =
        '${NovelBodyCodec.prefix}'
        '本文<img src="$remoteUrl" alt="挿絵">続き';

    final localized = await service.localizeDownloadedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: body,
    );

    final fragment = html_parser.parseFragment(
      NovelBodyCodec.payloadOf(localized),
    );
    final image = fragment.querySelector('img')!;
    final relativePath = image.attributes['data-local-src'];

    expect(loadCount, 1);
    expect(image.attributes['src'], remoteUrl);
    expect(relativePath, isNotNull);
    expect(relativePath, startsWith('narou/n3380le/1/'));
    expect(relativePath, endsWith('.jpg'));

    final localFile = await service.resolveLocalFile(relativePath!);
    expect(localFile, isNotNull);
    expect(await localFile!.exists(), isTrue);
  });

  test('同じURLの画像を1度だけ取得する', () async {
    var loadCount = 0;
    final service = IllustrationStorageService(
      rootDirectoryProvider: () async => temporaryDirectory,
      loader: (uri, maximumBytes) async {
        loadCount++;
        return IllustrationPayload(
          bytes: Uint8List.fromList(const [
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]),
          contentType: 'image/png',
        );
      },
    );

    const remoteUrl = 'https://img1.mitemin.net/example/image.png';
    const body =
        '${NovelBodyCodec.prefix}'
        '<img src="$remoteUrl" alt="挿絵1">'
        '<img src="$remoteUrl" alt="挿絵2">';

    final localized = await service.localizeDownloadedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: body,
    );

    final fragment = html_parser.parseFragment(
      NovelBodyCodec.payloadOf(localized),
    );
    final images = fragment.querySelectorAll('img');

    expect(loadCount, 1);
    expect(images, hasLength(2));
    expect(
      images[0].attributes['data-local-src'],
      images[1].attributes['data-local-src'],
    );
  });

  test('不正な画像データは保存せずリモートURLを残す', () async {
    final service = IllustrationStorageService(
      rootDirectoryProvider: () async => temporaryDirectory,
      loader: (uri, maximumBytes) async {
        return IllustrationPayload(
          bytes: Uint8List.fromList('not an image'.codeUnits),
          contentType: 'image/jpeg',
        );
      },
    );

    const remoteUrl = 'https://img1.mitemin.net/example/image.jpg';
    const body =
        '${NovelBodyCodec.prefix}'
        '<img src="$remoteUrl" alt="挿絵">';

    final localized = await service.localizeDownloadedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: body,
    );

    final fragment = html_parser.parseFragment(
      NovelBodyCodec.payloadOf(localized),
    );
    final image = fragment.querySelector('img')!;

    expect(image.attributes['src'], remoteUrl);
    expect(image.attributes.containsKey('data-local-src'), isFalse);
    expect(await temporaryDirectory.list(recursive: true).isEmpty, isTrue);
  });

  test('パストラバーサルを含む相対パスを拒否する', () async {
    final service = IllustrationStorageService(
      rootDirectoryProvider: () async => temporaryDirectory,
    );

    expect(await service.resolveLocalFile('../secret.jpg'), isNull);
    expect(await service.resolveLocalFile('/absolute/file.jpg'), isNull);
    expect(await service.resolveLocalFile(r'narou\..\secret.jpg'), isNull);
  });

  test('話単位で画像ディレクトリを削除する', () async {
    final service = IllustrationStorageService(
      rootDirectoryProvider: () async => temporaryDirectory,
      loader: (uri, maximumBytes) async {
        return IllustrationPayload(
          bytes: Uint8List.fromList(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
          contentType: 'image/gif',
        );
      },
    );

    const body =
        '${NovelBodyCodec.prefix}'
        '<img src="https://img1.mitemin.net/example/image.gif" alt="挿絵">';

    final localized = await service.localizeDownloadedBody(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
      body: body,
    );

    final fragment = html_parser.parseFragment(
      NovelBodyCodec.payloadOf(localized),
    );
    final relativePath = fragment
        .querySelector('img')!
        .attributes['data-local-src']!;

    expect(await service.resolveLocalFile(relativePath), isNotNull);

    await service.deleteEpisode(
      siteKey: 'narou',
      workId: 'n3380le',
      episodeNo: 1,
    );

    expect(await service.resolveLocalFile(relativePath), isNull);
  });
}
