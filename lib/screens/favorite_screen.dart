import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/favorite.dart';
import '../models/favorite_color.dart';
import '../models/saved_search.dart';
import '../models/site.dart';
import '../models/work.dart';
import '../services/novel_repository.dart';
import '../services/search_request_controller.dart';
import 'work_detail_screen.dart';

// ファイル先頭の import の下、クラス定義の外側(トップレベル)に追加
class _ClearFavoriteMarker {
  const _ClearFavoriteMarker();
}

const _clearFavoriteMarker = _ClearFavoriteMarker();

class FavoriteScreen extends StatefulWidget {
  final NovelRepository repository;
  final SearchRequestController searchRequestController;
  final VoidCallback onNavigateToSearch;

  const FavoriteScreen({
    super.key,
    required this.repository,
    required this.searchRequestController,
    required this.onNavigateToSearch,
  });

  @override
  State<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<FavoriteScreen> {
  FavoriteColor? _filter;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入り'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _filterChip(null, Icons.list, Colors.white70),
                for (final c in FavoriteColor.values)
                  _filterChip(c, Icons.star, c.materialColor),
              ],
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder<Box<Favorite>>(
        valueListenable: Hive.box<Favorite>('favorites').listenable(),
        builder: (context, box, _) {
          return _buildCombinedList(box);
        },
      ),
    );
  }

  Widget _buildCombinedList(Box<Favorite> box) {
    final works = Hive.box<Work>('works');

    final favorites = box.values
        .where((f) => _filter == null || f.colorIndex == _filter!.index)
        .toList();
    favorites.sort(
      (a, b) => (b.lastAccessedAt ?? b.registeredAt).compareTo(
        a.lastAccessedAt ?? a.registeredAt,
      ),
    );

    if (favorites.isEmpty) {
      return const Center(child: Text('お気に入りはまだありません'));
    }

    return ListView.separated(
      itemCount: favorites.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final fav = favorites[index];
        if (fav.targetType == FavoriteTargetType.work) {
          final work = works.get(fav.targetKey);
          if (work == null) return const SizedBox.shrink();
          return _buildWorkTile(fav, work);
        } else {
          final saved = widget.repository.getSavedSearch(fav.targetKey);
          if (saved == null) return const SizedBox.shrink();
          return _buildSearchTile(fav, saved);
        }
      },
    );
  }

  Widget _buildWorkTile(Favorite fav, Work work) {
    final color = FavoriteColor.values[fav.colorIndex];
    final site = Site.values[work.siteIndex];

    return ListTile(
      leading: GestureDetector(
        onTap: () => _pickColorForFavorite(fav),
        onLongPress: () => _pickColorForFavorite(fav),
        child: Icon(Icons.star, color: color.materialColor, size: 28),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: work.isCompleted ? Colors.grey : Colors.teal,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              work.isCompleted ? '完結' : '連載',
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              work.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fav.hasUnseenUpdate ? Colors.redAccent : null,
                fontWeight: fav.hasUnseenUpdate ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '作:${work.author}　サイト:${site.displayName}\n'
        'アクセス日:${_dateFormat.format(fav.lastAccessedAt ?? fav.registeredAt)}',
      ),
      isThreeLine: true,
      trailing: Icon(
        fav.hasUnseenUpdate ? Icons.fiber_new : Icons.check,
        color: fav.hasUnseenUpdate ? Colors.redAccent : Colors.grey,
      ),
      onTap: () async {
        fav.hasUnseenUpdate = false;
        fav.lastAccessedAt = DateTime.now();
        await fav.save();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WorkDetailScreen(repository: widget.repository, work: work),
          ),
        );
      },
    );
  }

  Widget _buildSearchTile(Favorite fav, SavedSearch saved) {
    final color = FavoriteColor.values[fav.colorIndex];
    final site = Site.values[saved.siteIndex];
    final label = saved.keyword.isEmpty ? '(キーワードなし)' : saved.keyword;

    return ListTile(
      leading: GestureDetector(
        onTap: () => _pickColorForFavorite(fav),
        onLongPress: () => _pickColorForFavorite(fav),
        child: Icon(Icons.star, color: color.materialColor, size: 28),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _searchModeLabel(saved),
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '検索:$label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        'サイト:${site.displayName}\n'
        'アクセス日:${_dateFormat.format(fav.lastAccessedAt ?? fav.registeredAt)}',
      ),

      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.grey),
        onPressed: () async {
          await widget.repository.removeSearchFavorite(saved.id);
        },
      ),
      onTap: () async {
        fav.lastAccessedAt = DateTime.now();
        await fav.save();
        widget.searchRequestController.request(
          SearchRequest(
  keyword: saved.keyword,
  order: saved.order,
  authorNameOnly: saved.authorNameOnly,
  keywordOnly: saved.keywordOnly,
  siteIndex: saved.siteIndex,
)

        );
        widget.onNavigateToSearch();
      },
    );
  }

  String _searchModeLabel(SavedSearch s) {
    if (s.authorNameOnly) return '作者名';
    if (s.keywordOnly) return 'タグ';
    return '検索';
  }

  Widget _filterChip(FavoriteColor? color, IconData icon, Color displayColor) {
    final isSelected = _filter == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        selected: isSelected,
        label: Icon(
          icon,
          size: 18,
          color: isSelected
              ? displayColor
              : displayColor.withValues(alpha: 0.5),
        ),
        onSelected: (_) => setState(() => _filter = color),
      ),
    );
  }

  Future<void> _pickColorForFavorite(Favorite fav) async {
    final current = FavoriteColor.values[fav.colorIndex];
    final selected = await showModalBottomSheet<Object?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in FavoriteColor.values)
              ListTile(
                leading: Icon(
                  current == c ? Icons.star : Icons.star_border,
                  color: c.materialColor,
                ),
                title: Text(c.label, style: TextStyle(color: c.materialColor)),
                onTap: () => Navigator.pop(sheetContext, c),
              ),
            ListTile(
              leading: const Icon(Icons.star_border, color: Colors.grey),
              title: const Text('解除'),
              onTap: () => Navigator.pop(sheetContext, _clearFavoriteMarker),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    // 外側タップなどでキャンセルされた場合は何もしない
    if (selected == null) return;

    if (fav.targetType == FavoriteTargetType.work) {
      final works = Hive.box<Work>('works');
      final work = works.get(fav.targetKey);
      if (work == null) return;

      if (selected is _ClearFavoriteMarker) {
        await widget.repository.setFavoriteColor(work, null);
      } else if (selected is FavoriteColor) {
        await widget.repository.setFavoriteColor(work, selected);
      }
    } else {
      if (selected is _ClearFavoriteMarker) {
        await widget.repository.removeSearchFavorite(fav.targetKey);
      } else if (selected is FavoriteColor) {
        fav.colorIndex = selected.index;
        await fav.save();
      }
    }
  }
}
