import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/utils/remote_response_guard.dart';
import 'package:read_book/utils/remote_resource_policy.dart';

void main() {
  group('RemoteResponseGuard', () {
    const narouHosts = {'api.syosetu.com', 'ncode.syosetu.com'};

    test('許可ホスト内の相対リダイレクトを受け入れる', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: '/n3380le/1/?view=all',
        allowedHosts: narouHosts,
      );

      expect(uri, Uri.parse('https://ncode.syosetu.com/n3380le/1/?view=all'));
    });

    test('同じ許可ホストの絶対URLを受け入れる', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: 'https://ncode.syosetu.com/n3380le/2/',
        allowedHosts: narouHosts,
      );

      expect(uri, Uri.parse('https://ncode.syosetu.com/n3380le/2/'));
    });

    test('許可外ホストへのリダイレクトを拒否する', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: 'https://example.com/redirected',
        allowedHosts: narouHosts,
      );

      expect(uri, isNull);
    });

    test('許可ホストに見せかけた別ドメインを拒否する', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: 'https://ncode.syosetu.com.example.com/redirected',
        allowedHosts: narouHosts,
      );

      expect(uri, isNull);
    });

    test('HTTPへのリダイレクトを拒否する', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: 'http://ncode.syosetu.com/n3380le/1/',
        allowedHosts: narouHosts,
      );

      expect(uri, isNull);
    });

    test('ユーザー情報を含むリダイレクトを拒否する', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: 'https://user@ncode.syosetu.com/n3380le/2/',
        allowedHosts: narouHosts,
      );

      expect(uri, isNull);
    });

    test('空のLocationを拒否する', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: '',
        allowedHosts: narouHosts,
      );

      expect(uri, isNull);
    });

    test('フラグメントを除去する', () {
      final uri = RemoteResponseGuard.resolveSafeRedirectUri(
        currentUri: Uri.parse('https://ncode.syosetu.com/n3380le/1/'),
        location: '/n3380le/2/#section',
        allowedHosts: narouHosts,
      );

      expect(uri, Uri.parse('https://ncode.syosetu.com/n3380le/2/'));
    });

    test('UTF-8文字列の実バイト数を計算する', () {
      expect(RemoteResponseGuard.payloadByteLength('あ'), 3);
    });

    test('バイト配列の長さを計算する', () {
      expect(RemoteResponseGuard.payloadByteLength(<int>[1, 2, 3]), 3);
    });

    test('通常通信の容量上限は8MiBである', () {
      expect(
        RemoteResourcePolicy.maximumExternalResponseBytes,
        8 * 1024 * 1024,
      );
    });

    test('リダイレクト上限は3回である', () {
      expect(RemoteResponseGuard.maximumRedirects, 3);
    });
  });
}
