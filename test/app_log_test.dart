import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/utils/app_log.dart';

void main() {
  test('AppLogは例外本文をログへ出力しない', () {
    final messages = <String>[];
    final previousDebugPrint = debugPrint;

    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };

    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    AppLog.failure(
      '外部通信に失敗しました',
      StateError(
        'https://example.invalid/private/work-id '
        'C:\\Users\\example\\private-file.zip',
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('外部通信に失敗しました'));
    expect(messages.single, contains('StateError'));
    expect(messages.single, isNot(contains('example.invalid')));
    expect(messages.single, isNot(contains('work-id')));
    expect(messages.single, isNot(contains(r'C:\Users')));
    expect(messages.single, isNot(contains('private-file.zip')));
  });
}
