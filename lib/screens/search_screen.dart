import 'package:flutter/material.dart';

import '../models/favorite_color.dart';
import '../models/site.dart';
import '../services/download_manager.dart';
import '../services/kakuyomu_scraper.dart';
import '../services/narou_api_client.dart';
import '../services/novel_repository.dart';
import '../services/search_request_controller.dart';
import '../utils/no_animation_route.dart';
import '../widgets/expandable_work_card.dart';
import 'work_detail_screen.dart';

/// 1回の検索条件を表します。
///
/// 戻る操作で以前の検索条件へ戻るために使用します。
class _SearchQuery {
  final String word;
  final bool authorNameOnly;
  final bool keywordOnly;
  final Site site;

  const _SearchQuery({
    required this.word,
    required this.authorNameOnly,
    required this.keywordOnly,
    required this.site,
  });
}

class SearchScreen extends StatefulWidget {
  final NovelRepository repository;
  final SearchRequestController searchRequestController;

  const SearchScreen({
    super.key,
    required this.repository,
    required this.searchRequestController,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// 検索結果画面下部のページ移動バーです。
///
/// 「前のページ」「ページ選択」「次のページ」のみ表示します。
class _SearchPaginationBar extends StatelessWidget {
  const _SearchPaginationBar({
    required this.currentPage,
    required this.maxPage,
    required this.isLoading,
    required this.onPageChanged,
  });

  final int currentPage;
  final int maxPage;
  final bool isLoading;
  final ValueChanged<int> onPageChanged;

  void _moveToPage(int page) {
    if (isLoading) {
      return;
    }

    final normalizedPage = page.clamp(1, maxPage).toInt();

    if (normalizedPage == currentPage) {
      return;
    }

    onPageChanged(normalizedPage);
  }

  @override
  Widget build(BuildContext context) {
    final canMovePrevious = !isLoading && currentPage > 1;
    final canMoveNext = !isLoading && currentPage < maxPage;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: canMovePrevious
                    ? () => _moveToPage(currentPage - 1)
                    : null,
                child: const Text('前のページ'),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  // ページ変更時に選択表示を確実に更新します。
                  key: ValueKey<int>(currentPage),
                  initialValue: currentPage,
                  isExpanded: true,
                  menuMaxHeight: 360,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  items: List<DropdownMenuItem<int>>.generate(maxPage, (index) {
                    final page = index + 1;

                    return DropdownMenuItem<int>(
                      value: page,
                      child: Text(
                        '$page ページ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                  onChanged: isLoading
                      ? null
                      : (page) {
                          if (page != null) {
                            _moveToPage(page);
                          }
                        },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: canMoveNext
                    ? () => _moveToPage(currentPage + 1)
                    : null,
                child: const Text('次のページ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchScreenState extends State<SearchScreen> {
  final NarouApiClient _narouApiClient = NarouApiClient();
  final KakuyomuScraper _kakuyomuScraper = KakuyomuScraper();

  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<NarouSearchResult> _results = <NarouSearchResult>[];

  bool _isLoading = false;
  int _page = 1;

  /// なろうAPIの取得開始位置stの最大値です。
  static const int _narouMaxStart = 2000;

  /// なろうで1ページに取得する件数です。
  static const int _narouPageSize = 50;

  /// カクヨムで選択できる最大ページです。
  static const int _kakuyomuMaxPage = 50;

  bool _authorNameOnly = false;
  bool _keywordOnly = false;

  Site _selectedSite = Site.narou;

  final List<_SearchQuery> _history = <_SearchQuery>[];

  /// 現在選択しているサイトの最大ページを返します。
  int get _currentMaxPage {
    return _maxPageForSite(_selectedSite);
  }

  /// 指定したサイトの最大ページを返します。
  int _maxPageForSite(Site site) {
    if (site == Site.narou) {
      // 1ページ50件で、stの最大値が2000の場合は40ページです。
      return ((_narouMaxStart - 1) ~/ _narouPageSize) + 1;
    }

    return _kakuyomuMaxPage;
  }

  /// ダウンロード状況が変化したときに、検索カードを即時更新します。
  late final _downloadSubscription = DownloadManager.instance.progressStream
      .listen((_) {
        if (!mounted) {
          return;
        }

        setState(() {});
      });

  @override
  void initState() {
    super.initState();

    _keywordController.addListener(_onKeywordChanged);

    widget.searchRequestController.addListener(_onExternalSearchRequest);

    // lateフィールドへアクセスしてリスナーを開始します。
    _downloadSubscription;

    _search(page: 1, pushHistory: false);
  }

  @override
  void dispose() {
    _downloadSubscription.cancel();

    widget.searchRequestController.removeListener(_onExternalSearchRequest);

    _keywordController.removeListener(_onKeywordChanged);

    _keywordController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  void _onKeywordChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  /// お気に入り画面・履歴画面などから送られた検索要求を処理します。
  void _onExternalSearchRequest() {
    final request = widget.searchRequestController.value;

    if (request == null) {
      return;
    }

    _keywordController.text = request.keyword;
    _authorNameOnly = request.authorNameOnly;
    _keywordOnly = request.keywordOnly;

    if (request.siteIndex >= 0 && request.siteIndex < Site.values.length) {
      _selectedSite = Site.values[request.siteIndex];
    } else {
      _selectedSite = Site.narou;
    }

    _history.clear();

    _search(page: 1, pushHistory: false);

    widget.searchRequestController.consume();
  }

  /// 指定ページの検索結果を取得します。
  Future<void> _search({required int page, bool pushHistory = true}) async {
    if (_isLoading) {
      return;
    }

    // 先に検索対象サイトを確定させます。
    final searchSite = _selectedSite;
    final searchWord = _keywordController.text;

    final maxPage = _maxPageForSite(searchSite);
    final normalizedPage = page.clamp(1, maxPage).toInt();

    if (pushHistory) {
      _history.add(
        _SearchQuery(
          word: searchWord,
          authorNameOnly: _authorNameOnly,
          keywordOnly: _keywordOnly,
          site: searchSite,
        ),
      );
    }

    setState(() {
      _isLoading = true;
    });

    try {
      late final List<NarouSearchResult> results;

      if (searchSite == Site.narou) {
        // なろうAPIはページ番号ではなく、
        // 取得開始位置を指定します。
        //
        // 1ページ目  = 1
        // 2ページ目  = 51
        // 40ページ目 = 1951
        final start = ((normalizedPage - 1) * _narouPageSize) + 1;

        results = await _narouApiClient.search(
          word: searchWord,
          order: 'new',
          limit: _narouPageSize,
          start: start,
          authorNameOnly: _authorNameOnly,
          keywordOnly: _keywordOnly,
        );
      } else {
        // カクヨムはページ番号をそのまま渡します。
        results = await _kakuyomuScraper.search(
          word: searchWord,
          page: normalizedPage,
          authorNameOnly: _authorNameOnly,
          keywordOnly: _keywordOnly,
        );
      }

      if (!mounted) {
        return;
      }

      // 検索中にサイトが切り替わっていた場合は、
      // 古いサイトの結果を画面へ反映しません。
      if (searchSite != _selectedSite) {
        return;
      }

      setState(() {
        _results = results;
        _page = normalizedPage;
      });

      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      final errorText = error.toString();

      final isNotFoundError =
          errorText.contains('status code of 404') ||
          errorText.contains('status code 404') ||
          errorText.contains('statusCode: 404');

      final message = isNotFoundError
          ? '${searchSite.displayName}では、このページを取得できません'
          : '${searchSite.displayName}の検索に失敗しました';

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ページ移動バーから呼び出されます。
  void _moveToPage(int page) {
    if (_isLoading) {
      return;
    }

    final normalizedPage = page.clamp(1, _currentMaxPage).toInt();

    if (normalizedPage == _page) {
      return;
    }

    _search(page: normalizedPage, pushHistory: false);
  }

  void _manualSearch() {
    if (_isLoading) {
      return;
    }

    _authorNameOnly = false;
    _keywordOnly = false;

    _search(page: 1);
  }

  void _goBack() {
    if (_history.length < 2 || _isLoading) {
      return;
    }

    // 現在の検索条件を削除します。
    _history.removeLast();

    // 1つ前の検索条件を取り出します。
    final previous = _history.removeLast();

    _keywordController.text = previous.word;
    _authorNameOnly = previous.authorNameOnly;
    _keywordOnly = previous.keywordOnly;
    _selectedSite = previous.site;

    _search(page: 1);
  }

  void _goHome() {
    if (_isLoading) {
      return;
    }

    _keywordController.clear();

    _authorNameOnly = false;
    _keywordOnly = false;

    _history.clear();

    _search(page: 1, pushHistory: false);
  }

  void _changeSite(Site nextSite) {
    if (nextSite == _selectedSite || _isLoading) {
      return;
    }

    setState(() {
      _selectedSite = nextSite;
      _results = <NarouSearchResult>[];
      _page = 1;
      _history.clear();
      _authorNameOnly = false;
      _keywordOnly = false;
    });

    // カクヨムでキーワードが空の場合は、
    // KakuyomuScraper側で新着小説を取得します。
    _search(page: 1, pushHistory: false);
  }

  bool get _isCurrentSearchFavorited {
    final keyword = _keywordController.text.trim();

    if (keyword.isEmpty) {
      return false;
    }

    return widget.repository.savedSearchFavoriteFor(
          keyword: keyword,
          order: 'new',
          authorNameOnly: _authorNameOnly,
          keywordOnly: _keywordOnly,
          site: _selectedSite,
        ) !=
        null;
  }

  Future<void> _toggleSearchFavorite() async {
    final keyword = _keywordController.text.trim();

    if (keyword.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('検索キーワードを入力してください')));
      return;
    }

    final existing = widget.repository.savedSearchFavoriteFor(
      keyword: keyword,
      order: 'new',
      authorNameOnly: _authorNameOnly,
      keywordOnly: _keywordOnly,
      site: _selectedSite,
    );

    if (existing != null) {
      await widget.repository.removeSearchFavorite(existing.targetKey);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('検索のお気に入りを解除しました')));
    } else {
      await widget.repository.addSearchFavorite(
        keyword: keyword,
        order: 'new',
        authorNameOnly: _authorNameOnly,
        keywordOnly: _keywordOnly,
        site: _selectedSite,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_selectedSite.displayName}の検索を'
            'お気に入りに登録しました',
          ),
        ),
      );
    }

    setState(() {});
  }

  Future<void> _onFavoriteChanged(
    NarouSearchResult result,
    FavoriteColor? color,
  ) async {
    final work = widget.repository.workFromNarouResult(result);

    await widget.repository.setFavoriteColor(work, color);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _searchByAuthor(String author) {
    if (_isLoading) {
      return;
    }

    _keywordController.text = author;
    _authorNameOnly = true;
    _keywordOnly = false;

    _search(page: 1);
  }

  void _searchByTag(String tag) {
    if (_isLoading) {
      return;
    }

    _keywordController.text = tag;
    _authorNameOnly = false;
    _keywordOnly = true;

    _search(page: 1);
  }

  Future<void> _download(NarouSearchResult result) async {
    final work = widget.repository.workFromNarouResult(result);

    await widget.repository.saveWork(work);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('目次を確認しています…')));

    try {
      final episodeList = await widget.repository.fetchEpisodeList(work);

      if (!mounted) {
        return;
      }

      final started = await DownloadManager.instance.enqueueBulk(
        work: work,
        episodeList: episodeList,
      );

      if (!mounted) {
        return;
      }

      if (started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ダウンロードを開始しました。'
              '他の画面に移動しても続行されます。',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('新しくダウンロードする話はありません')));
      }

      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ダウンロードの開始に失敗しました: $error')));
    }
  }

  Future<void> _deleteDownload(NarouSearchResult result) async {
    await widget.repository.deleteAllDownloads(result.ncode);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ダウンロードファイルを削除しました')));

    setState(() {});
  }

  Future<void> _deleteRead(NarouSearchResult result) async {
    await widget.repository.deleteAllReadAndCache(result.ncode);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('既読記録とキャッシュを削除しました')));

    setState(() {});
  }

