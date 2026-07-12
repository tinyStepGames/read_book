import 'package:hive/hive.dart';

part 'episode.g.dart';

@HiveType(typeId: 2)
class Episode extends HiveObject {
  @HiveField(0)
  String workId;

  @HiveField(1)
  int episodeNo;

  @HiveField(2)
  String episodeTitle;

  @HiveField(3)
  String body;

  @HiveField(4)
  DateTime fetchedAt;

  @HiveField(5)
  bool isRead; // 現在は使用しない(既存データ互換のため残す)

  @HiveField(6)
  DateTime? lastAccessedAt;

  Episode({
    required this.workId,
    required this.episodeNo,
    required this.episodeTitle,
    required this.body,
    required this.fetchedAt,
    this.isRead = false,
    this.lastAccessedAt,
  });
}
