import 'package:flutter/foundation.dart';

import '../models/search_filters.dart';

/// お気に入り画面などから検索画面へ、検索条件を渡すためのリクエストです。
class SearchRequest {
  final String keyword;
  final String order;
  final bool authorNameOnly;
  final bool keywordOnly;
  final int siteIndex;
  final SearchFilters filters;

  const SearchRequest({
    required this.keyword,
    this.order = 'new',
    this.authorNameOnly = false,
    this.keywordOnly = false,
    this.siteIndex = 0,
    this.filters = const SearchFilters(),
  });
}

/// 画面間で検索リクエストを橋渡しするためのコントローラです。
class SearchRequestController extends ValueNotifier<SearchRequest?> {
  SearchRequestController() : super(null);

  void request(SearchRequest request) {
    value = request;
  }

  /// リクエストを消費済みにします。
  void consume() {
    value = null;
  }
}
