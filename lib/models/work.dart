import 'package:hive/hive.dart';

import '../utils/work_tags.dart';

part 'work.g.dart';

@HiveType(typeId: 1)
class Work extends HiveObject {
  @HiveField(0)
  String workId;

  @HiveField(1)
  int siteIndex;

  @HiveField(2)
  String title;

  @HiveField(3)
  String author;

  @HiveField(4)
  String genre;

  @HiveField(5)
  String summary;

  @HiveField(6)
  int totalEpisodeCount;

  @HiveField(7)
  int checkedEpisodeCount;

  @HiveField(8)
  DateTime lastUpdatedAt;

  @HiveField(9)
  bool isCompleted;

  @HiveField(10)
  DateTime? firstOpenedAt;

  @HiveField(11)
  String? authorId;

  @HiveField(12)
  String? keyword;

  Work({
    required this.workId,
    required this.siteIndex,
    required this.title,
    required this.author,
    required this.genre,
    required this.summary,
    required this.totalEpisodeCount,
    required this.checkedEpisodeCount,
    required this.lastUpdatedAt,
    required this.isCompleted,
    this.firstOpenedAt,
    this.authorId,
    this.keyword,
  });

  /// 保存形式に応じてkeyword文字列をタグのリストへ変換します。
  List<String> get tags => WorkTags.decode(keyword ?? '');
}
