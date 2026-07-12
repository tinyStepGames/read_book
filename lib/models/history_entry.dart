import 'package:hive/hive.dart';

part 'history_entry.g.dart';

@HiveType(typeId: 5)
class HistoryEntry extends HiveObject {
  @HiveField(0)
  String workId;

  @HiveField(1)
  int episodeNo;

  @HiveField(2)
  double scrollFraction;

  @HiveField(3)
  DateTime lastReadAt;

  @HiveField(4)
  String? episodeTitle;

  HistoryEntry({
    required this.workId,
    required this.episodeNo,
    required this.scrollFraction,
    required this.lastReadAt,
    this.episodeTitle,
  });
}
