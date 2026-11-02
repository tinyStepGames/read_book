import 'package:hive/hive.dart';

import '../models/site.dart';
import 'app_session_service.dart';

class BlockedAuthorEntry {
  const BlockedAuthorEntry({
    required this.key,
    required this.siteIndex,
    required this.authorId,
    required this.authorName,
  });

  final String key;
  final int siteIndex;
  final String authorId;
  final String authorName;

  Site? get site {
    if (siteIndex < 0 || siteIndex >= Site.values.length) {
      return null;
    }

    return Site.values[siteIndex];
  }

  Map<String, Object> toMap() {
    return <String, Object>{
      'key': key,
      'siteIndex': siteIndex,
      'authorId': authorId,
      'authorName': authorName,
    };
  }

  static BlockedAuthorEntry? fromMap(Object? value) {
    if (value is! Map) {
      return null;
    }

    final key = value['key'];
    final siteIndex = value['siteIndex'];
    final authorId = value['authorId'];
    final authorName = value['authorName'];

    if (key is! String ||
        key.trim().isEmpty ||
        siteIndex is! int ||
        siteIndex < 0 ||
        siteIndex >= Site.values.length ||
        authorId is! String ||
        authorName is! String) {
      return null;
    }

    return BlockedAuthorEntry(
      key: key.trim(),
      siteIndex: siteIndex,
      authorId: authorId.trim(),
      authorName: authorName.trim(),
    );
  }
}

/// 検索結果から非表示にする作者を端末内へ保存します。
///
/// 作品・お気に入り・履歴・ダウンロード済み本文は削除しません。
class BlockedAuthorService {
  BlockedAuthorService._();

  static const String _storageKey = 'blocked_authors_v1';

  static Box<dynamic>? get _box {
    if (!Hive.isBoxOpen(AppSessionService.boxName)) {
      return null;
    }

    return Hive.box<dynamic>(AppSessionService.boxName);
  }

  static List<BlockedAuthorEntry> get entries {
    final stored = _box?.get(_storageKey);

    if (stored is! List) {
      return const <BlockedAuthorEntry>[];
    }

    final result = <BlockedAuthorEntry>[];
    final seenKeys = <String>{};

    for (final value in stored) {
      final entry = BlockedAuthorEntry.fromMap(value);

      if (entry == null || !seenKeys.add(entry.key)) {
        continue;
      }

      result.add(entry);
    }

    result.sort((a, b) {
      final siteComparison = a.siteIndex.compareTo(b.siteIndex);

      if (siteComparison != 0) {
        return siteComparison;
      }

      return a.authorName.compareTo(b.authorName);
    });

    return List<BlockedAuthorEntry>.unmodifiable(result);
  }

  static bool isBlocked({
    required Site site,
    required String authorId,
    required String authorName,
  }) {
    final key = _buildKey(
      site: site,
      authorId: authorId,
      authorName: authorName,
    );

    if (key == null) {
      return false;
    }

    return entries.any((entry) => entry.key == key);
  }

  static Future<bool> block({
    required Site site,
    required String authorId,
    required String authorName,
  }) async {
    final box = _box;

    if (box == null) {
      return false;
    }

    final key = _buildKey(
      site: site,
      authorId: authorId,
      authorName: authorName,
    );

    if (key == null) {
      return false;
    }

    final current = entries.toList();

    if (current.any((entry) => entry.key == key)) {
      return false;
    }

    current.add(
      BlockedAuthorEntry(
        key: key,
        siteIndex: site.index,
        authorId: authorId.trim(),
        authorName: authorName.trim(),
      ),
    );

    await _save(current);
    return true;
  }

  static Future<bool> unblock(String key) async {
    final box = _box;

    if (box == null || key.trim().isEmpty) {
      return false;
    }

    final current = entries.toList();
    final originalLength = current.length;

    current.removeWhere((entry) => entry.key == key.trim());

    if (current.length == originalLength) {
      return false;
    }

    await _save(current);
    return true;
  }

  static Future<void> _save(List<BlockedAuthorEntry> values) async {
    final box = _box;

    if (box == null) {
      return;
    }

    await box.put(
      _storageKey,
      values.map((entry) => entry.toMap()).toList(growable: false),
    );
  }

  static String? _buildKey({
    required Site site,
    required String authorId,
    required String authorName,
  }) {
    final normalizedAuthorId = authorId.trim().toLowerCase();

    if (normalizedAuthorId.isNotEmpty) {
      return '${site.name}|id|$normalizedAuthorId';
    }

    final normalizedAuthorName = authorName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();

    if (normalizedAuthorName.isEmpty) {
      return null;
    }

    return '${site.name}|name|$normalizedAuthorName';
  }
}
