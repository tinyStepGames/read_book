class ParsedSearchQuery {
  const ParsedSearchQuery({
    required this.original,
    required this.includeWords,
    required this.excludeWords,
  });

  final String original;
  final List<String> includeWords;
  final List<String> excludeWords;

  String get includeQuery => includeWords.join(' ');

  String get excludeQuery => excludeWords.join(' ');

  bool get hasIncludeWords => includeWords.isNotEmpty;

  bool get hasExcludeWords => excludeWords.isNotEmpty;

  /// カクヨム検索に渡す検索文字列を生成します。
  String get kakuyomuQuery {
    final parts = <String>[
      ...includeWords.map(_quoteIfNeeded),
      ...excludeWords.map((word) => '-${_quoteIfNeeded(word)}'),
    ];

    return parts.join(' ');
  }

  static String _quoteIfNeeded(String value) {
    if (value.contains(RegExp(r'\s'))) {
      return '"$value"';
    }

    return value;
  }
}

class SearchQueryParser {
  const SearchQueryParser._();

  static ParsedSearchQuery parse(String rawQuery) {
    final normalized = rawQuery
        .replaceAll('－', '-')
        .replaceAll('−', '-')
        .replaceAll('―', '-')
        .trim();

    final includeWords = <String>[];
    final excludeWords = <String>[];

    // 通常の単語と、"空白を含む語句"の両方に対応します。
    final pattern = RegExp(r'(-?)"([^"]+)"|(\S+)');

    for (final match in pattern.allMatches(normalized)) {
      final quotedSign = match.group(1) ?? '';
      final quotedValue = match.group(2);
      final plainValue = match.group(3);

      if (quotedValue != null) {
        final value = quotedValue.trim();

        if (value.isEmpty) {
          continue;
        }

        if (quotedSign == '-') {
          _addUnique(excludeWords, value);
        } else {
          _addUnique(includeWords, value);
        }

        continue;
      }

      if (plainValue == null) {
        continue;
      }

      final token = plainValue.trim();

      if (token.isEmpty || token == '-') {
        continue;
      }

      if (token.startsWith('-') && token.length > 1) {
        final value = token.substring(1).trim();

        if (value.isNotEmpty) {
          _addUnique(excludeWords, value);
        }
      } else {
        _addUnique(includeWords, token);
      }
    }

    return ParsedSearchQuery(
      original: rawQuery,
      includeWords: List.unmodifiable(includeWords),
      excludeWords: List.unmodifiable(excludeWords),
    );
  }

  static void _addUnique(List<String> values, String value) {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      return;
    }

    final alreadyExists = values.any(
      (item) => item.toLowerCase() == normalizedValue.toLowerCase(),
    );

    if (!alreadyExists) {
      values.add(normalizedValue);
    }
  }
}
