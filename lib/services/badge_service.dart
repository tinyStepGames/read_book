// services/badge_service.dart
import 'package:hive/hive.dart';
import '../models/favorite.dart';

class BadgeService {
  int countUnseen() {
    final box = Hive.box<Favorite>('favorites');
    return box.values.where((f) => f.hasUnseenUpdate).length;
  }
  // OSバッジ表示には app_badge_plus 等のパッケージを利用し、
  // countUnseen() の結果を渡す運用にする
}
