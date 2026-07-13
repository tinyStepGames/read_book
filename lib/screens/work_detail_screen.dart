import 'package:flutter/material.dart';

import '../models/work.dart';
import '../services/download_manager.dart';
import '../services/novel_repository.dart';
import '../utils/no_animation_route.dart';
import 'reader_screen.dart';

class WorkDetailScreen extends StatefulWidget {
  final NovelRepository repository;
  final Work work;

  const WorkDetailScreen({
    super.key,
    required this.repository,
    required this.work,
  });

  @override
  State<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends State<WorkDetailScreen> {
  /// 目次1ページあたりに表示する話数です。
  static const int _episodesPerPage = 100;

  List<Map<String, String>> _episodes = [];

  bool _isLoading = true;

  /// 作品情報・あらすじを表示しているかどうかです。
  bool _showWorkInformation = true;

  /// 現在表示している目次ページです。
  int _currentEpisodePage = 1;

  /// 目次一覧とスクロールバーで共用するControllerです。
  final ScrollController _episodeScrollController = ScrollController();

  /// あらすじとスクロールバーで共用するControllerです。
  final ScrollController _summaryScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _episodeScrollController.addListener(_handleEpisodeScroll);

    _loadEpisodes();
  }

  @override
  void dispose() {
    _episodeScrollController.removeListener(_handleEpisodeScroll);

    _summaryScrollController.dispose();
    _episodeScrollController.dispose();

    super.dispose();
  }

  /// 目次を下へスクロールしたときに、
  /// 作品情報とあらすじを自動的に閉じます。
  void _handleEpisodeScroll() {
    if (!_episodeScrollController.hasClients) {
      return;
    }

    if (!_showWorkInformation) {
      return;
    }

    if (_episodeScrollController.offset > 8) {
      setState(() {
        _showWorkInformation = false;
      });
    }
  }

