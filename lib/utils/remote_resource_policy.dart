import '../models/site.dart';

/// 外部サイトから取得するリソースのURLと容量を制限します。
class RemoteResourcePolicy {
  RemoteResourcePolicy._();

  /// 1話分のHTMLとして受け入れる最大容量です。
  static const int maximumEpisodeHtmlBytes = 8 * 1024 * 1024;

  /// 話URLを検証し、安全なHTTPS URLへ正規化します。
  ///
  /// 対象サイトと一致しないホスト、平文HTTP、ユーザー情報、
  /// 443以外の明示的なポートを拒否します。
  static Uri? normalizeEpisodeUri({
    required Site site,
    required String? source,
  }) {
    final value = source?.trim() ?? '';

    if (value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);

    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.path.isEmpty ||
        uri.path == '/') {
      return null;
    }

    final expectedHost = switch (site) {
      Site.narou => 'ncode.syosetu.com',
      Site.kakuyomu => 'kakuyomu.jp',
    };

    final host = uri.host.toLowerCase();

    if (host != expectedHost) {
      return null;
    }

    return uri.replace(scheme: 'https', host: host).removeFragment();
  }
}
