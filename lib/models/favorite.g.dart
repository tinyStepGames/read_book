// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FavoriteAdapter extends TypeAdapter<Favorite> {
  @override
  final int typeId = 3;

  @override
  Favorite read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Favorite(
      targetTypeIndex: fields[0] as int,
      colorIndex: fields[1] as int,
      targetKey: fields[2] as String,
      registeredAt: fields[3] as DateTime,
      lastAccessedAt: fields[4] as DateTime?,
      autoCheck: fields[5] as bool,
      hasUnseenUpdate: fields[6] as bool,
      lastKnownEpisodeCount: fields[7] as int,
      lastCheckedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Favorite obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.targetTypeIndex)
      ..writeByte(1)
      ..write(obj.colorIndex)
      ..writeByte(2)
      ..write(obj.targetKey)
      ..writeByte(3)
      ..write(obj.registeredAt)
      ..writeByte(4)
      ..write(obj.lastAccessedAt)
      ..writeByte(5)
      ..write(obj.autoCheck)
      ..writeByte(6)
      ..write(obj.hasUnseenUpdate)
      ..writeByte(7)
      ..write(obj.lastKnownEpisodeCount)
      ..writeByte(8)
      ..write(obj.lastCheckedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
