// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_search.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedSearchAdapter extends TypeAdapter<SavedSearch> {
  @override
  final int typeId = 4;

  @override
  SavedSearch read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedSearch(
      id: fields[0] as String,
      siteIndex: fields[1] as int,
      keyword: fields[2] as String,
      order: fields[3] as String,
      lastKnownNcodes: (fields[4] as List?)?.cast<String>(),
      authorNameOnly: fields[5] as bool,
      keywordOnly: fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SavedSearch obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.siteIndex)
      ..writeByte(2)
      ..write(obj.keyword)
      ..writeByte(3)
      ..write(obj.order)
      ..writeByte(4)
      ..write(obj.lastKnownNcodes)
      ..writeByte(5)
      ..write(obj.authorNameOnly)
      ..writeByte(6)
      ..write(obj.keywordOnly);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSearchAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
