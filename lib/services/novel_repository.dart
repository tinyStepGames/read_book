import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/download.dart';
import '../models/episode.dart';
import '../models/favorite.dart';
import '../models/favorite_color.dart';
import '../models/read_mark.dart';
import '../models/saved_search.dart';
import '../models/site.dart';
import '../models/work.dart';
import 'kakuyomu_scraper.dart';
import 'narou_api_client.dart';

class NovelRepository {
  final NarouApiClient narouApiClient = NarouApiClient();
  final KakuyomuScraper kakuyomuScraper = KakuyomuScraper();

  /// 作品詳細画面を開いたときに、サイトから完全な作品情報を取得します。
  ///
  /// 現在はカクヨムの完全なあらすじ取得に使用します。
  Future<void> refreshWorkDetails(Work work) async {
    if (work.siteIndex < 0 || work.siteIndex >= Site.values.length) {
      return;
    }

    final site = Site.values[work.siteIndex];

    if (site != Site.kakuyomu) {
      return;
    }

    final details = await kakuyomuScraper.fetchWorkDetails(work.workId);

    final fullSummary = details.summary.trim();

    if (fullSummary.isEmpty) {
      return;
    }

    if (work.summary.trim() == fullSummary) {
      return;
    }

    work.summary = fullSummary;

    // Hive管理中のWorkならsave()でも保存できますが、
    // putを使うことで未登録のWorkにも対応します。
    await saveWork(work);
  }

  // キャッシュの最大保持件数。超えたら古いものから自動削除する。
  static const int _maxCacheSize = 1000;

  Box<Work> get _workBox => Hive.box<Work>('works');
  Box<Episode> get _episodeBox => Hive.box<Episode>('episodes'); // 一時キャッシュ
  Box<Download> get _downloadBox => Hive.box<Download>('downloads'); // 永続ダウンロード
  Box<ReadMark> get _readMarkBox => Hive.box<ReadMark>('read_marks'); // 既読記録
  Box<Favorite> get _favoriteBox => Hive.box<Favorite>('favorites');
  Box<SavedSearch> get _savedSearchBox =>
      Hive.box<SavedSearch>('saved_searches');

  String _key(String workId, int episodeNo) => '${workId}_$episodeNo';

  // ---------- Work ----------

  Work workFromNarouResult(NarouSearchResult result) {
    final parsedUpdatedAt = DateTime.tryParse(result.generalLastup);

    return Work(
      workId: result.ncode,
      siteIndex: result.site.index,
      title: result.title,
      author: result.author,
      genre: result.genreName,
      summary: result.summary,
      totalEpisodeCount: result.generalAllNo,
      checkedEpisodeCount: result.generalAllNo,
      lastUpdatedAt: parsedUpdatedAt ?? DateTime.now(),
      isCompleted: result.isCompleted,
      authorId: result.authorId,
      keyword: result.keyword,
    );
  }

  List<Work> get registeredWorks => _workBox.values.toList();

  Work? getWork(String workId) => _workBox.get(workId);

  Future<void> saveWork(Work work) async {
    await _workBox.put(work.workId, work);
  }

  // ---------- Favorite(作品) ----------

  FavoriteColor? favoriteColorOf(String workId) {
    final fav = _favoriteBox.values.firstWhereOrNull(
      (f) => f.targetType == FavoriteTargetType.work && f.targetKey == workId,
    );
    if (fav == null) return null;
    return FavoriteColor.values[fav.colorIndex];
  }

  dynamic _favoriteKeyOf(String workId) {
    return _favoriteBox.keys.firstWhereOrNull((k) {
      final f = _favoriteBox.get(k);
      return f != null &&
          f.targetType == FavoriteTargetType.work &&
          f.targetKey == workId;
    });
  }

