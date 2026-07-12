import 'package:hive/hive.dart';

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

  // タグ(キーワード)だけを対象にした検索か
  @HiveField(6)
  bool keywordOnly;

  SavedSearch({
    required this.id,
    required this.siteIndex,
    required this.keyword,
    required this.order,
    List<String>? lastKnownNcodes,
    this.authorNameOnly = false,
    this.keywordOnly = false,
  }) : lastKnownNcodes = lastKnownNcodes ?? [];
}
