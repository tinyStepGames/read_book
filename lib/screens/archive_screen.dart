import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/download.dart';
import '../models/site.dart';
import '../models/work.dart';
import '../services/novel_repository.dart';
import '../services/search_request_controller.dart';
import '../utils/no_animation_route.dart';
import 'reader_screen.dart';
import '../services/backup_service.dart';
import '../services/download_manager.dart';

/// 書庫のトップ画面
///
/// 「なろう」「カクヨム」のフォルダーを表示します。
class ArchiveScreen extends StatelessWidget {
  final NovelRepository repository;
  final SearchRequestController searchRequestController;
  final VoidCallback onNavigateToSearch;

  const ArchiveScreen({
    super.key,
    required this.repository,
    required this.searchRequestController,
    required this.onNavigateToSearch,
  });
  Future<void> _createBackup(
    BuildContext context,
    Rect sharePositionOrigin,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('バックアップを作成'),
          content: const Text(
            'ダウンロードした本文、お気に入り、履歴、'
            '既読情報などをZIPファイルへ保存します。\n\n'
            '表示される共有画面から「ファイルに保存」を選択してください。',
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
              child: const Text('作成'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      messenger.showSnackBar(const SnackBar(content: Text('バックアップを作成しています…')));

      await BackupService().createAndShareBackup(
        sharePositionOrigin: sharePositionOrigin,
      );

      if (!context.mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('共有画面から「ファイルに保存」を選択してください。')),
      );
    } catch (error) {
      if (!context.mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('バックアップの作成に失敗しました: $error')),
      );
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('バックアップから復元'),
          content: const Text(
            'バックアップ作成時点のデータへ戻します。\n\n'
            '現在の作品情報、ダウンロード本文、お気に入り、'
            '履歴、既読情報はバックアップ内のデータに置き換わります。\n\n'
            '復元ファイルを選択しますか？',
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
              child: const Text('ファイルを選択'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      final staged = await BackupService().selectAndStageRestoreFile();

      if (!context.mounted || !staged) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('復元の準備ができました'),
            content: const Text(
              'アプリを完全に終了してから、もう一度起動してください。\n\n'
              '次回起動時にバックアップから自動的に復元します。\n\n'
              'iPhoneでは、アプリ切り替え画面でこのアプリを'
              '上へスワイプして終了してください。',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!context.mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text('バックアップを読み込めませんでした: $error')),
      );
    }
  }

  Site? _siteOfWork(Work work) {
    if (work.siteIndex < 0 || work.siteIndex >= Site.values.length) {
      return null;
    }

    return Site.values[work.siteIndex];
  }

  List<Download> _downloadsForSite(Box<Download> box, Site site) {
    return box.values.where((download) {
      final work = repository.getWork(download.workId);

      if (work == null) return false;

      return _siteOfWork(work) == site;
    }).toList();
  }

  int _workCountForSite(Box<Download> box, Site site) {
    return _downloadsForSite(
      box,
      site,
    ).map((download) => download.workId).toSet().length;
  }

  IconData _siteIcon(Site site) {
    switch (site) {
      case Site.narou:
        return Icons.menu_book_outlined;
      case Site.kakuyomu:
        return Icons.auto_stories_outlined;
    }
  }

  Color _siteColor(Site site) {
    switch (site) {
      case Site.narou:
        return Colors.teal;
      case Site.kakuyomu:
        return Colors.blue;
    }
  }

