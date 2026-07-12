import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/episode.dart';
import '../models/site.dart';
import '../utils/search_query_parser.dart';

/// なろう小説APIおよび作品ページのスクレイピングを行うクライアント
class NarouApiClient {
  NarouApiClient()
    : _dio = Dio(
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
            'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
          },
        ),
      );

  final Dio _dio;

  static const String _searchEndpoint = 'https://api.syosetu.com/novelapi/api/';

  // t  = title
  // n  = ncode
  // u  = userid
  // w  = writer
  // s  = story
  // bg = biggenre
  // g  = genre
  // k  = keyword
  // gf = general_firstup
  // gl = general_lastup
  // e  = end
  // l  = length
  // f  = fav_novel_cnt
  // ga = general_all_no
  // nt = novel_type
  static const String _fields = 't-n-u-w-s-bg-g-k-gf-gl-e-l-f-ga-nt';

  // ---------------------------------------------------------------------------
  // 検索
  // ---------------------------------------------------------------------------

  /// キーワード検索
  ///
  /// 次のような除外検索に対応します。
  ///
  /// ```text
  /// 異世界 -ハーレム -ざまぁ
  /// ```
  ///
  /// 引用符を使用した語句にも対応します。
  ///
  /// ```text
  /// 異世界 -"悪役令嬢" -"婚約破棄"
  /// ```
  ///
  /// なろうAPIのnotwordは応答が遅くなる場合があるため、
  /// 除外語はAPIへ送信せず、取得後にアプリ側で除外します。
  Future<List<NarouSearchResult>> search({
    required String word,
    int limit = 20,
    int start = 1,
    String order = 'new',
    bool authorNameOnly = false,
    bool keywordOnly = false,
  }) async {
    final parsedQuery = SearchQueryParser.parse(word);

    // clamp()の結果を明示的にintへ変換します。
    final normalizedLimit = limit.clamp(1, 500).toInt();
    final normalizedStart = start < 1 ? 1 : start;

    // 除外語がある場合は、除外後に表示件数が不足しにくいよう、
    // 通常より多めに取得します。
    final requestLimit = parsedQuery.hasExcludeWords
        ? (normalizedLimit * 3).clamp(normalizedLimit, 100).toInt()
        : normalizedLimit;

    final queryParameters = <String, String>{
      'out': 'json',
      'order': order,
      'lim': requestLimit.toString(),
      'st': normalizedStart.toString(),
      'of': _fields,
    };

    // 含める単語だけをなろうAPIへ送信します。
    if (parsedQuery.includeQuery.isNotEmpty) {
      queryParameters['word'] = parsedQuery.includeQuery;

      if (authorNameOnly) {
        queryParameters['wname'] = '1';
      } else if (keywordOnly) {
        queryParameters['keyword'] = '1';
      } else {
        // 通常検索ではタイトル・あらすじ・キーワードを対象にします。
        queryParameters['title'] = '1';
        queryParameters['ex'] = '1';
        queryParameters['keyword'] = '1';
      }
    }

    // notwordは送信しません。
    // 除外処理は、このメソッドの後半でアプリ側にて行います。

    final response = await _dio.get<dynamic>(
      _searchEndpoint,
      queryParameters: queryParameters,
    );

    final data = _decode(response.data);

    // 先頭要素は検索結果件数などのメタ情報です。
    if (data.length <= 1) {
      return <NarouSearchResult>[];
    }

    final fetchedResults = <NarouSearchResult>[];

    for (final item in data.skip(1)) {
      if (item is Map<String, dynamic>) {
        fetchedResults.add(NarouSearchResult.fromJson(item));
        continue;
      }

      if (item is Map) {
        fetchedResults.add(
          NarouSearchResult.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }

    // 除外語がない場合は、そのまま指定件数を返します。
    if (!parsedQuery.hasExcludeWords) {
      return fetchedResults.take(normalizedLimit).toList();
    }

    // 除外語がある場合は、取得結果をアプリ側で絞り込みます。
    final filteredResults = fetchedResults
        .where((result) {
          final searchableText = _buildSearchableText(
            result: result,
            authorNameOnly: authorNameOnly,
            keywordOnly: keywordOnly,
          );

          final containsExcludedWord = _containsAnyExcludedWord(
            searchableText: searchableText,
            excludeWords: parsedQuery.excludeWords,
          );

          return !containsExcludedWord;
        })
        .take(normalizedLimit)
        .toList();

    return filteredResults;
  }

  /// 検索種別に応じて、除外判定対象の文字列を作成します。
  ///
  /// このメソッドはsearch()の外側、
  /// NarouApiClientクラスの内側に配置します。
  String _buildSearchableText({
    required NarouSearchResult result,
    required bool authorNameOnly,
    required bool keywordOnly,
  }) {
    if (authorNameOnly) {
      return result.author;
    }

    if (keywordOnly) {
      return result.keyword;
    }

    return <String>[result.title, result.summary, result.keyword].join('\n');
  }

  /// 除外語が1つでも含まれているか判定します。
  bool _containsAnyExcludedWord({
    required String searchableText,
    required List<String> excludeWords,
  }) {
    if (excludeWords.isEmpty) {
      return false;
    }

    final normalizedText = _normalizeForSearch(searchableText);

    return excludeWords.any((word) {
      final normalizedWord = _normalizeForSearch(word);

      if (normalizedWord.isEmpty) {
        return false;
      }

      return normalizedText.contains(normalizedWord);
    });
  }

  /// 大文字・小文字、全角スペースなどの違いを吸収します。
  String _normalizeForSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll('　', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // 単一作品取得
  // ---------------------------------------------------------------------------

  /// Nコード指定で単一作品を取得します。
  ///
  /// 更新確認などで使用します。
  Future<NarouSearchResult?> fetchByNcode(String ncode) async {
    final normalizedNcode = ncode.trim().toUpperCase();

    if (normalizedNcode.isEmpty) {
      return null;
    }

    final response = await _dio.get<dynamic>(
      _searchEndpoint,
      queryParameters: <String, String>{
        'out': 'json',
        'ncode': normalizedNcode,
        'of': _fields,
        'lim': '1',
      },
    );

    final data = _decode(response.data);

    if (data.length < 2) {
      return null;
    }

    final item = data[1];

    if (item is Map<String, dynamic>) {
      return NarouSearchResult.fromJson(item);
    }

    if (item is Map) {
      return NarouSearchResult.fromJson(Map<String, dynamic>.from(item));
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // 目次取得
  // ---------------------------------------------------------------------------

  /// なろうの作品ページから目次一覧を取得します。
  ///
  /// 各要素は次の形式です。
  ///
  /// ```dart
  /// {
  ///   'episodeNo': '1',
  ///   'title': '第1話のタイトル',
  ///   'url': 'https://ncode.syosetu.com/nxxxxxx/1/',
  ///   'update': '2026/07/11 12:00',
  ///   'publishedAt': '2026/07/11 12:00',
  /// }
  /// ```
  Future<List<Map<String, String>>> fetchEpisodeList(String ncode) async {
    final normalizedNcode = ncode.trim().toLowerCase();

    if (normalizedNcode.isEmpty) {
      throw ArgumentError('ncodeが空です');
    }

    final workUrl = 'https://ncode.syosetu.com/$normalizedNcode/';

    final response = await _dio.get<String>(
      workUrl,
      options: Options(responseType: ResponseType.plain),
    );

    final html = response.data ?? '';

    if (html.isEmpty) {
      throw StateError('作品ページのHTMLが空です');
    }

    final document = html_parser.parse(html);

    // 現在のなろうで使われている各話の親要素
    final episodeElements = document.querySelectorAll('.p-eplist__sublist');

    if (episodeElements.isNotEmpty) {
      final episodes = <Map<String, String>>[];

      for (var index = 0; index < episodeElements.length; index++) {
        final episodeElement = episodeElements[index];

        final titleElement = episodeElement.querySelector(
          'a.p-eplist__subtitle',
        );

        if (titleElement == null) {
          continue;
        }

        final href = titleElement.attributes['href']?.trim() ?? '';
        final title = _cleanText(titleElement.text);

        if (href.isEmpty || title.isEmpty) {
          continue;
        }

        final episodeNo = _episodeNoFromHref(href: href, fallback: index + 1);

        final fullUrl = Uri.parse(workUrl).resolve(href).toString();

        final updateElement = episodeElement.querySelector('.p-eplist__update');

        final publishedAt = _cleanPublishedDate(updateElement?.text ?? '');

        episodes.add(<String, String>{
          'episodeNo': episodeNo.toString(),
          'title': title,
          'url': fullUrl,
          'update': publishedAt,
          'publishedAt': publishedAt,
        });
      }

      if (episodes.isNotEmpty) {
        return episodes;
      }
    }

    // 古いHTML構造などへの予備対応
    final titleAnchors = document.querySelectorAll('a.p-eplist__subtitle');

    if (titleAnchors.isNotEmpty) {
      final episodes = <Map<String, String>>[];

      for (var index = 0; index < titleAnchors.length; index++) {
        final titleElement = titleAnchors[index];

        final href = titleElement.attributes['href']?.trim() ?? '';
        final title = _cleanText(titleElement.text);

        if (href.isEmpty || title.isEmpty) {
          continue;
        }

        final episodeNo = _episodeNoFromHref(href: href, fallback: index + 1);

        final fullUrl = Uri.parse(workUrl).resolve(href).toString();

        final updateElement = titleElement.parent?.querySelector(
          '.p-eplist__update',
        );

        final publishedAt = _cleanPublishedDate(updateElement?.text ?? '');

        episodes.add(<String, String>{
          'episodeNo': episodeNo.toString(),
          'title': title,
          'url': fullUrl,
          'update': publishedAt,
          'publishedAt': publishedAt,
        });
      }

      if (episodes.isNotEmpty) {
        return episodes;
      }
    }

    // 目次がない作品は短編として扱います。
    final wwwcElement = document.querySelector('meta[name="WWWC"]');

    final publishedAt = _cleanPublishedDate(
      wwwcElement?.attributes['content'] ?? '',
    );

    final workTitle = _cleanText(
      document.querySelector('.p-novel__title')?.text ??
          document.querySelector('h1')?.text ??
          '本文',
    );

    return <Map<String, String>>[
      <String, String>{
        'episodeNo': '1',
        'title': workTitle.isEmpty ? '本文' : workTitle,
        'url': workUrl,
        'update': publishedAt,
        'publishedAt': publishedAt,
      },
    ];
  }

  // ---------------------------------------------------------------------------
  // 本文取得
  // ---------------------------------------------------------------------------

  /// 指定話の本文を取得します。
  Future<Episode> fetchEpisodeBody({
    required String workId,
    required int episodeNo,
    required String episodeTitle,
  }) async {
    final normalizedWorkId = workId.trim().toLowerCase();

    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workIdが空です');
    }

    final episodeUrl =
        'https://ncode.syosetu.com/$normalizedWorkId/$episodeNo/';

    var response = await _dio.get<String>(
      episodeUrl,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (status) {
          return status != null && status >= 200 && status < 500;
        },
      ),
    );

    // 短編は「/1/」が存在せず、作品ページ自体が本文になります。
    if (response.statusCode == 404) {
      response = await _dio.get<String>(
        'https://ncode.syosetu.com/$normalizedWorkId/',
        options: Options(responseType: ResponseType.plain),
      );
    }

    final html = response.data ?? '';

    if (html.isEmpty) {
      throw StateError('本文ページのHTMLが空です');
    }

    final document = html_parser.parse(html);

    final bodyElement =
        document.querySelector('.p-novel__body') ??
        document.querySelector('#novel_honbun');

    if (bodyElement == null) {
      throw StateError('本文要素を取得できませんでした');
    }

    final body = bodyElement.text.trim();

    if (body.isEmpty) {
      throw StateError('本文が空です');
    }

    return Episode(
      workId: normalizedWorkId,
      episodeNo: episodeNo,
      episodeTitle: episodeTitle,
      body: body,
      fetchedAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // 補助メソッド
  // ---------------------------------------------------------------------------

  /// URLから話番号を取得します。
  int _episodeNoFromHref({required String href, required int fallback}) {
    final normalizedHref = href.split('?').first.split('#').first;

    final match = RegExp(r'/(\d+)/?$').firstMatch(normalizedHref);

    if (match == null) {
      return fallback;
    }

    return int.tryParse(match.group(1) ?? '') ?? fallback;
  }

  /// タイトルなどの余分な空白や改行を除去します。
  String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// なろうの掲載日時を整形します。
  String _cleanPublishedDate(String value) {
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s*（改）\s*$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// なろうAPIのレスポンスをListへ変換します。
  List<dynamic> _decode(dynamic raw) {
    if (raw is List) {
      return raw;
    }

    if (raw is String) {
      final trimmed = raw.trim();

      if (trimmed.isEmpty) {
        return <dynamic>[];
      }

      try {
        final decoded = jsonDecode(trimmed);

        if (decoded is List) {
          return decoded;
        }
      } on FormatException {
        return <dynamic>[];
      }
    }

    return <dynamic>[];
  }
}

/// なろう・カクヨム共通で使用する検索結果
class NarouSearchResult {
  final String title;
  final String ncode;
  final String authorId;
  final String author;
  final String summary;
  final int biggenre;
  final int genre;
  final String keyword;
  final String generalFirstup;
  final String generalLastup;
  final int end;
  final int length;
  final int favNovelCnt;
  final int generalAllNo;
  final int novelType;
  final Site site;

  const NarouSearchResult({
    required this.title,
    required this.ncode,
    required this.authorId,
    required this.author,
    required this.summary,
    required this.biggenre,
    required this.genre,
    required this.keyword,
    required this.generalFirstup,
    required this.generalLastup,
    required this.end,
    required this.length,
    required this.favNovelCnt,
    required this.generalAllNo,
    required this.novelType,
    this.site = Site.narou,
  });

  String get workId => ncode;

  String get siteName => site.displayName;

  factory NarouSearchResult.fromJson(Map<String, dynamic> json) {
    return NarouSearchResult(
      title: json['title']?.toString() ?? '',
      ncode: json['ncode']?.toString() ?? '',
      authorId: json['userid']?.toString() ?? '',
      author: json['writer']?.toString() ?? '',
      summary: json['story']?.toString() ?? '',
      biggenre: _toInt(json['biggenre']),
      genre: _toInt(json['genre']),
      keyword: json['keyword']?.toString() ?? '',
      generalFirstup: json['general_firstup']?.toString() ?? '',
      generalLastup: json['general_lastup']?.toString() ?? '',
      end: _toInt(json['end']),
      length: _toInt(json['length']),
      favNovelCnt: _toInt(json['fav_novel_cnt']),
      generalAllNo: _toInt(json['general_all_no']),
      novelType: _toInt(json['novel_type'], fallback: 1),
      site: Site.narou,
    );
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  // novel_type:
  // 1 = 連載
  // 2 = 短編
  bool get isShortStory => novelType == 2;

  // end:
  // 0 = 短編または完結済み
  // 1 = 連載中
  bool get isCompleted {
    return !isShortStory && end == 0;
  }

  bool get isOngoing {
    return !isShortStory && end == 1;
  }

  /// 「短編」「連載 全n話」「連載完結 全n話」の表示
  String get statusLabel {
    if (isShortStory) {
      return '短編';
    }

    if (isOngoing) {
      return '連載 全$generalAllNo話';
    }

    return '連載完結 全$generalAllNo話';
  }

  String get genreName {
    switch (biggenre) {
      case 1:
        return '恋愛';

      case 2:
        return 'ファンタジー';

      case 3:
        return '文芸';

      case 4:
        return 'SF';

      case 98:
        return 'ノンジャンル';

      case 99:
      default:
        return 'その他';
    }
  }
}
