import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

import '../utils/novel_body_codec.dart';

typedef IllustrationLoader =
    Future<IllustrationPayload> Function(Uri uri, int maximumBytes);

class IllustrationPayload {
  const IllustrationPayload({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// 永続ダウンロード用の挿絵をApplication Support以下へ保存します。
///
/// 本文には絶対パスを保存せず、read_book_illustrationsからの相対パスを
/// data-local-src属性として保存します。
class IllustrationStorageService {
  IllustrationStorageService({
    Dio? dio,
    Future<Directory> Function()? rootDirectoryProvider,
    this._loader,
    this.maximumImageBytes = 20 * 1024 * 1024,
    this.maximumImagesPerEpisode = 20,
    this.maximumEpisodeBytes = 60 * 1024 * 1024,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 20),
               headers: const {
                 'User-Agent':
                     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                     'AppleWebKit/537.36 '
                     '(KHTML, like Gecko) '
                     'Chrome/125.0.0.0 Safari/537.36',
                 'Accept':
                     'image/avif,image/webp,image/png,image/jpeg,image/gif',
                 'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
               },
             ),
           ),
       _rootDirectoryProvider = rootDirectoryProvider ?? _defaultRootDirectory;

  static const String directoryName = 'read_book_illustrations';

  final Dio _dio;
  final Future<Directory> Function() _rootDirectoryProvider;
  final IllustrationLoader? _loader;

  final int maximumImageBytes;
  final int maximumImagesPerEpisode;
  final int maximumEpisodeBytes;

  static Future<Directory> _defaultRootDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$directoryName',
    );
  }

  /// 本文内の安全な挿絵を保存し、data-local-src属性を付与します。
  ///
  /// 個別画像の取得に失敗した場合はリモートsrcを残し、ほかの画像と本文の
  /// 保存を継続します。
  Future<String> localizeDownloadedBody({
    required String siteKey,
    required String workId,
    required int episodeNo,
    required String body,
  }) async {
    if (!NovelBodyCodec.isRichBody(body)) {
      return body;
    }

    final fragment = html_parser.parseFragment(NovelBodyCodec.payloadOf(body));
    final images = fragment.querySelectorAll('img');

    if (images.isEmpty) {
      return body;
    }

    final safeSiteKey = _safeSegment(siteKey);
    final safeWorkId = _safeSegment(workId);
    final safeEpisodeNo = episodeNo.toString();

    var processedImages = 0;
    var episodeBytes = 0;
    final localizedByUrl = <String, String>{};

    for (final image in images) {
      final uri = NovelBodyCodec.normalizeIllustrationUri(
        image.attributes['src'],
      );

      if (uri == null) {
        image.remove();
        continue;
      }

      image.attributes['src'] = uri.toString();

      final existingRelativePath = image.attributes['data-local-src'];
      if (existingRelativePath != null) {
        final existingFile = await resolveLocalFile(existingRelativePath);
        if (existingFile != null) {
          continue;
        }
        image.attributes.remove('data-local-src');
      }

      final knownPath = localizedByUrl[uri.toString()];
      if (knownPath != null) {
        image.attributes['data-local-src'] = knownPath;
        continue;
      }

      if (processedImages >= maximumImagesPerEpisode) {
        continue;
      }
      processedImages++;

      try {
        final payload =
            await (_loader?.call(uri, maximumImageBytes) ??
                _download(uri, maximumImageBytes));

        if (payload.bytes.isEmpty ||
            payload.bytes.length > maximumImageBytes ||
            episodeBytes + payload.bytes.length > maximumEpisodeBytes) {
          continue;
        }

        final extension = _validatedExtension(
          payload.bytes,
          payload.contentType,
        );
        if (extension == null) {
          continue;
        }

        final digest = sha256.convert(utf8.encode(uri.toString())).toString();
        final relativePath = [
          safeSiteKey,
          safeWorkId,
          safeEpisodeNo,
          '$digest.$extension',
        ].join('/');

        final file = await _fileForRelativePath(relativePath);
        await file.parent.create(recursive: true);

        if (!await file.exists()) {
          final temporaryFile = File('${file.path}.part');

          try {
            await temporaryFile.writeAsBytes(payload.bytes, flush: true);

            if (await file.exists()) {
              await temporaryFile.delete();
            } else {
              await temporaryFile.rename(file.path);
            }
          } catch (_) {
            if (await temporaryFile.exists()) {
              await temporaryFile.delete();
            }
            rethrow;
          }
        }

        image.attributes['data-local-src'] = relativePath;
        localizedByUrl[uri.toString()] = relativePath;
        episodeBytes += payload.bytes.length;
      } catch (_) {
        // 本文とリモートURLは保持し、画像だけオンライン表示へフォールバック
        // できるようにします。
      }
    }

    final payload = _serializeNodes(fragment.nodes);
    return '${NovelBodyCodec.prefix}$payload';
  }

  /// 相対パスに対応する実在ファイルを返します。
  Future<File?> resolveLocalFile(String relativePath) async {
    final file = await _fileForRelativePathOrNull(relativePath);
    if (file == null || !await file.exists()) {
      return null;
    }

    return file;
  }