  /// AppBarのボタンから作品情報の表示を切り替えます。
  void _toggleWorkInformation() {
    setState(() {
      _showWorkInformation = !_showWorkInformation;
    });

    if (_showWorkInformation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_episodeScrollController.hasClients) {
          return;
        }

        _episodeScrollController.jumpTo(0);
      });
    }
  }

  /// エピソードの掲載日を画面表示用に整形します。
  ///
  /// なろう・カクヨムで使用される可能性のある
  /// 複数のキーに対応します。
  String _formatPublishedDate(Map<String, String> entry) {
    final raw =
        (entry['publishedAt'] ??
                entry['published'] ??
                entry['update'] ??
                entry['updatedAt'] ??
                '')
            .trim();

    if (raw.isEmpty) {
      return '';
    }

    // 2026/07/11、2026-07-11、2026/07/11 12:00に対応
    final numericMatch = RegExp(
      r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})',
    ).firstMatch(raw);

    if (numericMatch != null) {
      final year = numericMatch.group(1) ?? '';
      final month = (numericMatch.group(2) ?? '').padLeft(2, '0');
      final day = (numericMatch.group(3) ?? '').padLeft(2, '0');

      return '$year/$month/$day';
    }

    // 2026年7月11日に対応
    final japaneseMatch = RegExp(
      r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日',
    ).firstMatch(raw);

    if (japaneseMatch != null) {
      final year = japaneseMatch.group(1) ?? '';
      final month = (japaneseMatch.group(2) ?? '').padLeft(2, '0');
      final day = (japaneseMatch.group(3) ?? '').padLeft(2, '0');

      return '$year/$month/$day';
    }

    final parsed = DateTime.tryParse(raw);

    if (parsed != null) {
      final year = parsed.year.toString().padLeft(4, '0');
      final month = parsed.month.toString().padLeft(2, '0');
      final day = parsed.day.toString().padLeft(2, '0');

      return '$year/$month/$day';
    }

    return raw
        .replaceAll(RegExp(r'\s*（改）\s*$'), '')
        .replaceAll(RegExp(r'\s*公開\s*$'), '')
        .trim();
  }

  /// 目次の総ページ数です。
  int get _totalEpisodePages {
    if (_episodes.isEmpty) {
      return 1;
    }

    return (_episodes.length / _episodesPerPage).ceil();
  }

  /// 現在のページに表示するエピソード一覧です。
  List<Map<String, String>> get _visibleEpisodes {
    if (_episodes.isEmpty) {
      return const <Map<String, String>>[];
    }

    final normalizedPage = _currentEpisodePage.clamp(1, _totalEpisodePages);

    final startIndex = (normalizedPage - 1) * _episodesPerPage;

    final endIndex = (startIndex + _episodesPerPage).clamp(0, _episodes.length);

    return _episodes.sublist(startIndex, endIndex);
  }

  /// 指定された目次ページへ移動します。
  void _changeEpisodePage(int page) {
    final normalizedPage = page.clamp(1, _totalEpisodePages);

    if (normalizedPage == _currentEpisodePage) {
      return;
    }

    setState(() {
      _currentEpisodePage = normalizedPage;
    });

    // ページ切り替え後、目次を先頭まで戻します。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_episodeScrollController.hasClients) {
        return;
      }

      _episodeScrollController.jumpTo(0);
    });
  }

  /// 目次のページ選択バーを作成します。
  Widget _buildEpisodePaginationBar(BuildContext context) {
    final theme = Theme.of(context);
    final totalPages = _totalEpisodePages;

    final currentPage = _currentEpisodePage.clamp(1, totalPages);

    final startEpisode = _episodes.isEmpty
        ? 0
        : (currentPage - 1) * _episodesPerPage + 1;

    final endEpisode = _episodes.isEmpty
        ? 0
        : (startEpisode + _episodesPerPage - 1).clamp(0, _episodes.length);

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$startEpisode～$endEpisode話 / '
                '全${_episodes.length}話',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: currentPage > 1
                          ? () {
                              _changeEpisodePage(currentPage - 1);
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left, size: 20),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('前へ', maxLines: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey<int>(currentPage),
                      initialValue: currentPage,
                      isExpanded: true,
                      menuMaxHeight: 360,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: List<DropdownMenuItem<int>>.generate(totalPages, (
                        index,
                      ) {
                        final page = index + 1;

                        return DropdownMenuItem<int>(
                          value: page,
                          child: Text(
                            '$pageページ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                      selectedItemBuilder: (context) {
                        return List<Widget>.generate(totalPages, (index) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${index + 1} / $totalPages',
                                maxLines: 1,
                              ),
                            ),
                          );
                        });
                      },
                      onChanged: totalPages > 1
                          ? (page) {
                              if (page != null) {
                                _changeEpisodePage(page);
                              }
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: currentPage < totalPages
                          ? () {
                              _changeEpisodePage(currentPage + 1);
                            }
                          : null,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('次へ', maxLines: 1),
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadEpisodes() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 詳細取得に失敗しても、目次取得は続行します。
      try {
        await widget.repository.refreshWorkDetails(widget.work);
      } catch (_) {
        // 完全なあらすじの取得失敗は無視します。
        // 検索結果のあらすじをそのまま表示します。
      }

      final episodes = await widget.repository.fetchEpisodeList(widget.work);

      await widget.repository.updateDownloadPublishedDates(
        work: widget.work,
        episodeList: episodes,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _episodes = episodes;

        final totalPages = episodes.isEmpty
            ? 1
            : (episodes.length / _episodesPerPage).ceil();

        _currentEpisodePage = _currentEpisodePage.clamp(1, totalPages);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('目次の取得に失敗しました: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmAndBulkDownload() async {
    final undownloaded = _episodes.where((entry) {
      final episodeNo = int.tryParse(entry['episodeNo'] ?? '') ?? 0;

      return !widget.repository.isDownloaded(widget.work, episodeNo);
    }).length;

    if (undownloaded == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('すべての話がダウンロード済みです')));
      return;
    }

    // 1話あたり約1秒として表示します。
    final approximateSeconds = undownloaded;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('全話ダウンロード'),
          content: Text(
            '未ダウンロードの$undownloaded話をダウンロードします。\n'
            '目安時間: 約$approximateSeconds秒〜',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('ダウンロード'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await DownloadManager.instance.enqueueBulk(
      work: widget.work,
      episodeList: _episodes,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ダウンロードを開始しました。'
          '他の画面に移動しても続行されます。',
        ),
      ),
    );
  }

  Future<void> _downloadSingle(
    int episodeNo,
    String title,
    String publishedAt,
  ) async {
    await DownloadManager.instance.downloadSingle(
      work: widget.work,
      episodeNo: episodeNo,
      episodeTitle: title,
      publishedAt: publishedAt,
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _openReader(int episodeNo, String title) async {
    await Navigator.of(context).push<void>(
      noAnimationRoute<void>(
        ReaderScreen(
          repository: widget.repository,
          work: widget.work,
          episodeNo: episodeNo,
          episodeTitle: title,
        ),
      ),
    );

    // 本文から目次へ戻ったときに既読表示などを更新します。
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _continueReading() {
    final nextEpisodeNo = widget.repository.firstUnreadEpisodeNo(
      widget.work.workId,
      _episodes,
    );

    if (nextEpisodeNo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('すべての話を読み終えています')));
      return;
    }

    final entry = _episodes.firstWhere((episode) {
      final episodeNo = int.tryParse(episode['episodeNo'] ?? '') ?? -1;

      return episodeNo == nextEpisodeNo;
    }, orElse: () => <String, String>{});

    final title = entry['title'] ?? '第$nextEpisodeNo話';

    _openReader(nextEpisodeNo, title);
  }

  /// 作品タイトルが省略されないように、
  /// 必要なAppBarの高さを計算します。
  double _calculateAppBarHeight(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;

    // 戻るボタン、右側のボタン、左右の余白を除いた幅です。
    final calculatedWidth = screenWidth - 56 - 112 - 32;

    final availableTitleWidth = calculatedWidth < 100 ? 100.0 : calculatedWidth;

    final titleStyle =
        Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 20);

    final textPainter = TextPainter(
      text: TextSpan(text: widget.work.title, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: mediaQuery.textScaler,
    )..layout(maxWidth: availableTitleWidth);

    final requiredHeight = textPainter.height + 24;

    return requiredHeight < kToolbarHeight ? kToolbarHeight : requiredHeight;
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        // 作品情報表示中は、タイトル全文に必要な高さにします。
        // 閉じているときは通常のAppBarの高さにします。
        toolbarHeight: _showWorkInformation
            ? _calculateAppBarHeight(context)
            : kToolbarHeight,
        title: Text(
          work.title,
          softWrap: true,
          maxLines: _showWorkInformation ? 1000 : 1,
          overflow: _showWorkInformation
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
        ),
        actions: [
          // 作品情報・あらすじの表示切り替え
          IconButton(
            icon: Icon(
              _showWorkInformation ? Icons.unfold_less : Icons.unfold_more,
            ),
            tooltip: _showWorkInformation ? '作品情報を閉じる' : '作品情報を表示',
            onPressed: _toggleWorkInformation,
          ),

          // 全話ダウンロード
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '全話ダウンロード',
            onPressed: _isLoading ? null : _confirmAndBulkDownload,
          ),
        ],
      ),
      body: StreamBuilder<dynamic>(
        stream: DownloadManager.instance.progressStream,
        builder: (context, snapshot) {
          final progress = DownloadManager.instance.progressOf(work.workId);

          return Column(
            children: [
              if (progress.isRunning)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: progress.total == 0
                          ? null
                          : progress.done / progress.total,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'ダウンロード中: '
                        '${progress.done}/${progress.total}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),

              // 作品情報
              if (_showWorkInformation)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: work.isCompleted
                                  ? Colors.grey
                                  : Colors.teal,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              work.isCompleted ? '完結' : '連載中',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '全${work.totalEpisodeCount}話',
                              softWrap: true,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '作:${work.author}　'
                        'ジャンル:${work.genre}',
                        softWrap: true,
                        maxLines: 1000,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '最終更新:${work.lastUpdatedAt}',
                        softWrap: true,
                        maxLines: 1000,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),

                      // あらすじ
                      if (work.summary.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Scrollbar(
                            controller: _summaryScrollController,
                            thumbVisibility: false,
                            trackVisibility: false,
                            interactive: true,
                            thickness: 6,
                            radius: const Radius.circular(8),
                            scrollbarOrientation: ScrollbarOrientation.right,
                            child: SingleChildScrollView(
                              controller: _summaryScrollController,
                              primary: false,
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                work.summary.trim(),
                                softWrap: true,
                                maxLines: 10000,
                                overflow: TextOverflow.visible,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // タグ
                      if (work.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: work.tags
                              .where((tag) => tag.trim().isNotEmpty)
                              .map(
                                (tag) => Text(
                                  tag,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _continueReading,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('続きから読む'),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_showWorkInformation) const Divider(height: 1),

              // 目次
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _episodes.isEmpty
                    ? const Center(child: Text('目次がありません'))
                    : Column(
                        children: [
                          // 100話ごとのページ選択
                          _buildEpisodePaginationBar(context),

                          const Divider(height: 1),

                          // 選択中のページに含まれる目次
                          Expanded(
                            child: Scrollbar(
                              controller: _episodeScrollController,

                              // スクロール中だけ表示し、停止後は消します。
                              thumbVisibility: false,
                              trackVisibility: false,

                              interactive: true,
                              thickness: 6,
                              radius: const Radius.circular(8),
                              scrollbarOrientation: ScrollbarOrientation.right,
                              child: ListView.separated(
                                controller: _episodeScrollController,
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: _visibleEpisodes.length,
                                separatorBuilder: (_, __) {
                                  return const Divider(height: 1);
                                },
                                itemBuilder: (context, index) {
                                  final entry = _visibleEpisodes[index];

                                  final globalIndex =
                                      (_currentEpisodePage - 1) *
                                          _episodesPerPage +
                                      index;

                                  final episodeNo =
                                      int.tryParse(entry['episodeNo'] ?? '') ??
                                      globalIndex + 1;

                                  final title =
                                      entry['title'] ?? '第$episodeNo話';

                                  final publishedDate = _formatPublishedDate(
                                    entry,
                                  );

                                  final downloaded = widget.repository
                                      .isDownloaded(work, episodeNo);

                                  final isRead = widget.repository
                                      .isEpisodeRead(work.workId, episodeNo);

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      _openReader(episodeNo, title);
                                    },
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 68,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 9,
                                      ),
                                      child: Row(
                                        children: [
                                          // 各話のダウンロードボタン
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: downloaded
                                                ? null
                                                : () {
                                                    _downloadSingle(
                                                      episodeNo,
                                                      title,
                                                      entry['publishedAt'] ??
                                                          entry['update'] ??
                                                          entry['published'] ??
                                                          entry['updatedAt'] ??
                                                          '',
                                                    );
                                                  },
                                            child: SizedBox(
                                              width: 40,
                                              height: 48,
                                              child: Center(
                                                child: Icon(
                                                  downloaded
                                                      ? Icons.download_done
                                                      : Icons.download_outlined,
                                                  color: downloaded
                                                      ? Colors.teal
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ),

                                          const SizedBox(width: 8),

                                          // タイトルと掲載日
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  softWrap: true,
                                                  maxLines: 1000,
                                                  overflow:
                                                      TextOverflow.visible,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.4,
                                                    color: isRead
                                                        ? Colors.grey
                                                        : null,
                                                  ),
                                                ),
                                                if (publishedDate
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '掲載日：$publishedDate',
                                                    softWrap: true,
                                                    maxLines: 1000,
                                                    overflow:
                                                        TextOverflow.visible,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isRead
                                                          ? Colors.grey
                                                          : theme
                                                                .textTheme
                                                                .bodySmall
                                                                ?.color
                                                                ?.withValues(
                                                                  alpha: 0.65,
                                                                ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),

                                          // 既読チェック
                                          if (isRead) ...[
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.check,
                                              color: Colors.grey,
                                              size: 20,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
