import '../models/site.dart';

/// 外部サイトから取得するリソースのURLと容量を制限します。
class RemoteResourcePolicy {
  RemoteResourcePolicy._();

  /// 外部サイトから受け入れる1レスポンスの最大容量です。
  static const int maximumExternalResponseBytes = 8 * 1024 * 1024;

  /// 1話分のHTMLとして受け入れる最大容量です。
  static const int maximumEpisodeHtmlBytes = maximumExternalResponseBytes;

  /// 通常通信で利用するHTTPS URLを検証します。
  ///
  /// 許可ホスト、HTTPS、ユーザー情報、明示的ポートを確認します。
  static bool isAllowedExternalUri({
    required Uri uri,
    required Set<String> allowedHosts,
    bool allowRootPath = true,
  }) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }

    if (!allowRootPath && (uri.path.isEmpty || uri.path == '/')) {
      return false;
    }

    final host = uri.host.toLowerCase();

    return allowedHosts.any((allowedHost) => allowedHost.toLowerCase() == host);
  }

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

    if (uri == null) {
      return null;
    }

    final expectedHost = switch (site) {
      Site.narou => 'ncode.syosetu.com',
      Site.kakuyomu => 'kakuyomu.jp',
    };

    if (!isAllowedExternalUri(
      uri: uri,
      allowedHosts: {expectedHost},
      allowRootPath: false,
    )) {
      return null;
    }

    final host = uri.host.toLowerCase();

    return uri.replace(scheme: 'https', host: host).removeFragment();
  }
}
