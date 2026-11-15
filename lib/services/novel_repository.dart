import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/download.dart';
import '../models/episode.dart';
import '../models/favorite.dart';
import '../models/favorite_color.dart';
import '../models/read_mark.dart';
import '../models/saved_search.dart';
import '../models/search_filters.dart';
import '../models/site.dart';
import '../models/work.dart';
import '../utils/novel_body_codec.dart';
import '../utils/work_metadata_merger.dart';
import 'download_refresh_planner.dart';
import 'download_refresh_runner.dart';
import 'illustration_storage_service.dart';
import 'kakuyomu_scraper.dart';
import 'narou_api_client.dart';

class NovelRepository {
  NovelRepository({
    IllustrationStorageService? illustrationStorageService,
    NarouApiClient? narouApiClient,
    KakuyomuScraper? kakuyomuScraper,
    DownloadRefreshRunner? downloadRefreshRunner,
  }) : illustrationStorageService =
           illustrationStorageService ?? IllustrationStorageService(),
       narouApiClient = narouApiClient ?? NarouApiClient(),
       kakuyomuScraper = kakuyomuScraper ?? KakuyomuScraper(),
       _downloadRefreshRunner =
           downloadRefreshRunner ?? DownloadRefreshRunner();

  final IllustrationStorageService illustrationStorageService;
  final NarouApiClient narouApiClient;
  final KakuyomuScraper kakuyomuScraper;
  final Set<String> _refreshingDownloadKeys = <String>{};
  final DownloadRefreshRunner _downloadRefreshRunner;
  final Set<String> _refreshingWorkIds = <String>{};
  final Set<String> _refreshingMetadataWorkIds = <String>{};

