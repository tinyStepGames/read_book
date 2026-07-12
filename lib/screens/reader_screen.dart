import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/history_entry.dart';
import '../models/site.dart';
import '../models/work.dart';
import '../services/novel_repository.dart';

class ReaderScreen extends StatefulWidget {
  final NovelRepository repository;
  final Work work;
  final int episodeNo;
  final String episodeTitle;

  const ReaderScreen({
    super.key,
    required this.repository,
    required this.work,
    required this.episodeNo,
    required this.episodeTitle,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  String _body = '';
  bool _isLoading = true;
  double _fontSize = 16;

  late int _currentEpisodeNo;
  late String _currentEpisodeTitle;

  List<Map<String, String>> _episodeList = [];

  bool _isLoadingList = true;

  final ScrollController _scrollController = ScrollController();

  bool _toolbarVisible = true;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();

    _currentEpisodeNo = widget.episodeNo;
    _currentEpisodeTitle = widget.episodeTitle;

    _saveHistory();
    _load();
    _loadEpisodeList();

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// スクロール方向に応じてツールバーを表示・非表示にする。
  ///
  /// 上部へ戻る方向：
  ///   スクロール位置が小さくなるのでツールバーを表示。
  ///
  /// 下へ読み進める方向：
  ///   スクロール位置が大きくなるのでツールバーを非表示。
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final currentOffset = _scrollController.offset;
    final difference = currentOffset - _lastOffset;

    // 小さな揺れでは表示状態を変更しない
    if (difference.abs() < 2) {
      return;
    }

    if (difference < 0) {
      // 作品の上部へ戻る方向
      if (!_toolbarVisible && mounted) {
        setState(() {
          _toolbarVisible = true;
        });
      }
    } else {
      // 下へ読み進める方向
      if (_toolbarVisible && mounted) {
        setState(() {
          _toolbarVisible = false;
        });
      }
    }

    _lastOffset = currentOffset;
  }

  /// 本文部分をタップするとツールバーの表示状態を切り替える。
  void _toggleToolbar() {
    if (!mounted) return;

    setState(() {
      _toolbarVisible = !_toolbarVisible;
    });
  }

  Future<void> _load() async {
    final loadingEpisodeNo = _currentEpisodeNo;
    final loadingEpisodeTitle = _currentEpisodeTitle;

    setState(() {
      _isLoading = true;
    });

    try {
      final body = await widget.repository.fetchEpisode(
        work: widget.work,
        episodeNo: loadingEpisodeNo,
        episodeTitle: loadingEpisodeTitle,
      );

      if (!mounted) return;

      // 読み込み中に別の話へ移動していた場合は反映しない
      if (_currentEpisodeNo != loadingEpisodeNo) return;

      setState(() {
        _body = body;
      });
    } catch (e) {
      if (!mounted) return;

      // 現在表示中の話で発生したエラーだけ表示する
      if (_currentEpisodeNo != loadingEpisodeNo) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('本文の取得に失敗しました: $e')));
    } finally {
      if (mounted && _currentEpisodeNo == loadingEpisodeNo) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadEpisodeList() async {
    try {
      final list = await widget.repository.fetchEpisodeList(widget.work);

      if (!mounted) return;

      setState(() {
        _episodeList = list;
        _isLoadingList = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoadingList = false;
      });
    }
  }

  Future<void> _saveHistory() async {
    final episodeNo = _currentEpisodeNo;
    final episodeTitle = _currentEpisodeTitle;

    final box = Hive.box<HistoryEntry>('history');
    final key = '${widget.work.workId}_$episodeNo';
    final existing = box.get(key);

    if (existing != null) {
      existing.lastReadAt = DateTime.now();

      if (episodeTitle.isNotEmpty) {
        existing.episodeTitle = episodeTitle;
      }

      await existing.save();
    } else {
      await box.put(
        key,
        HistoryEntry(
          workId: widget.work.workId,
          episodeNo: episodeNo,
          scrollFraction: 0,
          lastReadAt: DateTime.now(),
          episodeTitle: episodeTitle.isNotEmpty ? episodeTitle : null,
        ),
      );
    }
  }

  int get _currentIndex {
    return _episodeList.indexWhere(
      (episode) =>
          (int.tryParse(episode['episodeNo'] ?? '') ?? -1) == _currentEpisodeNo,
    );
  }

  Map<String, String>? get _previousEpisode {
    final index = _currentIndex;

    if (index <= 0) return null;

    return _episodeList[index - 1];
  }

  Map<String, String>? get _nextEpisode {
    final index = _currentIndex;

    if (index < 0 || index >= _episodeList.length - 1) {
      return null;
    }

    return _episodeList[index + 1];
  }

  Future<void> _goToEpisode(Map<String, String> entry) async {
    final episodeNo =
        int.tryParse(entry['episodeNo'] ?? '') ?? _currentEpisodeNo;
    final episodeTitle = entry['title'] ?? '';

    if (episodeNo == _currentEpisodeNo) return;

    setState(() {
      _currentEpisodeNo = episodeNo;
      _currentEpisodeTitle = episodeTitle;
      _body = '';
      _isLoading = true;
      _toolbarVisible = true;
    });

    // 新しい話へ移動したら画面上部へ戻す
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _lastOffset = 0;

    // 次話・前話も履歴に記録する
    await _saveHistory();

    if (!mounted) return;

    // 本文を取得する。fetchEpisode内で既読情報も保存される
    await _load();
  }

  Future<void> _showFontSizeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.text_decrease),
                      tooltip: '文字を小さく',
                      onPressed: () {
                        setState(() {
                          _fontSize = (_fontSize - 1)
                              .clamp(10.0, 32.0)
                              .toDouble();
                        });

                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_fontSize.round()}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.text_increase),
                      tooltip: '文字を大きく',
                      onPressed: () {
                        setState(() {
                          _fontSize = (_fontSize + 1)
                              .clamp(10.0, 32.0)
                              .toDouble();
                        });

                        setSheetState(() {});
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMoreMenu() async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, 'top');
              },
              child: const Text('最上部へスクロール'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, 'bottom');
              },
              child: const Text('最下部へスクロール'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
            },
            child: const Text('キャンセル'),
          ),
        );
      },
    );

    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    if (selected == 'top') {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

      if (!mounted) return;

      setState(() {
        _toolbarVisible = true;
        _lastOffset = 0;
      });
    } else if (selected == 'bottom') {
      final bottom = _scrollController.position.maxScrollExtent;

      await _scrollController.animateTo(
        bottom,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

      if (!mounted) return;

      setState(() {
        _toolbarVisible = false;
        _lastOffset = bottom;
      });
    }
  }

  Widget _buildNavBox({
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    final enabledBorderColor = theme.colorScheme.onSurface.withValues(
      alpha: 0.45,
    );
    final disabledBorderColor = theme.colorScheme.onSurface.withValues(
      alpha: 0.15,
    );

    final enabledIconColor = theme.colorScheme.onSurface.withValues(
      alpha: 0.75,
    );
    final disabledIconColor = theme.colorScheme.onSurface.withValues(
      alpha: 0.25,
    );

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? enabledBorderColor : disabledBorderColor,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            color: enabled ? enabledIconColor : disabledIconColor,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final work = widget.work;
    final site = Site.values[work.siteIndex];
    final statusLabel = work.isCompleted ? '完結' : '連載';

    final isDownloaded = widget.repository.isDownloaded(
      work,
      _currentEpisodeNo,
    );

    final url = site == Site.narou
        ? 'https://ncode.syosetu.com/'
              '${work.workId.toLowerCase()}/'
              '$_currentEpisodeNo/'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currentEpisodeTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),
          Text(
            '$statusLabel: ${work.title}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text('作: ${work.author}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            'サイト: ${site.displayName}',
            style: const TextStyle(fontSize: 13),
          ),
          if (url != null) ...[
            const SizedBox(height: 6),
            Text(url, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
          if (isDownloaded) ...[
            const SizedBox(height: 6),
            Text(
              '(ダウンロード済み)',
              style: TextStyle(fontSize: 12, color: Colors.teal[300]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReaderContent() {
    return Scrollbar(
      controller: _scrollController,

      // 本文をスクロールしている間だけ表示します。
      thumbVisibility: false,
      trackVisibility: false,

      // バーが表示されている間はドラッグ操作も可能です。
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(8),
      scrollbarOrientation: ScrollbarOrientation.right,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleToolbar,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(right: 10, bottom: 80),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // 前の話へ移動
              _buildNavBox(
                icon: Icons.keyboard_arrow_up,
                enabled: !_isLoadingList && _previousEpisode != null,
                onTap: () {
                  final previousEpisode = _previousEpisode;

                  if (previousEpisode != null) {
                    _goToEpisode(previousEpisode);
                  }
                },
              ),

              const SizedBox(height: 16),

              // 作品・話情報
              _buildHeader(),

              const Divider(height: 1),

              // 本文
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _body,
                  style: TextStyle(fontSize: _fontSize, height: 1.6),
                ),
              ),

              const SizedBox(height: 16),

              // 次の話へ移動
              _buildNavBox(
                icon: Icons.keyboard_arrow_down,
                enabled: !_isLoadingList && _nextEpisode != null,
                onTap: () {
                  final nextEpisode = _nextEpisode;

                  if (nextEpisode != null) {
                    _goToEpisode(nextEpisode);
                  }
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingToolbar() {
    final theme = Theme.of(context);

    return Positioned(
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        ignoring: !_toolbarVisible,
        child: AnimatedOpacity(
          opacity: _toolbarVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.grey[850]!.withValues(alpha: 0.92)
                  : Colors.grey[800]!.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 6),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white70),
                  tooltip: '目次に戻る',
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.text_fields, color: Colors.white70),
                  tooltip: '文字サイズ',
                  onPressed: _showFontSizeSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz, color: Colors.white70),
                  tooltip: 'その他',
                  onPressed: _showMoreMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        title: Text(
          _currentEpisodeTitle,

          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            _buildReaderContent(),

          // 画面右下のツールバー
          _buildFloatingToolbar(),
        ],
      ),
    );
  }
}
