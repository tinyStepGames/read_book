import 'package:flutter/foundation.dart';

/// お気に入り画面から検索画面へ、検索条件を渡すためのリクエスト
class SearchRequest {
  final String keyword;
  final String order;
  final bool authorNameOnly;
  final bool keywordOnly;
  final int siteIndex;


  const SearchRequest({
  required this.keyword,
  this.order = 'new',
  this.authorNameOnly = false,
  this.keywordOnly = false,
  this.siteIndex = 0,
});

}

/// 画面間で検索リクエストを橋渡しするためのコントローラ
/// main.dart で1つだけ生成し、SearchScreen と FavoriteScreen の両方に渡す
class SearchRequestController extends ValueNotifier<SearchRequest?> {
  SearchRequestController() : super(null);

  void request(SearchRequest request) {
    value = request;
  }

  /// リクエストを消費済みにする(再度同じリクエストが誤って処理されないようにする)
  void consume() {
    value = null;
  }
}
