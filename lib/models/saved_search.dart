import 'package:hive/hive.dart';

import 'search_filters.dart';

part 'saved_search.g.dart';

@HiveType(typeId: 4)
class SavedSearch extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  int siteIndex;

  @HiveField(2)
  String keyword;

  @HiveField(3)
  String order;

  @HiveField(4)
  List<String> lastKnownNcodes;

  // 作者名だけを対象にした検索か
  @HiveField(5)
  bool authorNameOnly;

  // タグ（キーワード）だけを対象にした検索か
  @HiveField(6)
  bool keywordOnly;

  // 既存データとの互換性を保つため、
  // 新しい検索条件は既存フィールドの後ろへ追加します。
  @HiveField(7, defaultValue: 0)
  int serialStatusIndex;

  @HiveField(8, defaultValue: 0)
  int lengthPresetIndex;

  @HiveField(9)
  int? customMinimumLength;

  @HiveField(10)
  int? customMaximumLength;

  SavedSearch({
    required this.id,
    required this.siteIndex,
    required this.keyword,
    required this.order,
    List<String>? lastKnownNcodes,
    this.authorNameOnly = false,
    this.keywordOnly = false,
    this.serialStatusIndex = 0,
    this.lengthPresetIndex = 0,
    this.customMinimumLength,
    this.customMaximumLength,
  }) : lastKnownNcodes = lastKnownNcodes ?? [];

  SearchSerialStatus get serialStatus {
    if (serialStatusIndex < 0 ||
        serialStatusIndex >= SearchSerialStatus.values.length) {
      return SearchSerialStatus.all;
    }

    return SearchSerialStatus.values[serialStatusIndex];
  }

  SearchLengthPreset get lengthPreset {
    if (lengthPresetIndex < 0 ||
        lengthPresetIndex >= SearchLengthPreset.values.length) {
      return SearchLengthPreset.all;
    }

    return SearchLengthPreset.values[lengthPresetIndex];
  }

  SearchFilters get filters {
    return SearchFilters(
      serialStatus: serialStatus,
      lengthPreset: lengthPreset,
      customMinimumLength: customMinimumLength,
      customMaximumLength: customMaximumLength,
    );
  }

  bool matchesFilters(SearchFilters other) {
    return serialStatus == other.serialStatus &&
        lengthPreset == other.lengthPreset &&
        customMinimumLength == other.customMinimumLength &&
        customMaximumLength == other.customMaximumLength;
  }
}
