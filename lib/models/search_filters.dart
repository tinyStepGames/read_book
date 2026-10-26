enum SearchSerialStatus { all, ongoing, completed, shortStory }

enum SearchLengthPreset { all, short, medium, long, veryLong, custom }

class SearchFilters {
  final SearchSerialStatus serialStatus;
  final SearchLengthPreset lengthPreset;
  final int? customMinimumLength;
  final int? customMaximumLength;

  const SearchFilters({
    this.serialStatus = SearchSerialStatus.all,
    this.lengthPreset = SearchLengthPreset.all,
    this.customMinimumLength,
    this.customMaximumLength,
  });

  bool get isActive {
    return serialStatus != SearchSerialStatus.all ||
        lengthPreset != SearchLengthPreset.all;
  }

  int? get minimumLength {
    switch (lengthPreset) {
      case SearchLengthPreset.all:
      case SearchLengthPreset.short:
        return null;

      case SearchLengthPreset.medium:
        return 20000;

      case SearchLengthPreset.long:
        return 100000;

      case SearchLengthPreset.veryLong:
        return 500000;

      case SearchLengthPreset.custom:
        return customMinimumLength;
    }
  }

  int? get maximumLength {
    switch (lengthPreset) {
      case SearchLengthPreset.all:
      case SearchLengthPreset.long:
      case SearchLengthPreset.veryLong:
        return null;

      case SearchLengthPreset.short:
        return 20000;

      case SearchLengthPreset.medium:
        return 100000;

      case SearchLengthPreset.custom:
        return customMaximumLength;
    }
  }

  String? get narouTypeParameter {
    switch (serialStatus) {
      case SearchSerialStatus.all:
        return null;

      case SearchSerialStatus.ongoing:
        return 'r';

      case SearchSerialStatus.completed:
        return 'er';

      case SearchSerialStatus.shortStory:
        return 't';
    }
  }

  String? get kakuyomuSerialStatusParameter {
    switch (serialStatus) {
      case SearchSerialStatus.all:
      case SearchSerialStatus.shortStory:
        return null;

      case SearchSerialStatus.ongoing:
        return 'ONGOING';

      case SearchSerialStatus.completed:
        return 'COMPLETED';
    }
  }

  String? validate() {
    final minimum = minimumLength;
    final maximum = maximumLength;

    if (minimum != null && minimum < 0) {
      return '最小文字数は0以上で指定してください';
    }

    if (maximum != null && maximum < 0) {
      return '最大文字数は0以上で指定してください';
    }

    if (minimum != null && maximum != null && minimum > maximum) {
      return '最小文字数は最大文字数以下にしてください';
    }

    return null;
  }

  bool matches({
    required bool isShortStory,
    required bool isCompleted,
    required int length,
  }) {
    switch (serialStatus) {
      case SearchSerialStatus.all:
        break;

      case SearchSerialStatus.ongoing:
        if (isShortStory || isCompleted) {
          return false;
        }
        break;

      case SearchSerialStatus.completed:
        if (isShortStory || !isCompleted) {
          return false;
        }
        break;

      case SearchSerialStatus.shortStory:
        if (!isShortStory) {
          return false;
        }
        break;
    }

    final minimum = minimumLength;
    final maximum = maximumLength;

    if (minimum != null && length < minimum) {
      return false;
    }

    if (maximum != null && length > maximum) {
      return false;
    }

    return true;
  }

  SearchFilters copyWith({
    SearchSerialStatus? serialStatus,
    SearchLengthPreset? lengthPreset,
    int? customMinimumLength,
    int? customMaximumLength,
    bool clearCustomMinimumLength = false,
    bool clearCustomMaximumLength = false,
  }) {
    return SearchFilters(
      serialStatus: serialStatus ?? this.serialStatus,
      lengthPreset: lengthPreset ?? this.lengthPreset,
      customMinimumLength: clearCustomMinimumLength
          ? null
          : customMinimumLength ?? this.customMinimumLength,
      customMaximumLength: clearCustomMaximumLength
          ? null
          : customMaximumLength ?? this.customMaximumLength,
    );
  }
}
