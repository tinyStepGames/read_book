import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/episode.dart';
import '../models/site.dart';
import '../utils/search_query_parser.dart';
import 'narou_api_client.dart';

/// カクヨム作品ページから取得した詳細情報
class KakuyomuWorkDetails {
  final String summary;

  const KakuyomuWorkDetails({required this.summary});
}

/// 作品ページHTMLの短時間キャッシュ
class _CachedWorkPage {
  final String html;
  final DateTime fetchedAt;

  const _CachedWorkPage({required this.html, required this.fetchedAt});
}

class KakuyomuScraper {
  KakuyomuScraper()
    : _dio = Dio(
        BaseOptions(
          responseType: ResponseType.plain,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 20),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                'Version/17.0 Mobile/15E148 Safari/604.1',
            'Accept':
                'text/html,application/xhtml+xml,'
                'application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
          },
        ),
      );

  final Dio _dio;

  /// workId → 話数 → episodeId
  final Map<String, Map<int, String>> _episodeIdCache = {};

  final Map<String, _CachedWorkPage> _workPageCache = {};

  static const Duration _workPageCacheDuration = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // 作品検索
  // ---------------------------------------------------------------------------

  /// カクヨム作品を検索します。
  ///
  /// ```text
  /// 異世界 -ハーレム -ざまぁ
  /// ```
  ///
  /// ```text
  /// 異世界 -"悪役令嬢"
  /// ```
  Future<List<NarouSearchResult>> search({
    required String word,
    int page = 1,
    bool authorNameOnly = false,
    bool keywordOnly = false,
  }) async {
    final parsedQuery = SearchQueryParser.parse(word);

    // カクヨムへ送信する検索文字列です。
    // 除外語には「-」を付けたまま送信します。
    final kakuyomuQuery = parsedQuery.kakuyomuQuery;

    final isRecentWorks = word.trim().isEmpty;
    final normalizedPage = page < 1 ? 1 : page;

    final response = await _dio.get<String>(
      isRecentWorks
          ? 'https://kakuyomu.jp/recent_works'
          : 'https://kakuyomu.jp/search',
      queryParameters: <String, dynamic>{
        if (!isRecentWorks) 'q': kakuyomuQuery,

        // キーワード検索結果を作品の更新順にします。
        if (!isRecentWorks) 'order': 'last_episode_published_at',

        if (normalizedPage > 1) 'page': normalizedPage,
      },
      options: Options(responseType: ResponseType.plain),
    );

    final html = response.data ?? '';

    if (html.isEmpty) {
      throw StateError(isRecentWorks ? 'カクヨムの新着小説ページが空でした' : 'カクヨムの検索結果が空でした');
    }

    final document = html_parser.parse(html);

    final titleAnchors = <Element>[
      ...document.querySelectorAll(
        '.widget-workCard-titleLabel[href^="/works/"]',
      ),
      ...document.querySelectorAll('h3 a[href^="/works/"]'),
      ...document.querySelectorAll('h4 a[href^="/works/"]'),
    ];

    final results = <NarouSearchResult>[];
    final usedWorkIds = <String>{};

    for (final titleAnchor in titleAnchors) {
      final href = titleAnchor.attributes['href'] ?? '';

      final match = RegExp(r'^/works/([^/?#]+)$').firstMatch(href);

      if (match == null) {
        continue;
      }

      final workId = match.group(1) ?? '';

      if (workId.isEmpty || !usedWorkIds.add(workId)) {
        continue;
      }

      final title = _cleanText(
        titleAnchor.attributes['title'] ?? titleAnchor.text,
      );

      if (title.isEmpty) {
        continue;
      }

      final container = _findWorkContainer(titleAnchor, workId);

      final authorAnchor = container?.querySelector(
        '.widget-workCard-authorLabel, '
        'a[href^="/users/"]',
      );

      final author = _cleanText(authorAnchor?.text ?? '');

      final authorHref = authorAnchor?.attributes['href'] ?? '';

      final authorId = authorHref
          .replaceFirst('/users/', '')
          .split('/')
          .first
          .trim();

      final summary = _findSummary(container, workId, title);

      final genre = _cleanText(
        container
                ?.querySelector(
                  '.widget-workCard-genre a, '
                  'a[href^="/genres/"]',
                )
                ?.text ??
            '',
      );

      final tags =
          container
              ?.querySelectorAll(
                '.widget-workCard-tags a, '
                'a[href^="/tags/"]',
              )
              .map((element) => _cleanText(element.text))
              .where((tag) => tag.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[];

      if (authorNameOnly &&
          !_matchesScopedSearch(value: author, query: parsedQuery)) {
        continue;
      }

      if (keywordOnly &&
          !_matchesScopedSearch(value: tags.join(' '), query: parsedQuery)) {
        continue;
      }

      // 通常検索ではカクヨム側の「-除外語」に加えて、
      // アプリ側でも除外判定を行います。
      if (!authorNameOnly &&
          !keywordOnly &&
          _containsExcludedWord(
            query: parsedQuery,
            values: <String>[title, summary, ...tags],
          )) {
        continue;
      }

      final containerText = container?.text ?? '';

      final episodeCount = _parseNumber(
        RegExp(r'(\d[\d,]*)\s*話').firstMatch(containerText)?.group(1),
      );

      final characterCount = _parseNumber(
        RegExp(r'(\d[\d,]*)\s*文字').firstMatch(containerText)?.group(1),
      );

      final starCount = _parseNumber(
        RegExp(r'★\s*(\d[\d,]*)').firstMatch(containerText)?.group(1),
      );

      final isCompleted =
          containerText.contains('完結') || containerText.contains('完結済');

      final updatedElement =
          container?.querySelector('time') ??
          container?.querySelector('.widget-workCard-dateUpdated');

      final displayedUpdatedAt = updatedElement?.text.trim() ?? '';

      final attributeUpdatedAt =
          updatedElement?.attributes['datetime'] ??
          updatedElement?.attributes['dateTime'] ??
          '';

      final rawUpdatedAt = displayedUpdatedAt.isNotEmpty
          ? displayedUpdatedAt
          : attributeUpdatedAt;

      final cleanedUpdatedAt = _cleanPublishedDate(rawUpdatedAt);
      final updatedAt = _toIsoLikeDate(cleanedUpdatedAt);
      final bigGenreNumber = _bigGenreNumber(genre);

      results.add(
        NarouSearchResult(
          title: title,
          ncode: workId,
          authorId: authorId,
          author: author,
          summary: summary,
          biggenre: bigGenreNumber,
          genre: bigGenreNumber,
          keyword: tags.join(' '),
          generalFirstup: '',
          generalLastup: updatedAt,
          end: isCompleted ? 0 : 1,
          length: characterCount,
          favNovelCnt: starCount,
          generalAllNo: episodeCount,
          novelType: 1,
          site: Site.kakuyomu,
        ),
      );
    }

    return results;
  }

  bool _matchesScopedSearch({
    required String value,
    required ParsedSearchQuery query,
  }) {
    final normalizedValue = value.toLowerCase();

    final containsAllIncludedWords = query.includeWords.every(
      (word) => normalizedValue.contains(word.toLowerCase()),
    );

    if (!containsAllIncludedWords) {
      return false;
    }

    final containsExcludedWord = query.excludeWords.any(
      (word) => normalizedValue.contains(word.toLowerCase()),
    );

    return !containsExcludedWord;
  }

  bool _containsExcludedWord({
    required ParsedSearchQuery query,
    required Iterable<String> values,
  }) {
    if (!query.hasExcludeWords) {
      return false;
    }

    final searchableText = values.join('\n').toLowerCase();

    return query.excludeWords.any(
      (word) => searchableText.contains(word.toLowerCase()),
    );
  }

  // ---------------------------------------------------------------------------
  // 完全な作品詳細
  // ---------------------------------------------------------------------------

  /// カクヨムの完全なあらすじを取得します。
  ///
  /// 通常の作品ページHTMLでは「…続きを読む」の位置で省略されるため、
  /// アプリ用JSON APIのintroductionを優先して使用します。
  Future<KakuyomuWorkDetails> fetchWorkDetails(String workId) async {
    final normalizedWorkId = _normalizeWorkId(workId);

    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workIdが空です');
    }

    final apiUrl = 'https://kakuyomu.jp/api/app/works/$normalizedWorkId';

    try {
      final response = await _dio.get<dynamic>(
        apiUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: const {'Accept': 'application/json'},
        ),
      );

      final data = _toJsonMap(response.data);

      final introduction = _cleanSummary(
        data['introduction']?.toString() ?? '',
      );

      if (introduction.isNotEmpty) {
        return KakuyomuWorkDetails(summary: introduction);
      }
    } catch (_) {
      // API取得に失敗した場合はHTML解析へ進みます。
    }

    return _fetchWorkDetailsFromHtml(normalizedWorkId);
  }

  Future<KakuyomuWorkDetails> _fetchWorkDetailsFromHtml(String workId) async {
    try {
      final document = await _fetchWorkDocument(workId);

      final summaryElement =
          document.querySelector(
            '[class*="CollapseTextWithKakuyomuLinks_collapseText"]',
          ) ??
          document.querySelector(
            '[class*="WorkIntroductionBox"] '
            '[class*="collapseText"]',
          ) ??
          document.querySelector(
            '[class*="WorkIntroductionBox"] '
            '[class*="CollapseText"]',
          ) ??
          document.querySelector('.widget-workDescription') ??
          document.querySelector('[class*="workDescription"]');

      var summary = '';

      if (summaryElement != null) {
        summary = _textWithLineBreaks(summaryElement);
      }

      if (summary.trim().isEmpty) {
        summary =
            document
                .querySelector('meta[name="description"]')
                ?.attributes['content']
                ?.trim() ??
            '';
      }

      return KakuyomuWorkDetails(summary: _cleanSummary(summary));
    } catch (_) {
      return const KakuyomuWorkDetails(summary: '');
    }
  }

  Map<String, dynamic> _toJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is Map<String, dynamic>) {
          return decoded;
        }

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        return const <String, dynamic>{};
      }
    }

    return const <String, dynamic>{};
  }

  String _normalizeWorkId(String value) {
    final trimmed = value.trim();

    final match = RegExp(r'/works/(\d+)').firstMatch(trimmed);

    if (match != null) {
      return match.group(1) ?? '';
    }

    return RegExp(r'^\d+$').hasMatch(trimmed) ? trimmed : '';
  }

  // ---------------------------------------------------------------------------
  // 目次取得
  // ---------------------------------------------------------------------------

  /// カクヨムの目次を取得します.
  ///
  /// アプリ用JSON APIを優先し、取得できなかった場合だけ
  /// 作品ページHTMLの解析へ切り替えます。
  Future<List<Map<String, String>>> fetchEpisodeList(String workId) async {
    final normalizedWorkId = _normalizeWorkId(workId);

    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workIdが空です');
    }

    try {
      final episodes = await _fetchEpisodeListFromApi(normalizedWorkId);

      debugPrint(
        'Kakuyomu API目次取得成功: '
        'workId=$normalizedWorkId, episodes=${episodes.length}',
      );

      return episodes;
    } catch (error, stackTrace) {
      debugPrint(
        'Kakuyomu API目次取得失敗: '
        'workId=$normalizedWorkId, error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);

      final episodes = await _fetchEpisodeListFromHtml(normalizedWorkId);

      debugPrint(
        'Kakuyomu HTML目次取得: '
        'workId=$normalizedWorkId, episodes=${episodes.length}',
      );

      return episodes;
    }
  }

  /// カクヨムのアプリ用JSON APIから全エピソードを取得します。
  Future<List<Map<String, String>>> _fetchEpisodeListFromApi(
    String workId,
  ) async {
    final apiUrl = 'https://kakuyomu.jp/api/app/works/$workId';

    final response = await _dio.get<dynamic>(
      apiUrl,
      options: Options(
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );

    final data = _toJsonMap(response.data);
    final rawEpisodes = data['episodes'];

    debugPrint(
      'Kakuyomu API応答: '
      'workId=$workId, '
      'dataType=${response.data.runtimeType}, '
      'episodesType=${rawEpisodes.runtimeType}, '
      'episodesCount=${rawEpisodes is List ? rawEpisodes.length : 0}',
    );

    if (rawEpisodes is! List) {
      throw StateError(
        'カクヨムAPIのepisodesがListではありません。'
        '実際の型: ${rawEpisodes.runtimeType}',
      );
    }

    if (rawEpisodes.isEmpty) {
      throw StateError('カクヨムAPIの目次が空でした');
    }

    final episodes = <Map<String, String>>[];
    final usedEpisodeIds = <String>{};

    for (final rawEpisode in rawEpisodes) {
      final episodeData = _toEpisodeJsonMap(rawEpisode);

      if (episodeData.isEmpty) {
        continue;
      }

      final episodeId = _readEpisodeId(episodeData);

      if (episodeId.isEmpty) {
        debugPrint(
          'KakuyomuエピソードIDなし: '
          '${episodeData.keys.join(', ')}',
        );
        continue;
      }

      if (!usedEpisodeIds.add(episodeId)) {
        continue;
      }

      var title = _cleanEpisodeTitle(episodeData['title']?.toString() ?? '');

      final publicNumber = _parsePositiveInt(episodeData['public_number']);

      final apiNumber = _parsePositiveInt(episodeData['number']);

      final episodeNo = publicNumber ?? apiNumber ?? episodes.length + 1;

      if (title.isEmpty) {
        title = '第$episodeNo話';
      }

      final rawPermalink = episodeData['permalink']?.toString().trim() ?? '';

      final episodeUrl = rawPermalink.isNotEmpty
          ? rawPermalink
          : 'https://kakuyomu.jp/works/'
                '$workId/episodes/$episodeId';

      final publishedAt = _formatApiTimestamp(episodeData['published_at']);

      episodes.add(<String, String>{
        'episodeNo': episodeNo.toString(),
        'episodeId': episodeId,
        'title': title,
        'url': episodeUrl,
        'update': publishedAt,
        'publishedAt': publishedAt,
      });
    }

    if (episodes.isEmpty) {
      throw StateError(
        'カクヨムAPIから各話を取得できませんでした。'
        'API上の話数: ${rawEpisodes.length}',
      );
    }

    // public_numberまたはnumberの順番に並べます。
    episodes.sort((left, right) {
      final leftNo = int.tryParse(left['episodeNo'] ?? '') ?? 0;
      final rightNo = int.tryParse(right['episodeNo'] ?? '') ?? 0;

      return leftNo.compareTo(rightNo);
    });

    // 欠番や重複番号があっても、アプリ内では1話目から連番にします。
    final normalizedEpisodes = <Map<String, String>>[];
    final normalizedEpisodeIdMap = <int, String>{};

    for (var index = 0; index < episodes.length; index++) {
      final episodeNo = index + 1;
      final source = episodes[index];
      final episodeId = source['episodeId'] ?? '';

      if (episodeId.isEmpty) {
        continue;
      }

      final normalizedEntry = <String, String>{
        ...source,
        'episodeNo': episodeNo.toString(),
      };

      normalizedEpisodes.add(normalizedEntry);
      normalizedEpisodeIdMap[episodeNo] = episodeId;
    }

    if (normalizedEpisodes.isEmpty) {
      throw StateError('カクヨムAPIの目次を正規化できませんでした');
    }

    _episodeIdCache[workId] = normalizedEpisodeIdMap;

    debugPrint(
      'Kakuyomu API解析完了: '
      'workId=$workId, '
      'raw=${rawEpisodes.length}, '
      'parsed=${normalizedEpisodes.length}, '
      'first=${normalizedEpisodes.first['title']}, '
      'last=${normalizedEpisodes.last['title']}',
    );

    return normalizedEpisodes;
  }

  /// APIの各エピソードをMapへ変換します。
  Map<String, dynamic> _toEpisodeJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const <String, dynamic>{};
  }

  /// APIのエピソードIDを取得します。
  ///
  /// 通常はidを使用し、取得できない場合はpermalinkから取り出します。
  String _readEpisodeId(Map<String, dynamic> episodeData) {
    final rawId = episodeData['id']?.toString().trim() ?? '';

    if (rawId.isNotEmpty && rawId != 'null') {
      return rawId;
    }

    final permalink = episodeData['permalink']?.toString().trim() ?? '';

    final match = RegExp(r'/episodes/([^/?#]+)').firstMatch(permalink);

    return match?.group(1)?.trim() ?? '';
  }

  /// 正の整数を取得します。
  int? _parsePositiveInt(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');

    if (parsed == null || parsed <= 0) {
      return null;
    }

    return parsed;
  }

  /// カクヨムAPIのUnix秒を画面用の日時へ変換します。
  String _formatApiTimestamp(dynamic value) {
    final seconds = value is int
        ? value
        : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');

    if (seconds == null || seconds <= 0) {
      return '';
    }

    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ).toLocal();

      final year = dateTime.year.toString().padLeft(4, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');

      return '$year/$month/$day $hour:$minute';
    } catch (_) {
      return '';
    }
  }

  /// APIが利用できない場合のHTML目次取得です。
  Future<List<Map<String, String>>> _fetchEpisodeListFromHtml(
    String workId,
  ) async {
    final document = await _fetchWorkDocument(workId);

    final anchors = document.querySelectorAll(
      'a[href^="/works/$workId/episodes/"]',
    );

    if (anchors.isEmpty) {
      throw StateError('カクヨムの目次を取得できませんでした');
    }

    final episodeTitles = <String, String>{};
    final episodePublishedDates = <String, String>{};
    final episodeOrder = <String>[];

    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';

      final match = RegExp(
        '^/works/'
        '${RegExp.escape(workId)}'
        '/episodes/([^/?#]+)',
      ).firstMatch(href);

      if (match == null) {
        continue;
      }

      final episodeId = match.group(1) ?? '';

      if (episodeId.isEmpty) {
        continue;
      }

      final rawTitle = _cleanText(anchor.text);
      final cleanedTitle = _cleanEpisodeTitle(rawTitle);

      if (cleanedTitle.isEmpty || _isGenericEpisodeTitle(cleanedTitle)) {
        continue;
      }

      if (!episodeOrder.contains(episodeId)) {
        episodeOrder.add(episodeId);
      }

      final oldTitle = episodeTitles[episodeId] ?? '';

      if (oldTitle.isEmpty || cleanedTitle.length > oldTitle.length) {
        episodeTitles[episodeId] = cleanedTitle;
      }

      final episodeContainer = _findEpisodeContainer(anchor);

      final timeElement =
          anchor.querySelector('time') ??
          episodeContainer?.querySelector('time');

      var publishedDate = '';

      if (timeElement != null) {
        final displayedDate = _cleanPublishedDate(timeElement.text);

        final attributeDate = _cleanPublishedDate(
          timeElement.attributes['datetime'] ??
              timeElement.attributes['dateTime'] ??
              '',
        );

        publishedDate = displayedDate.isNotEmpty
            ? displayedDate
            : attributeDate;
      }

      if (publishedDate.isEmpty) {
        publishedDate = _extractPublishedDate(rawTitle);
      }

      if (publishedDate.isNotEmpty) {
        episodePublishedDates[episodeId] = publishedDate;
      }
    }

    if (episodeOrder.isEmpty) {
      throw StateError('カクヨムの各話タイトルを取得できませんでした');
    }

    final episodes = <Map<String, String>>[];
    final episodeIdMap = <int, String>{};

    for (final episodeId in episodeOrder) {
      final title = _cleanEpisodeTitle(episodeTitles[episodeId] ?? '');

      if (title.isEmpty) {
        continue;
      }

      final episodeNo = episodes.length + 1;
      final publishedDate = episodePublishedDates[episodeId] ?? '';

      final episodeUrl =
          'https://kakuyomu.jp/works/'
          '$workId/episodes/$episodeId';

      episodes.add(<String, String>{
        'episodeNo': episodeNo.toString(),
        'episodeId': episodeId,
        'title': title,
        'url': episodeUrl,
        'update': publishedDate,
        'publishedAt': publishedDate,
      });

      episodeIdMap[episodeNo] = episodeId;
    }

    if (episodes.isEmpty) {
      throw StateError('カクヨムの各話タイトルを取得できませんでした');
    }

    _episodeIdCache[workId] = episodeIdMap;

    return episodes;
  }

  Future<String> resolveEpisodeId({
    required String workId,
    required int episodeNo,
  }) async {
    final normalizedWorkId = _normalizeWorkId(workId);

    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workIdが空です');
    }

    final cached = _episodeIdCache[normalizedWorkId]?[episodeNo];

    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    await fetchEpisodeList(normalizedWorkId);

    final resolved = _episodeIdCache[normalizedWorkId]?[episodeNo];

    if (resolved == null || resolved.isEmpty) {
      throw StateError('カクヨムの第$episodeNo話のIDを取得できませんでした');
    }

    return resolved;
  }

  // ---------------------------------------------------------------------------
  // 本文取得
  // ---------------------------------------------------------------------------

  Future<Episode> fetchEpisodeBody({
    required String workId,
    required String episodeId,
    required int episodeNo,
    required String episodeTitle,
  }) async {
    final normalizedWorkId = _normalizeWorkId(workId);
    final normalizedEpisodeId = episodeId.trim();

    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workIdが空です');
    }

    if (normalizedEpisodeId.isEmpty) {
      throw ArgumentError('episodeIdが空です');
    }

    final url =
        'https://kakuyomu.jp/works/'
        '$normalizedWorkId/episodes/$normalizedEpisodeId';

    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );

    final html = response.data ?? '';

    if (html.isEmpty) {
      throw StateError('カクヨムの本文ページが空でした');
    }

    final document = html_parser.parse(html);

    final bodyElement =
        document.querySelector('.widget-episodeBody') ??
        document.querySelector('.js-episode-body') ??
        document.querySelector('[class*="episodeBody"]');

    if (bodyElement == null) {
      throw StateError('カクヨムの本文要素を取得できませんでした');
    }

    final paragraphs = bodyElement.querySelectorAll('p');

    final body = paragraphs.isNotEmpty
        ? paragraphs
              .map(_textWithLineBreaks)
              .where((text) => text.isNotEmpty)
              .join('\n\n')
              .trim()
        : _textWithLineBreaks(bodyElement);

    if (body.isEmpty) {
      throw StateError('カクヨムの本文が空でした');
    }

    return Episode(
      workId: normalizedWorkId,
      episodeNo: episodeNo,
      episodeTitle: _cleanEpisodeTitle(episodeTitle),
      body: body,
      fetchedAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // HTTP・キャッシュ
  // ---------------------------------------------------------------------------

  Future<Document> _fetchWorkDocument(String workId) async {
    final now = DateTime.now();
    final cached = _workPageCache[workId];

    if (cached != null &&
        now.difference(cached.fetchedAt) < _workPageCacheDuration) {
      return html_parser.parse(cached.html);
    }

    final url = 'https://kakuyomu.jp/works/$workId';

    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );

    final html = response.data ?? '';

    if (html.isEmpty) {
      throw StateError('カクヨムの作品ページが空でした');
    }

    _workPageCache[workId] = _CachedWorkPage(html: html, fetchedAt: now);

    _removeExpiredWorkPageCache(now);

    return html_parser.parse(html);
  }

  void _removeExpiredWorkPageCache(DateTime now) {
    final expiredKeys = _workPageCache.entries
        .where(
          (entry) =>
              now.difference(entry.value.fetchedAt) >= _workPageCacheDuration,
        )
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _workPageCache.remove(key);
    }
  }

  // ---------------------------------------------------------------------------
  // HTML要素探索
  // ---------------------------------------------------------------------------

  Element? _findWorkContainer(Element titleAnchor, String workId) {
    Element? current = titleAnchor.parent;

    for (var depth = 0; depth < 15; depth++) {
      if (current == null) {
        return null;
      }

      if (current.classes.contains('widget-work')) {
        return current;
      }

      final hasWorkLink =
          current.querySelector('a[href="/works/$workId"]') != null;

      final hasAuthor = current.querySelector('a[href^="/users/"]') != null;

      final hasMetaInformation =
          current.querySelector('time') != null ||
          current.querySelector('.widget-workCard-dateUpdated') != null ||
          current.querySelector('.widget-workCard-meta') != null ||
          RegExp(r'\d[\d,]*\s*話').hasMatch(current.text);

      if (hasWorkLink && hasAuthor && hasMetaInformation) {
        return current;
      }

      current = current.parent;
    }

    return titleAnchor.parent;
  }

  Element? _findEpisodeContainer(Element anchor) {
    Element? current = anchor;

    for (var depth = 0; depth < 10; depth++) {
      if (current == null) {
        return null;
      }

      if (current.querySelector('time') != null) {
        return current;
      }

      current = current.parent;
    }

    return anchor.parent;
  }

  String _findSummary(Element? container, String workId, String title) {
    if (container == null) {
      return '';
    }

    final recentSummary = _cleanText(
      container.querySelector('.widget-workCard-introduction')?.text ?? '',
    );

    if (recentSummary.isNotEmpty) {
      return recentSummary;
    }

    final candidates = container.querySelectorAll('a[href="/works/$workId"]');

    for (final candidate in candidates) {
      final text = _cleanText(candidate.text);

      if (text.isEmpty || text == title) {
        continue;
      }

      if (text.length >= 20) {
        return text;
      }
    }

    return '';
  }

  // ---------------------------------------------------------------------------
  // 文字列整形
  // ---------------------------------------------------------------------------

  String _textWithLineBreaks(Element element) {
    var html = element.innerHtml;

    html = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');

    final text = html_parser.parseFragment(html).text ?? '';

    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  String _cleanSummary(String value) {
    return value
        .replaceAll('…続きを読む', '')
        .replaceAll('続きを読む', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _cleanEpisodeTitle(String value) {
    var result = _cleanText(value);

    result = result.replaceFirst(
      RegExp(
        r'\s*'
        r'\d{4}年\s*'
        r'\d{1,2}月\s*'
        r'\d{1,2}日'
        r'(?:\s+\d{1,2}:\d{2})?'
        r'\s*(?:公開|更新)\s*$',
      ),
      '',
    );

    result = result.replaceFirst(
      RegExp(
        r'\s*'
        r'\d{4}[/-]\d{1,2}[/-]\d{1,2}'
        r'(?:\s+\d{1,2}:\d{2})?'
        r'\s*(?:公開|更新)\s*$',
      ),
      '',
    );

    return result.trim();
  }

  String _extractPublishedDate(String value) {
    final japaneseMatch = RegExp(
      r'(\d{4}年\s*\d{1,2}月\s*\d{1,2}日'
      r'(?:\s+\d{1,2}:\d{2})?)'
      r'\s*(?:公開|更新)',
    ).firstMatch(value);

    if (japaneseMatch != null) {
      return _cleanPublishedDate(japaneseMatch.group(1) ?? '');
    }

    final numericMatch = RegExp(
      r'(\d{4}[/-]\d{1,2}[/-]\d{1,2}'
      r'(?:\s+\d{1,2}:\d{2})?)'
      r'\s*(?:公開|更新)?',
    ).firstMatch(value);

    if (numericMatch != null) {
      return _cleanPublishedDate(numericMatch.group(1) ?? '');
    }

    return '';
  }

  String _cleanPublishedDate(String value) {
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s*(?:公開|更新)\s*$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  String _toIsoLikeDate(String value) {
    final raw = value.trim();

    if (raw.isEmpty) {
      return '';
    }

    final japaneseMatch = RegExp(
      r'(\d{4})年\s*'
      r'(\d{1,2})月\s*'
      r'(\d{1,2})日'
      r'(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(raw);

    if (japaneseMatch != null) {
      final year = japaneseMatch.group(1) ?? '';
      final month = (japaneseMatch.group(2) ?? '').padLeft(2, '0');
      final day = (japaneseMatch.group(3) ?? '').padLeft(2, '0');

      final hour = japaneseMatch.group(4);
      final minute = japaneseMatch.group(5);

      if (hour != null && minute != null) {
        return '$year-$month-$day '
            '${hour.padLeft(2, '0')}:$minute';
      }

      return '$year-$month-$day';
    }

    final numericMatch = RegExp(
      r'(\d{4})[/-]'
      r'(\d{1,2})[/-]'
      r'(\d{1,2})'
      r'(?:[T\s]+(\d{1,2}):(\d{2})(?::\d{2})?)?',
    ).firstMatch(raw);

    if (numericMatch != null) {
      final year = numericMatch.group(1) ?? '';
      final month = (numericMatch.group(2) ?? '').padLeft(2, '0');
      final day = (numericMatch.group(3) ?? '').padLeft(2, '0');

      final hour = numericMatch.group(4);
      final minute = numericMatch.group(5);

      if (hour != null && minute != null) {
        return '$year-$month-$day '
            '${hour.padLeft(2, '0')}:$minute';
      }

      return '$year-$month-$day';
    }

    return raw;
  }

  bool _isGenericEpisodeTitle(String title) {
    final normalized = title.trim();

    if (normalized.isEmpty) {
      return true;
    }

    const genericTitles = <String>{
      '1話目から読む',
      '最初から読む',
      '続きを読む',
      'この話を読む',
      'エピソードを読む',
      '最新話を読む',
    };

    return genericTitles.contains(normalized);
  }

  // ---------------------------------------------------------------------------
  // 数値・ジャンル
  // ---------------------------------------------------------------------------

  int _parseNumber(String? raw) {
    final normalized = (raw ?? '').replaceAll(',', '').trim();

    if (normalized.isEmpty) {
      return 0;
    }

    return int.tryParse(normalized) ?? 0;
  }

  int _bigGenreNumber(String genre) {
    if (genre.contains('恋愛') || genre.contains('ラブコメ')) {
      return 1;
    }

    if (genre.contains('ファンタジー')) {
      return 2;
    }

    if (genre.contains('SF')) {
      return 4;
    }

    if (genre.contains('ドラマ') ||
        genre.contains('ミステリー') ||
        genre.contains('ホラー') ||
        genre.contains('歴史') ||
        genre.contains('エッセイ') ||
        genre.contains('評論') ||
        genre.contains('詩') ||
        genre.contains('童話')) {
      return 3;
    }

    return 99;
  }
}
