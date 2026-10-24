import 'dart:convert';

import 'package:dio/dio.dart';

import 'remote_resource_policy.dart';

/// Dioによる外部通信へURL・リダイレクト・容量制限を適用します。
class RemoteResponseGuard extends Interceptor {
  RemoteResponseGuard(
    this._dio, {
    required Set<String> allowedHosts,
    this.maximumBytes = RemoteResourcePolicy.maximumExternalResponseBytes,
  }) : allowedHosts = {for (final host in allowedHosts) host.toLowerCase()};

  static const String _redirectCountKey = 'readBookRemoteResponseRedirectCount';

  static const int maximumRedirects = 3;

  final Dio _dio;
  final Set<String> allowedHosts;
  final int maximumBytes;

  /// 指定されたDioへ防御処理を追加します。
  static void install(
    Dio dio, {
    required Set<String> allowedHosts,
    int maximumBytes = RemoteResourcePolicy.maximumExternalResponseBytes,
  }) {
    dio.interceptors.add(
      RemoteResponseGuard(
        dio,
        allowedHosts: allowedHosts,
        maximumBytes: maximumBytes,
      ),
    );
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_isAllowed(options.uri)) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          message: '許可されていないURLへの通信を拒否しました',
        ),
      );
      return;
    }

    // 許可外ホストへ自動的に接続しないよう、
    // Dioの自動リダイレクトを無効化します。
    options.followRedirects = false;
    options.maxRedirects = 0;
    options.validateStatus = (status) {
      if (status == null) {
        return false;
      }

      return (status >= 200 && status < 300) || _isRedirectStatus(status);
    };

    final cancelToken = options.cancelToken ?? CancelToken();
    options.cancelToken = cancelToken;

    final previousProgress = options.onReceiveProgress;

    options.onReceiveProgress = (received, total) {
      previousProgress?.call(received, total);

      if (received > maximumBytes || (total >= 0 && total > maximumBytes)) {
        if (!cancelToken.isCancelled) {
          cancelToken.cancel(
            StateError(
              '外部レスポンスが容量上限を超えました: '
              '$maximumBytes バイト',
            ),
          );
        }
      }
    };

    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final statusCode = response.statusCode;

    if (statusCode != null && _isRedirectStatus(statusCode)) {
      await _handleRedirect(response, handler);
      return;
    }

    if (!_isAllowed(response.realUri)) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: '許可されていない応答URLを拒否しました',
        ),
      );
      return;
    }

    final declaredLength = int.tryParse(
      response.headers.value('content-length') ?? '',
    );

    if (declaredLength != null && declaredLength > maximumBytes) {
      handler.reject(_sizeException(response, declaredLength));
      return;
    }

    final actualLength = payloadByteLength(response.data);

    if (actualLength != null && actualLength > maximumBytes) {
      handler.reject(_sizeException(response, actualLength));
      return;
    }

    handler.next(response);
  }

  Future<void> _handleRedirect(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final requestOptions = response.requestOptions;

    final redirectCount = requestOptions.extra[_redirectCountKey] as int? ?? 0;

    if (redirectCount >= maximumRedirects) {
      handler.reject(
        DioException(
          requestOptions: requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'リダイレクト回数が上限を超えました',
        ),
      );
      return;
    }

    final location = response.headers.value('location');

    final targetUri = resolveSafeRedirectUri(
      currentUri: response.realUri,
      location: location,
      allowedHosts: allowedHosts,
    );

    if (targetUri == null) {
      handler.reject(
        DioException(
          requestOptions: requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: '許可されていないリダイレクト先を拒否しました',
        ),
      );
      return;
    }

    final redirectedOptions = requestOptions.copyWith(
      path: targetUri.toString(),
      baseUrl: '',
      queryParameters: <String, dynamic>{},
      followRedirects: false,
      maxRedirects: 0,
    );

    redirectedOptions.extra[_redirectCountKey] = redirectCount + 1;

    try {
      final redirectedResponse = await _dio.fetch<dynamic>(redirectedOptions);

      handler.resolve(redirectedResponse);
    } on DioException catch (error) {
      handler.reject(error);
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: redirectedOptions,
          error: error,
          stackTrace: stackTrace,
          message: '安全なリダイレクトの処理に失敗しました',
        ),
      );
    }
  }

  DioException _sizeException(Response<dynamic> response, int actualBytes) {
    return DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message:
          '外部レスポンスが容量上限を超えました: '
          '$actualBytes / $maximumBytes バイト',
    );
  }

  bool _isAllowed(Uri uri) {
    return RemoteResourcePolicy.isAllowedExternalUri(
      uri: uri,
      allowedHosts: allowedHosts,
    );
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  /// Locationを現在のURLに対して解決し、安全性を検証します。
  static Uri? resolveSafeRedirectUri({
    required Uri currentUri,
    required String? location,
    required Set<String> allowedHosts,
  }) {
    final value = location?.trim() ?? '';

    if (value.isEmpty) {
      return null;
    }

    final locationUri = Uri.tryParse(value);

    if (locationUri == null) {
      return null;
    }

    final targetUri = currentUri.resolveUri(locationUri);

    if (!RemoteResourcePolicy.isAllowedExternalUri(
      uri: targetUri,
      allowedHosts: allowedHosts,
    )) {
      return null;
    }

    return targetUri.removeFragment();
  }

  /// 変換後レスポンスのおおよそのバイト数を返します。
  static int? payloadByteLength(dynamic payload) {
    if (payload == null) {
      return 0;
    }

    if (payload is String) {
      return utf8.encode(payload).length;
    }

    if (payload is List<int>) {
      return payload.length;
    }

    if (payload is Map || payload is List) {
      try {
        return utf8.encode(jsonEncode(payload)).length;
      } on JsonUnsupportedObjectError {
        return null;
      }
    }

    return null;
  }
}