  Future<void> _openDetail(NarouSearchResult result) async {
    final work = widget.repository.workFromNarouResult(result);

    await widget.repository.saveWork(work);

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      noAnimationRoute<void>(
        WorkDetailScreen(repository: widget.repository, work: work),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Widget _buildSiteSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<Site>(
          segments: const <ButtonSegment<Site>>[
            ButtonSegment<Site>(
              value: Site.narou,
              icon: Icon(Icons.menu_book_outlined),
              label: Text('なろう'),
            ),
            ButtonSegment<Site>(
              value: Site.kakuyomu,
              icon: Icon(Icons.auto_stories_outlined),
              label: Text('カクヨム'),
            ),
          ],
          selected: <Site>{_selectedSite},
          showSelectedIcon: false,
          onSelectionChanged: _isLoading
              ? null
              : (selected) {
                  _changeSite(selected.first);
                },
        ),
      ),
    );
  }

  Widget _buildEmptyMessage() {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_selectedSite == Site.kakuyomu &&
        _keywordController.text.trim().isEmpty) {
      return const Center(
        child: Text('カクヨムの新着小説はありません', textAlign: TextAlign.center),
      );
    }

    return Center(
      child: Text(
        '${_selectedSite.displayName}の検索結果はありません',
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildResultList() {
    if (_results.isEmpty) {
      return _buildEmptyMessage();
    }

    return Scrollbar(
      controller: _scrollController,

      // スクロール中だけ表示し、停止後は自動的に消します。
      thumbVisibility: false,
      trackVisibility: false,

      // 表示中のバーをドラッグして移動できます。
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(8),
      scrollbarOrientation: ScrollbarOrientation.right,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final result = _results[index];

          return ExpandableWorkCard(
            work: result,
            favoriteColor: widget.repository.favoriteColorOf(result.ncode),
            onFavoriteChanged: (color) {
              _onFavoriteChanged(result, color);
            },
            onOpenDetail: () {
              _openDetail(result);
            },
            onDownload: () {
              _download(result);
            },
            onSearchAuthor: _searchByAuthor,
            onSearchTag: _searchByTag,
            hasAnyRead: widget.repository.hasAnyRead(result.ncode),
            hasAnyDownload: widget.repository.hasAnyDownload(result.ncode),
            onDeleteDownload: () {
              _deleteDownload(result);
            },
            onDeleteRead: () {
              _deleteRead(result);
            },
          );
        },
      ),
    );
  }

  Widget _buildPagination() {
    final currentPage = _page.clamp(1, _currentMaxPage).toInt();

    return _SearchPaginationBar(
      currentPage: currentPage,
      maxPage: _currentMaxPage,
      isLoading: _isLoading,
      onPageChanged: _moveToPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: '戻る',
              onPressed: _history.length >= 2 && !_isLoading ? _goBack : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.home, size: 20),
              tooltip: 'ホーム',
              onPressed: _isLoading ? null : _goHome,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(Icons.search, size: 18, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _keywordController,
                        enabled: !_isLoading,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: '検索キーワード　例：異世界 -ハーレム',
                          hintStyle: TextStyle(fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) {
                          _manualSearch();
                        },
                      ),
                    ),
                    if (_keywordController.text.isNotEmpty)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _isLoading
                            ? null
                            : () {
                                _keywordController.clear();
                                _authorNameOnly = false;
                                _keywordOnly = false;

                                // なろうは通常の空検索、
                                // カクヨムは新着小説を取得します。
                                _search(page: 1, pushHistory: false);
                              },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isCurrentSearchFavorited
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: _isCurrentSearchFavorited ? Colors.amber : null,
            ),
            tooltip: '検索をお気に入り登録',
            onPressed: _isLoading ? null : _toggleSearchFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '検索',
            onPressed: _isLoading ? null : _manualSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSiteSelector(),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(child: _buildResultList()),
          _buildPagination(),
        ],
      ),
    );
  }
}
