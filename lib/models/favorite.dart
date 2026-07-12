import 'package:hive/hive.dart';

part 'favorite.g.dart';

enum FavoriteTargetType { work, savedSearch }

@HiveType(typeId: 3)
class Favorite extends HiveObject {
  @HiveField(0)
  int targetTypeIndex;

  @HiveField(1)
  int colorIndex;

  @HiveField(2)
  String targetKey;

  @HiveField(3)
  DateTime registeredAt;

  @HiveField(4)
  DateTime? lastAccessedAt;

  @HiveField(5)
  bool autoCheck;

  @HiveField(6)
  bool hasUnseenUpdate;

  @HiveField(7)
  int lastKnownEpisodeCount;

  @HiveField(8)
  DateTime? lastCheckedAt;

  Favorite({
    required this.targetTypeIndex,
    required this.colorIndex,
    required this.targetKey,
    required this.registeredAt,
    this.lastAccessedAt,
    this.autoCheck = true,
    this.hasUnseenUpdate = false,
    this.lastKnownEpisodeCount = 0,
    this.lastCheckedAt,
  });

  FavoriteTargetType get targetType => FavoriteTargetType.values[targetTypeIndex];
  set targetType(FavoriteTargetType type) => targetTypeIndex = type.index;
}