  /// 登録済みのカクヨム作品情報を取得し、安全に統合して保存します。
  ///
  /// trueは保存完了、falseは取得中の削除・変更による保留です。
  /// 通信失敗・不正応答・未登録・重複実行は例外で返します。
  Future<bool> refreshStoredKakuyomuWorkDetails({required Work work}) async {
    final workId = work.workId;
    final siteIndex = work.siteIndex;

    if (siteIndex != Site.kakuyomu.index ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(workId)) {
      throw ArgumentError('更新対象のカクヨム作品情報が不正です。');
    }

    if (!_refreshingMetadataWorkIds.add(workId)) {
      throw StateError('この作品の情報更新はすでに実行中です。');
    }

    try {
      final original = _workBox.get(workId);
      if (original == null ||
          original.workId != workId ||
          original.siteIndex != siteIndex) {
        throw StateError('更新対象の作品が登録されていません。');
      }

      final snapshot = Work(
        workId: original.workId,
        siteIndex: original.siteIndex,
        title: original.title,
        author: original.author,
        genre: original.genre,
        summary: original.summary,
        totalEpisodeCount: original.totalEpisodeCount,
        checkedEpisodeCount: original.checkedEpisodeCount,
        lastUpdatedAt: original.lastUpdatedAt,
        isCompleted: original.isCompleted,
        firstOpenedAt: original.firstOpenedAt,
        authorId: original.authorId,
        keyword: original.keyword,
      );

      bool stillCurrent() {
        final current = _workBox.get(workId);
        return work.workId == workId &&
            work.siteIndex == siteIndex &&
            identical(current, original) &&
            current != null &&
            current.workId == snapshot.workId &&
            current.siteIndex == snapshot.siteIndex &&
            current.title == snapshot.title &&
            current.author == snapshot.author &&
            current.genre == snapshot.genre &&
            current.summary == snapshot.summary &&
            current.totalEpisodeCount == snapshot.totalEpisodeCount &&
            current.checkedEpisodeCount == snapshot.checkedEpisodeCount &&
            current.lastUpdatedAt == snapshot.lastUpdatedAt &&
            current.isCompleted == snapshot.isCompleted &&
            current.firstOpenedAt == snapshot.firstOpenedAt &&
            current.authorId == snapshot.authorId &&
            current.keyword == snapshot.keyword;
      }

      final details = await kakuyomuScraper.fetchWorkMetadata(workId);

      if (!stillCurrent()) {
        return false;
      }
      if (details.workId != workId) {
        throw const FormatException('カクヨムの作品IDが一致しません。');
      }

      final incoming = Work(
        workId: workId,
        siteIndex: siteIndex,
        title: details.title,
        author: details.author,
        genre: details.genre,
        summary: details.summary,
        totalEpisodeCount: details.episodeCount,
        checkedEpisodeCount: snapshot.checkedEpisodeCount,
        // APIの作品編集日時を本文の更新日時として流用しません。
        lastUpdatedAt: snapshot.lastUpdatedAt,
        isCompleted: details.isCompleted,
        authorId: details.authorId,
        keyword: details.keyword,
      );

      final replacement = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: incoming,
        existing: snapshot,
      );

      await _workBox.put(workId, replacement);
      return true;
    } finally {
      _refreshingMetadataWorkIds.remove(workId);
    }
  }

  /// 登録済みのなろう作品情報を取得し、端末側の確認状態を維持して保存します。
  ///
  /// trueは保存完了、falseは取得中の削除・変更による保留です。
  /// 通信失敗・不正応答・未登録・重複実行は例外で返します。
  /// 既存のWorkオブジェクトは直接変更しません。
  Future<bool> refreshStoredNarouWorkDetails({required Work work}) async {
    final workId = work.workId;
    final siteIndex = work.siteIndex;

    if (siteIndex != Site.narou.index ||
        !RegExp(r'^n[0-9]+[a-z]+$', caseSensitive: false).hasMatch(workId)) {
      throw ArgumentError('更新対象のなろう作品情報が不正です。');
    }

    if (!_refreshingMetadataWorkIds.add(workId)) {
      throw StateError('この作品の情報更新はすでに実行中です。');
    }

    try {
      final original = _workBox.get(workId);
      if (original == null ||
          original.workId != workId ||
          original.siteIndex != siteIndex) {
        throw StateError('更新対象の作品が登録されていません。');
      }

      final snapshot = Work(
        workId: original.workId,
        siteIndex: original.siteIndex,
        title: original.title,
        author: original.author,
        genre: original.genre,
        summary: original.summary,
        totalEpisodeCount: original.totalEpisodeCount,
        checkedEpisodeCount: original.checkedEpisodeCount,
        lastUpdatedAt: original.lastUpdatedAt,
        isCompleted: original.isCompleted,
        firstOpenedAt: original.firstOpenedAt,
        authorId: original.authorId,
        keyword: original.keyword,
      );

      bool stillCurrent() {
        final current = _workBox.get(workId);
        return work.workId == workId &&
            work.siteIndex == siteIndex &&
            identical(current, original) &&
            current != null &&
            current.workId == snapshot.workId &&
            current.siteIndex == snapshot.siteIndex &&
            current.title == snapshot.title &&
            current.author == snapshot.author &&
            current.genre == snapshot.genre &&
            current.summary == snapshot.summary &&
            current.totalEpisodeCount == snapshot.totalEpisodeCount &&
            current.checkedEpisodeCount == snapshot.checkedEpisodeCount &&
            current.lastUpdatedAt == snapshot.lastUpdatedAt &&
            current.isCompleted == snapshot.isCompleted &&
            current.firstOpenedAt == snapshot.firstOpenedAt &&
            current.authorId == snapshot.authorId &&
            current.keyword == snapshot.keyword;
      }

      final result = await narouApiClient.fetchByNcode(workId);

      if (!stillCurrent()) {
        return false;
      }

      if (result == null ||
          result.site != Site.narou ||
          result.ncode.toLowerCase() != workId.toLowerCase() ||
          result.title.trim().isEmpty ||
          result.author.trim().isEmpty ||
          result.generalAllNo <= 0 ||
          (result.end != 0 && result.end != 1) ||
          (result.novelType != 1 && result.novelType != 2) ||
          !const <int>{1, 2, 3, 4, 98, 99}.contains(result.biggenre)) {
        throw const FormatException('なろうの作品情報を安全に取得できませんでした。');
      }

      final incoming = Work(
        // APIのNコードの大文字・小文字でローカルキーを変えません。
        workId: workId,
        siteIndex: siteIndex,
        title: result.title,
        author: result.author,
        genre: result.genreName,
        summary: result.summary,
        totalEpisodeCount: result.generalAllNo,
        checkedEpisodeCount: snapshot.checkedEpisodeCount,
        lastUpdatedAt:
            DateTime.tryParse(result.generalLastup) ?? snapshot.lastUpdatedAt,
        isCompleted: result.isCompleted,
        authorId: result.authorId,
        keyword: result.keyword,
      );

      final replacement = WorkMetadataMerger.mergeRefreshedDetails(
        incoming: incoming,
        existing: snapshot,
      );

      await _workBox.put(workId, replacement);
      return true;
    } finally {
      _refreshingMetadataWorkIds.remove(workId);
    }
  }

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

  /// 指定作品のダウンロード済みエピソード一覧を返します。
  ///
  /// オフライン時のReader画面で、前話・次話の移動判定に使用します。

  // キャッシュの最大保持件数。超えたら古いものから自動削除する。
  static const int _maxCacheSize = 1000;

  Box<Work> get _workBox => Hive.box<Work>('works');
  Box<Episode> get _episodeBox => Hive.box<Episode>('episodes'); // 一時キャッシュ
  Box<Download> get _downloadBox => Hive.box<Download>('downloads'); // 永続ダウンロード
  Box<ReadMark> get _readMarkBox => Hive.box<ReadMark>('read_marks'); // 既読記録
  Box<Favorite> get _favoriteBox => Hive.box<Favorite>('favorites');
  Box<SavedSearch> get _savedSearchBox =>
      Hive.box<SavedSearch>('saved_searches');

  String _siteKeyForWork(Work work) {
    if (work.siteIndex < 0 || work.siteIndex >= Site.values.length) {
      throw StateError('作品のサイト情報が不正です');
    }

    return Site.values[work.siteIndex].name;
  }

  String _key(String workId, int episodeNo) => '${workId}_$episodeNo';

  // ---------- Work ----------

  Work workFromNarouResult(NarouSearchResult result) {
    final existing = _workBox.get(result.ncode);
    final parsedUpdatedAt = DateTime.tryParse(result.generalLastup);

    final incoming = Work(
      workId: result.ncode,
      siteIndex: result.site.index,
      title: result.title,
      author: result.author,
      genre: result.genreName,
      summary: result.summary,
      totalEpisodeCount: result.generalAllNo,
      checkedEpisodeCount: result.generalAllNo,
      lastUpdatedAt:
          parsedUpdatedAt ?? existing?.lastUpdatedAt ?? DateTime.now(),
      isCompleted: result.isCompleted,
      authorId: result.authorId,
      keyword: result.keyword,
    );

    return WorkMetadataMerger.mergeSearchResult(
      incoming: incoming,
      existing: existing,
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
          lastKnownEpisodeCount: work.totalEpisodeCount,
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
    SearchFilters filters = const SearchFilters(),
  }) {
    for (final fav in savedSearchFavorites) {
      final saved = _savedSearchBox.get(fav.targetKey);

      if (saved != null &&
          saved.siteIndex == site.index &&
          saved.keyword == keyword &&
          saved.order == order &&
          saved.authorNameOnly == authorNameOnly &&
          saved.keywordOnly == keywordOnly &&
          saved.matchesFilters(filters)) {
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
    SearchFilters filters = const SearchFilters(),
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final savedSearch = SavedSearch(
      id: id,
      siteIndex: site.index,
      keyword: keyword,
      order: order,
      authorNameOnly: authorNameOnly,
      keywordOnly: keywordOnly,
      serialStatusIndex: filters.serialStatus.index,
      lengthPresetIndex: filters.lengthPreset.index,
      customMinimumLength: filters.customMinimumLength,
      customMaximumLength: filters.customMaximumLength,
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

  /// ダウンロード済みファイルと挿絵を全て削除する。
  ///
  /// 既読状態と履歴には影響しません。
  Future<void> deleteAllDownloads(String workId, {required Site site}) async {
    await illustrationStorageService.deleteWork(
      siteKey: site.name,
      workId: workId,
    );

    final keys = _downloadBox.keys
        .where((key) => _downloadBox.get(key)?.workId == workId)
        .toList();

    for (final key in keys) {
      await _downloadBox.delete(key);
    }
  }

  /// 指定した1話のダウンロード本文と挿絵を削除する。
  ///
  /// 既読状態と履歴には影響しません。
  Future<void> deleteDownloadedEpisode({
    required String workId,
    required int episodeNo,
    required Site site,
  }) async {
    await illustrationStorageService.deleteEpisode(
      siteKey: site.name,
      workId: workId,
      episodeNo: episodeNo,
    );

    final keys = _downloadBox.keys.where((key) {
      final download = _downloadBox.get(key);

      return download?.workId == workId && download?.episodeNo == episodeNo;
    }).toList();

    for (final key in keys) {
      await _downloadBox.delete(key);
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

  /// 指定作品のダウンロード済みエピソード一覧を返します。
  ///
  /// オフライン時のReader画面で、前話・次話の移動判定に使用します。
  List<Map<String, String>> getDownloadedEpisodeList(String workId) {
    final downloads =
        _downloadBox.values
            .where((download) => download.workId == workId)
            .toList()
          ..sort((a, b) => a.episodeNo.compareTo(b.episodeNo));

    return downloads
        .map(
          (download) => <String, String>{
            'episodeNo': download.episodeNo.toString(),
            'title': download.episodeTitle,
            'episodeTitle': download.episodeTitle,
            'publishedAt': download.publishedAt,
          },
        )
        .toList();
  }

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

    // 1. 永続ダウンロード済みならそれを使う。
    //
    // ローカル挿絵が欠落している場合だけ再取得を試みます。
    // 挿絵の確認・取得に失敗しても、保存済み本文の表示は継続します。
    final downloaded = _downloadBox.get(key);
    if (downloaded != null) {
      var body = downloaded.body;

      try {
        final localizedBody = await illustrationStorageService
            .localizeDownloadedBody(
              siteKey: _siteKeyForWork(work),
              workId: work.workId,
              episodeNo: episodeNo,
              body: body,
            );

        if (localizedBody != body) {
          downloaded.body = localizedBody;
          await downloaded.save();
          body = localizedBody;
        }
      } catch (_) {
        // オフラインやストレージ障害時も、保存済み本文をそのまま表示します。
      }

      await _markRead(work.workId, episodeNo);
      return body;
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
    String sourceId = '',
    String sourceUpdatedAt = '',
  }) async {
    // 書庫で作品情報を表示できるように保存します。
    await saveWork(work);

    final key = _key(work.workId, episodeNo);
    final siteKey = _siteKeyForWork(work);
    final existing = _downloadBox.get(key);

    if (existing != null) {
      final localizedBody = await illustrationStorageService
          .localizeDownloadedBody(
            siteKey: siteKey,
            workId: work.workId,
            episodeNo: episodeNo,
            body: existing.body,
          );
      final normalizedPublishedAt = publishedAt.trim();
      var needsSave = false;

      if (localizedBody != existing.body) {
        existing.body = localizedBody;
        needsSave = true;
      }

      if (normalizedPublishedAt.isNotEmpty &&
          existing.publishedAt != normalizedPublishedAt) {
        existing.publishedAt = normalizedPublishedAt;
        needsSave = true;
      }

      if (needsSave) {
        await existing.save();
      }

      return;
    }

    final cached = _episodeBox.get(key);

    final sourceBody = cached != null
        ? cached.body
        : await _fetchBodyFromNetwork(work, episodeNo, episodeTitle);

    final localizedBody = await illustrationStorageService
        .localizeDownloadedBody(
          siteKey: siteKey,
          workId: work.workId,
          episodeNo: episodeNo,
          body: sourceBody,
        );

    await _downloadBox.put(
      key,
      Download(
        workId: work.workId,
        episodeNo: episodeNo,
        episodeTitle: episodeTitle,
        body: localizedBody,
        downloadedAt: DateTime.now(),
        publishedAt: publishedAt.trim(),
        // キャッシュ本文と現在の目次が同じ版とは限りません。
        sourceId: cached == null ? sourceId.trim() : '',
        sourceUpdatedAt: cached == null && sourceId.trim().isNotEmpty
            ? sourceUpdatedAt.trim()
            : '',
      ),
    );
  }

  /// バックグラウンド取得済みの本文を既存形式で保存します。
  Future<void> saveDownloadedEpisodeBody({
    required Work work,
    required int episodeNo,
    required String episodeTitle,
    required String body,
    String publishedAt = '',
    String sourceId = '',
    String sourceUpdatedAt = '',
  }) async {
    await saveWork(work);

    if (body.trim().isEmpty) {
      throw StateError('保存する本文が空です');
    }

    final key = _key(work.workId, episodeNo);
    final localizedBody = await illustrationStorageService
        .localizeDownloadedBody(
          siteKey: _siteKeyForWork(work),
          workId: work.workId,
          episodeNo: episodeNo,
          body: body,
        );
    final existing = _downloadBox.get(key);

    if (existing != null) {
      final normalizedPublishedAt = publishedAt.trim();
      var needsSave = false;

      if (localizedBody != existing.body) {
        existing.body = localizedBody;
        // 本文が変わった場合、以前の版を示す情報は引き継ぎません。
        // 既存本文の更新専用処理は、後続段階で別途実装します。
        existing.sourceId = '';
        existing.sourceUpdatedAt = '';
        needsSave = true;
      }

      if (normalizedPublishedAt.isNotEmpty &&
          existing.publishedAt != normalizedPublishedAt) {
        existing.publishedAt = normalizedPublishedAt;
        needsSave = true;
      }

      if (needsSave) {
        await existing.save();
      }

      return;
    }

    await _downloadBox.put(
      key,
      Download(
        workId: work.workId,
        episodeNo: episodeNo,
        episodeTitle: episodeTitle,
        body: localizedBody,
        downloadedAt: DateTime.now(),
        publishedAt: publishedAt.trim(),
        sourceId: sourceId.trim(),
        sourceUpdatedAt: sourceId.trim().isNotEmpty
            ? sourceUpdatedAt.trim()
            : '',
      ),
    );
  }

  /// 識別子が一致する保存済みの1話を更新します。
  ///
  /// falseは対象なし・識別子不一致・ローカル競合による保留です。
  /// 取得・挿絵準備・保存の失敗は例外として呼び出し元へ返します。
  /// このメソッド自身は目次全体の重複・移動判定を行いません。
  Future<bool> refreshDownloadedEpisode({
    required Work work,
    required Map<String, String> episodeEntry,
  }) async {
    final workId = work.workId;
    final siteIndex = work.siteIndex;
    final siteKey = _siteKeyForWork(work);
    final entry = Map<String, String>.from(episodeEntry);
    final number = int.tryParse((entry['episodeNo'] ?? '').trim());
    final sourceId = (entry['sourceId'] ?? '').trim();

    if (number == null || number <= 0) {
      throw ArgumentError('更新対象の話番号が不正です。');
    }

    final key = _key(workId, number);
    if (!_refreshingDownloadKeys.add(key)) {
      throw StateError('この話の更新処理はすでに実行中です。');
    }

    try {
      final registeredWork = _workBox.get(workId);
      final original = _downloadBox.get(key);

      if (registeredWork == null ||
          registeredWork.siteIndex != siteIndex ||
          original == null ||
          original.workId != workId ||
          original.episodeNo != number ||
          sourceId.isEmpty ||
          original.sourceId.trim() != sourceId) {
        return false;
      }

      // Hive管理中のオブジェクトを直接書き換えないためのスナップショット。
      final snapshot = Download(
        workId: original.workId,
        episodeNo: original.episodeNo,
        episodeTitle: original.episodeTitle,
        body: original.body,
        downloadedAt: original.downloadedAt,
        publishedAt: original.publishedAt,
        sourceId: original.sourceId,
        sourceUpdatedAt: original.sourceUpdatedAt,
      );

      bool stillCurrent() {
        final currentWork = _workBox.get(workId);
        final current = _downloadBox.get(key);
        return identical(currentWork, registeredWork) &&
            currentWork != null &&
            currentWork.workId == workId &&
            currentWork.siteIndex == siteIndex &&
            work.workId == workId &&
            work.siteIndex == siteIndex &&
            identical(current, original) &&
            current != null &&
            current.workId == snapshot.workId &&
            current.episodeNo == snapshot.episodeNo &&
            current.episodeTitle == snapshot.episodeTitle &&
            current.body == snapshot.body &&
            current.downloadedAt == snapshot.downloadedAt &&
            current.publishedAt == snapshot.publishedAt &&
            current.sourceId == snapshot.sourceId &&
            current.sourceUpdatedAt == snapshot.sourceUpdatedAt;
      }

      final incomingTitle = (entry['title'] ?? '').trim();
      final title = incomingTitle.isEmpty
          ? snapshot.episodeTitle
          : incomingTitle;

      final site = Site.values[siteIndex];
      late final Episode fetched;

      if (site == Site.narou) {
        fetched = await narouApiClient.fetchEpisodeBodyForRefresh(
          workId: workId,
          episodeNo: number,
          episodeTitle: title,
          sourceId: sourceId,
        );
      } else {
        if (!RegExp(r'^[0-9]+$').hasMatch(workId) ||
            !RegExp(r'^[0-9]+$').hasMatch(sourceId)) {
          throw ArgumentError('更新対象のカクヨム識別子が不正です。');
        }
        fetched = await kakuyomuScraper.fetchEpisodeBody(
          workId: workId,
          episodeId: sourceId,
          episodeNo: number,
          episodeTitle: title,
        );
      }

      if (fetched.workId.toLowerCase() != workId.toLowerCase() ||
          fetched.episodeNo != number ||
          NovelBodyCodec.payloadOf(fetched.body).trim().isEmpty) {
        throw StateError('取得した更新用本文の作品・話番号・内容が不正です。');
      }

      if (!stillCurrent()) {
        return false;
      }

      final preparedBody = await illustrationStorageService
          .prepareRefreshedBody(
            siteKey: siteKey,
            workId: workId,
            episodeNo: number,
            body: fetched.body,
          );

      if (NovelBodyCodec.payloadOf(preparedBody).trim().isEmpty) {
        throw StateError('挿絵準備後の更新用本文が空です。');
      }

      // 取得・挿絵準備の間に削除・変更された本文を復活・上書きしません。
      if (!stillCurrent()) {
        return false;
      }

      final publishedAt = (entry['publishedAt'] ?? '').trim();
      final replacement = Download(
        workId: workId,
        episodeNo: number,
        episodeTitle: title,
        body: preparedBody,
        downloadedAt: DateTime.now(),
        publishedAt: publishedAt.isEmpty ? snapshot.publishedAt : publishedAt,
        sourceId: sourceId,
        sourceUpdatedAt: (entry['sourceUpdatedAt'] ?? '').trim(),
      );

      await _downloadBox.put(key, replacement);
      return true;
    } finally {
      _refreshingDownloadKeys.remove(key);
    }
  }

  /// 保存済み本文だけを最新目次と照合し、順番に更新します。
  ///
  /// 新着話のダウンロード・作品情報更新・既読変更は行いません。
  /// 目次取得や計画作成の失敗は例外、個別更新の失敗は結果へ集計します。
  Future<DownloadRefreshBatchResult> refreshDownloadedWork({
    required Work work,
    bool forceRefresh = false,
    DownloadRefreshCancellation? cancellation,
    void Function(int completed, int total)? onProgress,
  }) async {
    final workId = work.workId;
    final siteIndex = work.siteIndex;
    _siteKeyForWork(work);

    if (workId.trim().isEmpty) {
      throw ArgumentError('作品IDが空です。');
    }
    if (!_refreshingWorkIds.add(workId)) {
      throw StateError('この作品の更新処理はすでに実行中です。');
    }

    try {
      final registeredWork = _workBox.get(workId);
      if (registeredWork == null || registeredWork.siteIndex != siteIndex) {
        throw StateError('更新対象の作品が登録されていません。');
      }

      bool sameWork() {
        final current = _workBox.get(workId);
        return identical(current, registeredWork) &&
            current != null &&
            current.workId == workId &&
            current.siteIndex == siteIndex &&
            work.workId == workId &&
            work.siteIndex == siteIndex;
      }

      if (!_downloadBox.values.any((item) => item.workId == workId)) {
        return DownloadRefreshBatchResult([]);
      }

      // 開始前キャンセルでは目次通信も行いません。
      final latest = (cancellation?.isRequested ?? false)
          ? <Map<String, String>>[]
          : await fetchEpisodeList(work);

      if (!sameWork()) {
        throw StateError('目次取得中に作品が削除または変更されました。');
      }

      // 計画作成時点の参照と値を、別々に保持します。
      final originals = _downloadBox.values
          .where((item) => item.workId == workId)
          .toList();

      final snapshots = originals.map((item) {
        return Download(
          workId: item.workId,
          episodeNo: item.episodeNo,
          episodeTitle: item.episodeTitle,
          body: item.body,
          downloadedAt: item.downloadedAt,
          publishedAt: item.publishedAt,
          sourceId: item.sourceId,
          sourceUpdatedAt: item.sourceUpdatedAt,
        );
      }).toList();

      // 不正・重複目次があれば、最初の本文取得前に停止します。
      final plan = DownloadRefreshPlanner.build(
        workId: workId,
        downloads: snapshots,
        episodeList: latest,
        forceRefresh: forceRefresh,
      );

      final originalsByNumber = {
        for (final item in originals) item.episodeNo: item,
      };
      final snapshotsByNumber = {
        for (final item in snapshots) item.episodeNo: item,
      };

      bool sameDownload(int number) {
        final current = _downloadBox.get(_key(workId, number));
        final original = originalsByNumber[number];
        final snapshot = snapshotsByNumber[number];

        return sameWork() &&
            current != null &&
            snapshot != null &&
            identical(current, original) &&
            current.workId == snapshot.workId &&
            current.episodeNo == snapshot.episodeNo &&
            current.episodeTitle == snapshot.episodeTitle &&
            current.body == snapshot.body &&
            current.downloadedAt == snapshot.downloadedAt &&
            current.publishedAt == snapshot.publishedAt &&
            current.sourceId == snapshot.sourceId &&
            current.sourceUpdatedAt == snapshot.sourceUpdatedAt;
      }

      return await _downloadRefreshRunner.run(
        workId: workId,
        plan: plan,
        cancellation: cancellation,
        onProgress: onProgress,
        refreshUnchangedItem: (item) async {
          if (!sameDownload(item.episodeNo)) {
            return DownloadRefreshOutcome.skipped;
          }

          final original = originalsByNumber[item.episodeNo]!;
          final snapshot = snapshotsByNumber[item.episodeNo]!;
          final latestId = (item.latestEntry['sourceId'] ?? '').trim();
          final latestStamp = (item.latestEntry['sourceUpdatedAt'] ?? '')
              .trim();

          if (latestId.isEmpty ||
              latestId != snapshot.sourceId.trim() ||
              latestStamp.isEmpty ||
              latestStamp != snapshot.sourceUpdatedAt.trim()) {
            return DownloadRefreshOutcome.skipped;
          }

          final title = (item.latestEntry['title'] ?? '').trim();
          if (title.isEmpty || title == original.episodeTitle) {
            return DownloadRefreshOutcome.unchanged;
          }

          // 本文と本文の版情報は変えず、タイトルだけを差し替えます。
          final replacement = Download(
            workId: snapshot.workId,
            episodeNo: snapshot.episodeNo,
            episodeTitle: title,
            body: snapshot.body,
            downloadedAt: snapshot.downloadedAt,
            publishedAt: snapshot.publishedAt,
            sourceId: snapshot.sourceId,
            sourceUpdatedAt: snapshot.sourceUpdatedAt,
          );

          await _downloadBox.put(_key(workId, item.episodeNo), replacement);
          return DownloadRefreshOutcome.titleUpdated;
        },
        refreshItem: (item) async {
          // 前の話を処理している間に変わったデータも上書きしません。
          if (!sameDownload(item.episodeNo)) {
            return false;
          }
          return refreshDownloadedEpisode(
            work: work,
            episodeEntry: item.latestEntry,
          );
        },
      );
    } finally {
      _refreshingWorkIds.remove(workId);
    }
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
          sourceId: entry['sourceId'] ?? '',
          sourceUpdatedAt: entry['sourceUpdatedAt'] ?? '',
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
