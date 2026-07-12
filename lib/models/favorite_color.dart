import 'package:flutter/material.dart';

enum FavoriteColor { blue, cyan, green, purple, yellow, red }

extension FavoriteColorX on FavoriteColor {
  Color get materialColor {
    switch (this) {
      case FavoriteColor.blue:
        return const Color(0xFF3B82F6);
      case FavoriteColor.cyan:
        return const Color(0xFF60C7F0);
      case FavoriteColor.green:
        return const Color(0xFF34D399);
      case FavoriteColor.purple:
        return const Color(0xFFA78BFA);
      case FavoriteColor.yellow:
        return const Color(0xFFFBBF24);
      case FavoriteColor.red:
        return const Color(0xFFF87171);
    }
  }

  String get label {
    switch (this) {
      case FavoriteColor.blue:
        return 'お気に入り1';
      case FavoriteColor.cyan:
        return 'お気に入り2';
      case FavoriteColor.green:
        return 'お気に入り3';
      case FavoriteColor.purple:
        return 'お気に入り4';
      case FavoriteColor.yellow:
        return 'お気に入り5';
      case FavoriteColor.red:
        return 'お気に入り6';
    }
  }
}