  void _openSiteFolder(BuildContext context, Site site) {
    Navigator.of(context).push<void>(
      noAnimationRoute<void>(
        SiteArchiveScreen(
          repository: repository,
          site: site,
          searchRequestController: searchRequestController,
          onNavigateToSearch: onNavigateToSearch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadBox = Hive.box<Download>('downloads');

    return Scaffold(
      appBar: AppBar(
        title: const Text('書庫'),
        actions: [
          Builder(
            builder: (menuContext) {
              return PopupMenuButton<_ArchiveMenuAction>(
                tooltip: 'バックアップ',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) async {
                  switch (action) {
                    case _ArchiveMenuAction.createBackup:
                      final renderBox =
                          menuContext.findRenderObject() as RenderBox?;

                      final sharePositionOrigin = renderBox == null
                          ? const Rect.fromLTWH(0, 0, 1, 1)
                          : renderBox.localToGlobal(Offset.zero) &
                                renderBox.size;

                      await _createBackup(menuContext, sharePositionOrigin);

                    case _ArchiveMenuAction.restoreBackup:
                      await _restoreBackup(menuContext);
                  }
                },
                itemBuilder: (context) {
                  return const [
                    PopupMenuItem<_ArchiveMenuAction>(
                      value: _ArchiveMenuAction.createBackup,
                      child: ListTile(
                        leading: Icon(Icons.backup_outlined),
                        title: Text('バックアップを作成'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem<_ArchiveMenuAction>(
                      value: _ArchiveMenuAction.restoreBackup,
                      child: ListTile(
                        leading: Icon(Icons.restore_outlined),
                        title: Text('バックアップから復元'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ];
                },
              );
            },
          ),
        ],
      ),

      body: ValueListenableBuilder<Box<Download>>(
        valueListenable: downloadBox.listenable(),
        builder: (context, box, _) {
          final totalDownloads = box.length;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  totalDownloads == 0
                      ? 'ダウンロードした作品はありません'
                      : 'ダウンロード済み: $totalDownloads話',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
              for (final site in Site.values)
                _ArchiveFolderTile(
                  label: site.displayName,
                  icon: _siteIcon(site),
                  color: _siteColor(site),
                  workCount: _workCountForSite(box, site),
                  episodeCount: _downloadsForSite(box, site).length,
                  onTap: () {
                    _openSiteFolder(context, site);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// なろう・カクヨムのフォルダー表示
class _ArchiveFolderTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int workCount;
  final int episodeCount;
  final VoidCallback onTap;

  const _ArchiveFolderTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.workCount,
    required this.episodeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = workCount == 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.folder,
                    size: 44,
                    color: isEmpty ? Colors.grey : color,
                  ),
                  Positioned(
                    bottom: 6,
                    child: Icon(icon, size: 15, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$workCount作品・$episodeCount話',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }
}

/// サイト別の書庫画面
///
/// なろう、またはカクヨムでダウンロードした作品を表示します。
class SiteArchiveScreen extends StatelessWidget {
  final NovelRepository repository;
  final Site site;
  final SearchRequestController searchRequestController;
  final VoidCallback onNavigateToSearch;

  const SiteArchiveScreen({
    super.key,
    required this.repository,
    required this.site,
    required this.searchRequestController,
    required this.onNavigateToSearch,
  });

  List<Work> _downloadedWorks(Box<Download> box) {
    final workIds = box.values.map((download) => download.workId).toSet();

    final works = <Work>[];

    for (final workId in workIds) {
      final work = repository.getWork(workId);

      if (work == null) continue;
      if (work.siteIndex != site.index) continue;

      works.add(work);
    }

    works.sort((a, b) {
      final aLatest = _latestDownloadDate(box, a.workId);
      final bLatest = _latestDownloadDate(box, b.workId);

      return bLatest.compareTo(aLatest);
    });

    return works;
  }

  DateTime _latestDownloadDate(Box<Download> box, String workId) {
    final downloads = box.values
        .where((download) => download.workId == workId)
        .toList();

    if (downloads.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    downloads.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

    return downloads.first.downloadedAt;
  }

  int _downloadCount(Box<Download> box, String workId) {
    return box.values.where((download) => download.workId == workId).length;
  }

  void _openWork(BuildContext context, Work work) {
    Navigator.of(context).push<void>(
      noAnimationRoute<void>(
        DownloadedWorkScreen(repository: repository, work: work),
      ),
    );
  }

  Widget _buildActionLabel(
    IconData icon,
    String label, {
    bool destructive = false,
    bool disabled = false,
  }) {
    Color? color;

    if (disabled) {
      color = CupertinoColors.inactiveGray;
    } else if (destructive) {
      color = CupertinoColors.systemRed;
    }

    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.left,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }

  void _navigateToSearch(BuildContext context, SearchRequest request) {
    searchRequestController.request(request);

    // サイト別書庫画面を閉じてから検索タブへ移動します。
    Navigator.of(context).pop();

    onNavigateToSearch();
  }

  void _searchByTitle(BuildContext context, Work work) {
    final title = work.title.trim();

    if (title.isEmpty) return;

    _navigateToSearch(
      context,
      SearchRequest(keyword: title, siteIndex: work.siteIndex),
    );
  }

  void _searchByTag(BuildContext context, Work work, String tag) {
    final keyword = tag.trim();

    if (keyword.isEmpty) return;

    _navigateToSearch(
      context,
      SearchRequest(
        keyword: keyword,
        keywordOnly: true,
        siteIndex: work.siteIndex,
      ),
    );
  }

  Future<void> _showTagMenu(BuildContext context, Work work) async {
    final tags = work.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();

    if (tags.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('この作品には検索できるタグがありません')));
      return;
    }

    final selectedTag = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) {
        return CupertinoActionSheet(
          title: const Text('検索するタグを選択'),
          message: Text(work.title),
          actions: [
            for (final tag in tags)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(popupContext).pop(tag);
                },
                child: Text(tag),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
            },
            child: const Text('キャンセル'),
          ),
        );
      },
    );

    if (selectedTag == null) return;
    if (!context.mounted) return;

    _searchByTag(context, work, selectedTag);
  }

  Future<void> _deleteWorkDownloads(BuildContext context, Work work) async {
    final box = Hive.box<Download>('downloads');

    final targetEntries = box.toMap().entries.where((entry) {
      return entry.value.workId == work.workId;
    }).toList();

    if (targetEntries.isEmpty) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('削除するダウンロードファイルがありません')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ダウンロードを削除'),
          content: Text(
            '「${work.title}」のダウンロードファイルを'
            'すべて削除しますか？\n\n'
            '${targetEntries.length}話のファイルが削除されます。\n'
            '既読情報と履歴は削除されません。',
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
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    for (final entry in targetEntries) {
      await box.delete(entry.key);
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「${work.title}」のダウンロードファイルを削除しました')),
    );
  }

  Future<void> _showWorkMenu(BuildContext context, Work work) async {
    final hasTags = work.tags.any((tag) => tag.trim().isNotEmpty);

    final action = await showCupertinoModalPopup<_WorkMenuAction>(
      context: context,
      builder: (popupContext) {
        return CupertinoActionSheet(
          title: Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop(_WorkMenuAction.searchByTitle);
              },
              child: _buildActionLabel(CupertinoIcons.search, '作品名で検索'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop(_WorkMenuAction.searchByTag);
              },
              child: _buildActionLabel(
                CupertinoIcons.tag,
                hasTags ? 'タグ検索' : 'タグ検索（タグなし）',
                disabled: !hasTags,
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(popupContext).pop(_WorkMenuAction.deleteDownloads);
              },
              child: _buildActionLabel(
                CupertinoIcons.delete,
                'ダウンロードファイルを削除',
                destructive: true,
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
            },
            child: const Text('キャンセル'),
          ),
        );
      },
    );

    if (action == null) return;
    if (!context.mounted) return;

    switch (action) {
      case _WorkMenuAction.searchByTitle:
        _searchByTitle(context, work);

      case _WorkMenuAction.searchByTag:
        if (!hasTags) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('この作品には検索できるタグがありません')));
          return;
        }

        await _showTagMenu(context, work);

      case _WorkMenuAction.deleteDownloads:
        await _deleteWorkDownloads(context, work);
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Download>('downloads');

    return Scaffold(
      appBar: AppBar(title: Text('${site.displayName}の書庫')),
      body: ValueListenableBuilder<Box<Download>>(
        valueListenable: box.listenable(),
        builder: (context, downloadBox, _) {
          final works = _downloadedWorks(downloadBox);

          if (works.isEmpty) {
            return Center(
              child: Text(
                '${site.displayName}で\n'
                'ダウンロードした作品はありません',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            itemCount: works.length,
            separatorBuilder: (_, __) {
              return const Divider(height: 1);
            },
            itemBuilder: (context, index) {
              final work = works[index];

              final downloadedCount = _downloadCount(downloadBox, work.workId);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _openWork(context, work);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.folder_outlined,
                          size: 34,
                          color: site == Site.narou ? Colors.teal : Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              work.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '作:${work.author}　'
                              'サイト:${site.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              runSpacing: 3,
                              children: [
                                Text(
                                  work.isCompleted ? '完結' : '連載中',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: work.isCompleted
                                        ? Colors.grey
                                        : Colors.teal,
                                  ),
                                ),
                                if (work.genre.isNotEmpty)
                                  Text(
                                    'ジャンル:${work.genre}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                Text(
                                  '$downloadedCount話ダウンロード済み',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: site == Site.narou
                                        ? Colors.teal[300]
                                        : Colors.blue[300],
                                  ),
                                ),
                              ],
                            ),
                            if ((html_parser.parseFragment(work.summary).text ??
                                    '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Text(
                                (html_parser.parseFragment(work.summary).text ??
                                        '')
                                    .trim(),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                            if (work.tags.isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 7,
                                runSpacing: 4,
                                children: work.tags
                                    .where((tag) => tag.trim().isNotEmpty)
                                    .take(8)
                                    .map(
                                      (tag) => Text(
                                        '#$tag',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: site == Site.narou
                                              ? Colors.teal[300]
                                              : Colors.blue[300],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),

                      // 三点リーダー
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _showWorkMenu(context, work);
                        },
                        child: SizedBox(
                          width: 40,
                          height: 44,
                          child: Center(
                            child: Icon(
                              Icons.more_vert,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Icon(
                          Icons.chevron_right,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

enum _ArchiveMenuAction { createBackup, restoreBackup }

enum _WorkMenuAction { searchByTitle, searchByTag, deleteDownloads }

/// ダウンロード済み作品の各話一覧画面
class DownloadedWorkScreen extends StatefulWidget {
  final NovelRepository repository;
  final Work work;

  const DownloadedWorkScreen({
    super.key,
    required this.repository,
    required this.work,
  });

  @override
  State<DownloadedWorkScreen> createState() => _DownloadedWorkScreenState();
}

class _DownloadedWorkScreenState extends State<DownloadedWorkScreen> {
  static const int _episodesPerPage = 100;

  int _currentEpisodePage = 1;

  bool _isFetchingEpisodeList = false;

  int? _onlineEpisodeCount;

  final ScrollController _episodeScrollController = ScrollController();

  NovelRepository get repository => widget.repository;

  Work get work => widget.work;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOnlineEpisodeCount();
    });
  }

  Future<void> _refreshOnlineEpisodeCount() async {
    if (_isFetchingEpisodeList) {
      return;
    }

    setState(() {
      _isFetchingEpisodeList = true;
    });

    try {
      final episodeList = await repository.fetchEpisodeList(work);

      if (!mounted || episodeList.isEmpty) {
        return;
      }

      setState(() {
        _onlineEpisodeCount = episodeList.length;
      });
    } catch (_) {
      // Offline: continue using the saved episode count.
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingEpisodeList = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _episodeScrollController.dispose();
    super.dispose();
  }

  List<Download> _downloads(Box<Download> box) {
    final downloads = box.values
        .where((download) => download.workId == work.workId)
        .toList();

    downloads.sort((a, b) => a.episodeNo.compareTo(b.episodeNo));

    return downloads;
  }

  int _totalEpisodePages(List<Download> downloads) {
    if (downloads.isEmpty) {
      return 1;
    }

    return (downloads.length / _episodesPerPage).ceil();
  }

  List<Download> _visibleDownloads(List<Download> downloads) {
    if (downloads.isEmpty) {
      return const <Download>[];
    }

    final totalPages = _totalEpisodePages(downloads);
    final currentPage = _currentEpisodePage.clamp(1, totalPages);

    final startIndex = (currentPage - 1) * _episodesPerPage;
    final endIndex = (startIndex + _episodesPerPage).clamp(0, downloads.length);

    return downloads.sublist(startIndex, endIndex);
  }

  void _changeEpisodePage(int page, int totalPages) {
    final normalizedPage = page.clamp(1, totalPages);

    if (normalizedPage == _currentEpisodePage) {
      return;
    }

    setState(() {
      _currentEpisodePage = normalizedPage;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_episodeScrollController.hasClients) {
        return;
      }

      _episodeScrollController.jumpTo(0);
    });
  }

  Widget _buildEpisodePaginationBar(
    BuildContext context,
    List<Download> downloads,
  ) {
    final theme = Theme.of(context);
    final totalPages = _totalEpisodePages(downloads);
    final currentPage = _currentEpisodePage.clamp(1, totalPages);

    final startIndex = (currentPage - 1) * _episodesPerPage;
    final endIndex = (startIndex + _episodesPerPage).clamp(0, downloads.length);

    final visibleDownloads = downloads.sublist(startIndex, endIndex);

    final rangeLabel = visibleDownloads.isEmpty
        ? 'ダウンロード済み 0話'
        : '第${visibleDownloads.first.episodeNo}話'
              '～第${visibleDownloads.last.episodeNo}話'
              ' / ダウンロード済み${downloads.length}話';

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rangeLabel, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: currentPage > 1
                          ? () {
                              _changeEpisodePage(currentPage - 1, totalPages);
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
                        final pageStartIndex = index * _episodesPerPage;
                        final pageEndIndex = (pageStartIndex + _episodesPerPage)
                            .clamp(0, downloads.length);

                        final pageDownloads = downloads.sublist(
                          pageStartIndex,
                          pageEndIndex,
                        );

                        final label = pageDownloads.isEmpty
                            ? '$pageページ'
                            : '${pageDownloads.first.episodeNo}'
                                  '～${pageDownloads.last.episodeNo}話';

                        return DropdownMenuItem<int>(
                          value: page,
                          child: Text(
                            label,
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
                                _changeEpisodePage(page, totalPages);
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
                              _changeEpisodePage(currentPage + 1, totalPages);
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

  String _formatPublishedDate(String value) {
    final raw = value.trim();

    if (raw.isEmpty) {
      return '';
    }

    // 2026年7月11日
    final japaneseMatch = RegExp(
      r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日',
    ).firstMatch(raw);

    if (japaneseMatch != null) {
      final year = japaneseMatch.group(1) ?? '';
      final month = (japaneseMatch.group(2) ?? '').padLeft(2, '0');
      final day = (japaneseMatch.group(3) ?? '').padLeft(2, '0');

      return '$year/$month/$day';
    }

    // 2026/07/11、2026-07-11、日時付きISO形式
    final numericMatch = RegExp(
      r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})',
    ).firstMatch(raw);

    if (numericMatch != null) {
      final year = numericMatch.group(1) ?? '';
      final month = (numericMatch.group(2) ?? '').padLeft(2, '0');
      final day = (numericMatch.group(3) ?? '').padLeft(2, '0');

      return '$year/$month/$day';
    }

    return raw.replaceAll(RegExp(r'\s*(?:公開|更新|（改）)\s*$'), '').trim();
  }

  Site _siteOfWork() {
    if (work.siteIndex < 0 || work.siteIndex >= Site.values.length) {
      return Site.narou;
    }

    return Site.values[work.siteIndex];
  }

  Future<void> _openReader(BuildContext context, Download download) async {
    await Navigator.of(context).push<void>(
      noAnimationRoute<void>(
        ReaderScreen(
          repository: repository,
          work: work,
          episodeNo: download.episodeNo,
          episodeTitle: download.episodeTitle.isNotEmpty
              ? download.episodeTitle
              : '第${download.episodeNo}話',
        ),
      ),
    );
  }

  Future<void> _deleteEpisode(BuildContext context, Download download) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ダウンロードを削除'),
          content: Text(
            '第${download.episodeNo}話の'
            'ダウンロードファイルを削除しますか？\n\n'
            '既読情報と履歴は削除されません。',
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
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final box = Hive.box<Download>('downloads');

    final targetEntries = box.toMap().entries.where((entry) {
      final value = entry.value;

      return value.workId == download.workId &&
          value.episodeNo == download.episodeNo;
    }).toList();

    for (final entry in targetEntries) {
      await box.delete(entry.key);
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ダウンロードファイルを削除しました')));
  }

  Future<void> _confirmAndDownloadMissing() async {
    if (_isFetchingEpisodeList) {
      return;
    }

    if (DownloadManager.instance.isDownloading(work.workId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('この作品は現在ダウンロード中です')));
      return;
    }

    setState(() {
      _isFetchingEpisodeList = true;
    });

    try {
      final episodeList = await repository.fetchEpisodeList(work);

      if (!mounted) {
        return;
      }

      if (episodeList.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('作品の目次を取得できませんでした')));
        return;
      }

      final undownloadedEpisodes = episodeList.where((entry) {
        final episodeNo = int.tryParse(entry['episodeNo'] ?? '');

        if (episodeNo == null) {
          return false;
        }

        return !repository.isDownloaded(work, episodeNo);
      }).toList();

      if (undownloadedEpisodes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('すべての話がダウンロード済みです')));
        return;
      }

      final downloadedCount = episodeList.length - undownloadedEpisodes.length;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('不足分をダウンロード'),
            content: Text(
              '全${episodeList.length}話のうち、'
              '$downloadedCount話がダウンロード済みです。\n\n'
              '未ダウンロードの${undownloadedEpisodes.length}話を'
              'ダウンロードしますか？',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('キャンセル'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                icon: const Icon(Icons.download),
                label: const Text('ダウンロード'),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) {
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
          SnackBar(
            content: Text(
              '未ダウンロードの${undownloadedEpisodes.length}話の'
              'ダウンロードを開始しました。'
              '他の画面に移動しても続行されます。',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ダウンロードを開始できませんでした。'
              'すでに実行中か、すべてダウンロード済みです。',
            ),
          ),
        );
      }
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
          _isFetchingEpisodeList = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Download>('downloads');
    final site = _siteOfWork();

    return Scaffold(
      appBar: AppBar(
        title: Text(work.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '不足分をダウンロード',
            onPressed: _isFetchingEpisodeList
                ? null
                : _confirmAndDownloadMissing,
            icon: _isFetchingEpisodeList
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
          ),
        ],
      ),

      body: ValueListenableBuilder<Box<Download>>(
        valueListenable: box.listenable(),
        builder: (context, downloadBox, _) {
          final downloads = _downloads(downloadBox);
          final visibleDownloads = _visibleDownloads(downloads);

          if (downloads.isEmpty) {
            return const Center(child: Text('ダウンロードした話はありません'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          site == Site.narou
                              ? Icons.menu_book_outlined
                              : Icons.auto_stories_outlined,
                          size: 18,
                          color: site == Site.narou ? Colors.teal : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '作:${work.author}　'
                            'サイト:${site.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        Text(
                          '${downloads.length}話',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: work.isCompleted ? Colors.grey : Colors.teal,
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
                        if (work.genre.isNotEmpty)
                          Text(
                            'ジャンル:${work.genre}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        Text(
                          '全${_onlineEpisodeCount ?? work.totalEpisodeCount}話',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    if ((html_parser.parseFragment(work.summary).text ?? '')
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        (html_parser.parseFragment(work.summary).text ?? '')
                            .trim(),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Theme.of(context).textTheme.bodyMedium?.color
                              ?.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                    if (work.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 5,
                        children: work.tags
                            .where((tag) => tag.trim().isNotEmpty)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: site == Site.narou
                                      ? Colors.teal.withValues(alpha: 0.12)
                                      : Colors.blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: site == Site.narou
                                        ? Colors.teal[300]
                                        : Colors.blue[300],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Column(
                  children: [
                    _buildEpisodePaginationBar(context, downloads),

                    const Divider(height: 1),

                    Expanded(
                      child: Scrollbar(
                        controller: _episodeScrollController,
                        thumbVisibility: false,
                        trackVisibility: false,
                        interactive: true,
                        thickness: 6,
                        radius: const Radius.circular(8),
                        scrollbarOrientation: ScrollbarOrientation.right,
                        child: ListView.separated(
                          controller: _episodeScrollController,
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: visibleDownloads.length,

                          separatorBuilder: (_, __) {
                            return const Divider(height: 1);
                          },
                          itemBuilder: (context, index) {
                            final download = visibleDownloads[index];

                            final title = download.episodeTitle.isNotEmpty
                                ? download.episodeTitle
                                : '第${download.episodeNo}話';

                            final publishedDate = _formatPublishedDate(
                              download.publishedAt,
                            );

                            final isRead = repository.isEpisodeRead(
                              work.workId,
                              download.episodeNo,
                            );

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                _openReader(context, download);
                              },
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 64,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.download_done,
                                      size: 20,
                                      color: Colors.teal,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '第${download.episodeNo}話',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isRead
                                                  ? Colors.grey
                                                  : null,
                                            ),
                                          ),
                                          if (publishedDate.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '掲載日：$publishedDate',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isRead
                                                    ? Colors.grey
                                                    : Theme.of(context)
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
                                    if (isRead)
                                      const Icon(
                                        Icons.check,
                                        size: 19,
                                        color: Colors.grey,
                                      ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        _deleteEpisode(context, download);
                                      },
                                      child: const SizedBox(
                                        width: 40,
                                        height: 44,
                                        child: Center(
                                          child: Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
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