  Future<void> setFavoriteColor(Work work, FavoriteColor? color) async {
    if (!_workBox.containsKey(work.workId)) {
      await _workBox.put(work.workId, work);
    }

    final existingKey = _favoriteKeyOf(work.workId);

    if (color == null) {
      if (existingKey != null) {
        await _favoriteBox.delete(existingKey);
      }
      return;
    }

    if (existingKey != null) {
      final fav = _favoriteBox.get(existingKey)!;
      fav.colorIndex = color.index;
      await fav.save();
    } else {
      await _favoriteBox.add(
        Favorite(
          targetTypeIndex: FavoriteTargetType.work.index,
          colorIndex: color.index,
          targetKey: work.workId,
          registeredAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> addFavoriteFromNarouResult(
    NarouSearchResult result, {
    FavoriteColor color = FavoriteColor.blue,
  }) async {
    final work = workFromNarouResult(result);
    await setFavoriteColor(work, color);
  }

  Future<void> removeFavorite(String workId) async {
    final work = _workBox.get(workId);
    if (work != null) {
      await setFavoriteColor(work, null);
    } else {
      final existingKey = _favoriteKeyOf(workId);
      if (existingKey != null) {
        await _favoriteBox.delete(existingKey);
      }
    }
  }

  List<Favorite> get workFavorites => _favoriteBox.values
      .where((f) => f.targetType == FavoriteTargetType.work)
      .toList();

  // ---------- Favorite(検索条件) ----------

  List<Favorite> get savedSearchFavorites => _favoriteBox.values
      .where((f) => f.targetType == FavoriteTargetType.savedSearch)
      .toList();

  SavedSearch? getSavedSearch(String id) => _savedSearchBox.get(id);

  Favorite? savedSearchFavoriteFor({
    required String keyword,
    required String order,
    required bool authorNameOnly,
    required bool keywordOnly,
    Site site = Site.narou,
  }) {
    for (final fav in savedSearchFavorites) {
      final saved = _savedSearchBox.get(fav.targetKey);

      if (saved != null &&
          saved.siteIndex == site.index &&
          saved.keyword == keyword &&
          saved.order == order &&
          saved.authorNameOnly == authorNameOnly &&
          saved.keywordOnly == keywordOnly) {
        return fav;
      }
    }

    return null;
  }

  Future<void> addSearchFavorite({
    required String keyword,
    required String order,
    bool authorNameOnly = false,
    bool keywordOnly = false,
    Site site = Site.narou,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final savedSearch = SavedSearch(
      id: id,
      siteIndex: site.index,
      keyword: keyword,
      order: order,
      authorNameOnly: authorNameOnly,
      keywordOnly: keywordOnly,
    );
    await _savedSearchBox.put(id, savedSearch);

    await _favoriteBox.add(
      Favorite(
        targetTypeIndex: FavoriteTargetType.savedSearch.index,
        colorIndex: FavoriteColor.blue.index,
        targetKey: id,
        registeredAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeSearchFavorite(String savedSearchId) async {
    final key = _favoriteBox.keys.firstWhereOrNull((k) {
      final f = _favoriteBox.get(k);
      return f != null &&
          f.targetType == FavoriteTargetType.savedSearch &&
          f.targetKey == savedSearchId;
    });
    if (key != null) {
      await _favoriteBox.delete(key);
    }
    await _savedSearchBox.delete(savedSearchId);
  }

  // ---------- 既読管理(本文を持たない軽量な記録) ----------

  bool isEpisodeRead(String workId, int episodeNo) =>
      _readMarkBox.containsKey(_key(workId, episodeNo));

  /// 指定した作品の中で、1話でも既読の話があるかどうか
  bool hasAnyRead(String workId) {
    return _readMarkBox.values.any((r) => r.workId == workId);
  }

  /// ダウンロード済みファイルを全て削除する(既読状態には影響しない)
  Future<void> deleteAllDownloads(String workId) async {
    final keys = _downloadBox.keys
        .where((k) => _downloadBox.get(k)?.workId == workId)
        .toList();
    for (final k in keys) {
      await _downloadBox.delete(k);
    }
  }

  /// 既読記録とキャッシュ本文を全て削除する(ダウンロードファイルには影響しない)
  Future<void> deleteAllReadAndCache(String workId) async {
    final readKeys = _readMarkBox.keys
        .where((k) => _readMarkBox.get(k)?.workId == workId)
        .toList();
    for (final k in readKeys) {
      await _readMarkBox.delete(k);
    }

    final cacheKeys = _episodeBox.keys
        .where((k) => _episodeBox.get(k)?.workId == workId)
        .toList();
    for (final k in cacheKeys) {
      await _episodeBox.delete(k);
    }
  }

  Future<void> _markRead(String workId, int episodeNo) async {
    final key = _key(workId, episodeNo);
    if (!_readMarkBox.containsKey(key)) {
      await _readMarkBox.put(
        key,
        ReadMark(workId: workId, episodeNo: episodeNo, readAt: DateTime.now()),
      );
    }
  }

  /// 未読の最初の話数を返す(全話既読ならnull)
  int? firstUnreadEpisodeNo(
    String workId,
    List<Map<String, String>> episodeList,
  ) {
    for (final entry in episodeList) {
      final no = int.tryParse(entry['episodeNo'] ?? '');
      if (no == null) continue;
      if (!isEpisodeRead(workId, no)) return no;
    }
    return null;
  }

  // ---------- ダウンロード判定(永続) ----------

  bool isDownloaded(Work work, int episodeNo) =>
      _downloadBox.containsKey(_key(work.workId, episodeNo));

  bool hasAnyDownload(String workId) =>
      _downloadBox.values.any((d) => d.workId == workId);

  // ---------- 目次取得 ----------

  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    final site = Site.values[work.siteIndex];

    if (site == Site.narou) {
      return narouApiClient.fetchEpisodeList(work.workId);
    }

    return kakuyomuScraper.fetchEpisodeList(work.workId);
  }

  // ---------- 本文取得(読む用) ----------
  // 優先順位: 永続ダウンロード > キャッシュ > ネットワーク取得
  // どの経路であっても、読んだ時点で必ず既読として記録する。
  Future<String> fetchEpisode({
    required Work work,
    required int episodeNo,
    required String episodeTitle,
  }) async {
    final key = _key(work.workId, episodeNo);

    // 1. 永続ダウンロード済みならそれを使う(ネットワークアクセス不要)
    final downloaded = _downloadBox.get(key);
    if (downloaded != null) {
      await _markRead(work.workId, episodeNo);
      return downloaded.body;
    }

    // 2. キャッシュにあれば使う(アクセス時刻を更新して長生きさせる)
    final cached = _episodeBox.get(key);
    if (cached != null) {
      cached.lastAccessedAt = DateTime.now();
      await cached.save();
      await _markRead(work.workId, episodeNo);
      return cached.body;
    }

    // 3. どちらにも無い場合はネットワークから取得し、キャッシュに保存する
    final body = await _fetchBodyFromNetwork(work, episodeNo, episodeTitle);
    await _putCache(work.workId, episodeNo, episodeTitle, body);
    await _markRead(work.workId, episodeNo);
    return body;
  }

  Future<void> downloadEpisode({
    required Work work,
    required int episodeNo,
    required String episodeTitle,
    String publishedAt = '',
  }) async {
    // 書庫で作品情報を表示できるように保存します。
    await saveWork(work);

    final key = _key(work.workId, episodeNo);

    final existing = _downloadBox.get(key);

    if (existing != null) {
      final normalizedPublishedAt = publishedAt.trim();

      if (normalizedPublishedAt.isNotEmpty &&
          existing.publishedAt != normalizedPublishedAt) {
        existing.publishedAt = normalizedPublishedAt;
        await existing.save();
      }

      return;
    }

    final cached = _episodeBox.get(key);

    final body = cached != null
        ? cached.body
        : await _fetchBodyFromNetwork(work, episodeNo, episodeTitle);

    await _downloadBox.put(
      key,
      Download(
        workId: work.workId,
        episodeNo: episodeNo,
        episodeTitle: episodeTitle,
        body: body,
        downloadedAt: DateTime.now(),
        publishedAt: publishedAt.trim(),
      ),
    );
  }

  /// 1話分の既存ダウンロードへ掲載日を設定します。
  Future<void> updateDownloadPublishedDate({
    required Work work,
    required int episodeNo,
    required String publishedAt,
  }) async {
    final normalizedPublishedAt = publishedAt.trim();

    if (normalizedPublishedAt.isEmpty) {
      return;
    }

    final key = _key(work.workId, episodeNo);

    final download = _downloadBox.get(key);

    if (download == null) {
      return;
    }

    if (download.publishedAt == normalizedPublishedAt) {
      return;
    }

    download.publishedAt = normalizedPublishedAt;
    await download.save();
  }

  /// 目次の掲載日を、すでにダウンロード済みの各話へ反映します。
  ///
  /// 本文は再ダウンロードしません。
  Future<void> updateDownloadPublishedDates({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {
    for (var index = 0; index < episodeList.length; index++) {
      final entry = episodeList[index];

      final episodeNo = int.tryParse(entry['episodeNo'] ?? '') ?? index + 1;

      final publishedAt =
          entry['publishedAt'] ??
          entry['update'] ??
          entry['published'] ??
          entry['updatedAt'] ??
          '';

      if (publishedAt.trim().isEmpty) {
        continue;
      }

      await updateDownloadPublishedDate(
        work: work,
        episodeNo: episodeNo,
        publishedAt: publishedAt,
      );
    }
  }

  Future<String> _fetchBodyFromNetwork(
    Work work,
    int episodeNo,
    String episodeTitle,
  ) async {
    final site = Site.values[work.siteIndex];

    if (site == Site.narou) {
      final episode = await narouApiClient.fetchEpisodeBody(
        workId: work.workId,
        episodeNo: episodeNo,
        episodeTitle: episodeTitle,
      );

      return episode.body;
    }

    final episodeId = await kakuyomuScraper.resolveEpisodeId(
      workId: work.workId,
      episodeNo: episodeNo,
    );

    final episode = await kakuyomuScraper.fetchEpisodeBody(
      workId: work.workId,
      episodeId: episodeId,
      episodeNo: episodeNo,
      episodeTitle: episodeTitle,
    );

    return episode.body;
  }

  Future<void> _putCache(
    String workId,
    int episodeNo,
    String episodeTitle,
    String body,
  ) async {
    final key = _key(workId, episodeNo);
    await _episodeBox.put(
      key,
      Episode(
        workId: workId,
        episodeNo: episodeNo,
        episodeTitle: episodeTitle,
        body: body,
        fetchedAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
      ),
    );
    await _evictCacheIfNeeded();
  }

  /// キャッシュが上限を超えたら、最後にアクセスした時刻が古いものから削除する
  Future<void> _evictCacheIfNeeded() async {
    if (_episodeBox.length <= _maxCacheSize) return;

    final entries = _episodeBox.toMap().entries.toList()
      ..sort((a, b) {
        final aTime = a.value.lastAccessedAt ?? a.value.fetchedAt;
        final bTime = b.value.lastAccessedAt ?? b.value.fetchedAt;
        return aTime.compareTo(bTime);
      });

    final overflow = _episodeBox.length - _maxCacheSize;
    for (var i = 0; i < overflow; i++) {
      await _episodeBox.delete(entries[i].key);
    }
  }

  // ---------- 一括ダウンロード ----------

  Future<void> bulkDownload({
    required Work work,
    required List<Map<String, String>> episodeList,
    void Function(int done, int total)? onProgress,
  }) async {
    // 既存ダウンロードにも掲載日を補完します。
    await updateDownloadPublishedDates(work: work, episodeList: episodeList);

    for (var index = 0; index < episodeList.length; index++) {
      final entry = episodeList[index];

      final episodeNo = int.tryParse(entry['episodeNo'] ?? '') ?? index + 1;

      final title = entry['title'] ?? '第$episodeNo話';

      final publishedAt =
          entry['publishedAt'] ??
          entry['update'] ??
          entry['published'] ??
          entry['updatedAt'] ??
          '';

      if (!isDownloaded(work, episodeNo)) {
        await downloadEpisode(
          work: work,
          episodeNo: episodeNo,
          episodeTitle: title,
          publishedAt: publishedAt,
        );

        await Future<void>.delayed(const Duration(seconds: 1));
      } else if (publishedAt.trim().isNotEmpty) {
        await updateDownloadPublishedDate(
          work: work,
          episodeNo: episodeNo,
          publishedAt: publishedAt,
        );
      }

      onProgress?.call(index + 1, episodeList.length);
    }
  }
}