  Future<void> deleteEpisode({
    required String siteKey,
    required String workId,
    required int episodeNo,
  }) async {
    final root = await _rootDirectoryProvider();
    final directory = Directory(
      [
        root.path,
        _safeSegment(siteKey),
        _safeSegment(workId),
        episodeNo.toString(),
      ].join(Platform.pathSeparator),
    );

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    await _deleteEmptyParents(directory.parent, root);
  }

  Future<void> deleteWork({
    required String siteKey,
    required String workId,
  }) async {
    final root = await _rootDirectoryProvider();
    final directory = Directory(
      [
        root.path,
        _safeSegment(siteKey),
        _safeSegment(workId),
      ].join(Platform.pathSeparator),
    );

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    await _deleteEmptyParents(directory.parent, root);
  }

  static String _serializeNodes(List<dom.Node> nodes) {
    const escape = HtmlEscape(HtmlEscapeMode.element);

    return nodes.map((node) {
      if (node is dom.Element) {
        return node.outerHtml;
      }

      if (node is dom.Text) {
        return escape.convert(node.data);
      }

      return '';
    }).join();
  }

  Future<IllustrationPayload> _download(
    Uri initialUri,
    int maximumBytes,
  ) async {
    var currentUri = initialUri;

    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final response = await _dio.get<ResponseBody>(
        currentUri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );

      final status = response.statusCode ?? 0;
      if (_isRedirect(status)) {
        final location = response.headers.value('location');
        if (location == null || redirectCount == 5) {
          throw StateError('安全に追跡できないリダイレクトです。');
        }

        final redirected = NovelBodyCodec.normalizeIllustrationUri(
          currentUri.resolve(location).toString(),
        );
        if (redirected == null) {
          throw StateError('許可されていない画像URLへのリダイレクトです。');
        }

        currentUri = redirected;
        continue;
      }

      if (status != HttpStatus.ok || response.data == null) {
        throw HttpException('画像取得に失敗しました。HTTP $status');
      }

      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      final declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );

      if (declaredLength != null && declaredLength > maximumBytes) {
        throw StateError('画像サイズが上限を超えています。');
      }

      final builder = BytesBuilder(copy: false);
      var receivedBytes = 0;

      await for (final chunk in response.data!.stream) {
        receivedBytes += chunk.length;
        if (receivedBytes > maximumBytes) {
          throw StateError('画像サイズが上限を超えています。');
        }
        builder.add(chunk);
      }

      return IllustrationPayload(
        bytes: builder.takeBytes(),
        contentType: contentType,
      );
    }

    throw StateError('画像のリダイレクト回数が上限を超えています。');
  }

  static bool _isRedirect(int status) {
    return status == HttpStatus.movedPermanently ||
        status == HttpStatus.found ||
        status == HttpStatus.seeOther ||
        status == HttpStatus.temporaryRedirect ||
        status == HttpStatus.permanentRedirect;
  }

  static String? _validatedExtension(
    Uint8List bytes,
    String contentTypeHeader,
  ) {
    final contentType = contentTypeHeader.split(';').first.trim().toLowerCase();

    final detected = _detectImageType(bytes);
    if (detected == null) {
      return null;
    }

    final expectedContentTypes = switch (detected) {
      'jpg' => const {'image/jpeg', 'image/jpg'},
      'png' => const {'image/png'},
      'gif' => const {'image/gif'},
      'webp' => const {'image/webp'},
      _ => const <String>{},
    };

    if (!expectedContentTypes.contains(contentType)) {
      return null;
    }

    return detected;
  }

  static String? _detectImageType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'jpg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'png';
    }

    if (bytes.length >= 6) {
      final signature = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
      if (signature == 'GIF87a' || signature == 'GIF89a') {
        return 'gif';
      }
    }

    if (bytes.length >= 12) {
      final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
      final webp = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (riff == 'RIFF' && webp == 'WEBP') {
        return 'webp';
      }
    }

    return null;
  }

  Future<File> _fileForRelativePath(String relativePath) async {
    final file = await _fileForRelativePathOrNull(relativePath);
    if (file == null) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }
    return file;
  }

  Future<File?> _fileForRelativePathOrNull(String relativePath) async {
    final normalized = relativePath.replaceAll(r'\', '/');
    final segments = normalized.split('/');

    if (normalized.startsWith('/') ||
        normalized.contains(':') ||
        segments.isEmpty ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              !_isSafeSegment(segment),
        )) {
      return null;
    }

    final root = await _rootDirectoryProvider();
    final path = [root.path, ...segments].join(Platform.pathSeparator);
    return File(path);
  }

  static String _safeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && _isSafeSegment(trimmed)) {
      return trimmed;
    }

    return sha256.convert(utf8.encode(value)).toString();
  }

  static bool _isSafeSegment(String value) {
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
  }

  static Future<void> _deleteEmptyParents(
    Directory directory,
    Directory root,
  ) async {
    var current = directory;

    while (current.path != root.path &&
        await current.exists() &&
        await current.list().isEmpty) {
      final parent = current.parent;
      await current.delete();
      current = parent;
    }
  }
}
