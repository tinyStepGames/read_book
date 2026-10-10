import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/utils/novel_body_codec.dart';
import 'package:read_book/widgets/decorated_novel_text.dart';

void main() {
  late Directory temporaryDirectory;
  late File imageFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_decorated_text_test_',
    );

    imageFile = File(
      [
        temporaryDirectory.path,
        'narou',
        'n3380le',
        '1',
        'test.gif',
      ].join(Platform.pathSeparator),
    );

    await imageFile.parent.create(recursive: true);
    await imageFile.writeAsBytes(
      base64Decode('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=='),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('data-local-srcのローカル画像を表示する', (tester) async {
    const relativePath = 'narou/n3380le/1/test.gif';
    final service = _ImmediateIllustrationStorageService(imageFile);

    const body =
        '${NovelBodyCodec.prefix}'
        '画像の前'
        '<img '
        'src="https://img1.mitemin.net/example/test.png" '
        'data-local-src="$relativePath" '
        'alt="テスト挿絵">'
        '画像の後';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedNovelText(
            body: body,
            fontSize: 16,
            illustrationStorageService: service,
          ),
        ),
      ),
    );

    // FutureBuilderによるローカルファイル確認を完了させます。
    // CircularProgressIndicatorは継続的にアニメーションするため、
    // 非同期処理は有限回のpumpで反映します。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('画像の前', findRichText: true), findsOneWidget);
    expect(find.textContaining('画像の後', findRichText: true), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
    expect(image.semanticLabel, 'テスト挿絵');

    // Windowsで一時画像を削除できるよう、Imageをツリーとキャッシュから
    // 明示的に外します。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('従来のプレーン本文をそのまま表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DecoratedNovelText(body: '従来形式の本文', fontSize: 16)),
      ),
    );

    expect(find.text('従来形式の本文'), findsOneWidget);
  });
}

class _ImmediateIllustrationStorageService extends IllustrationStorageService {
  _ImmediateIllustrationStorageService(this.file);

  final File file;

  @override
  Future<File?> resolveLocalFile(String relativePath) {
    return SynchronousFuture<File?>(file);
  }
}
