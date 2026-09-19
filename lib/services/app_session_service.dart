import 'package:hive/hive.dart';

class ReaderSession {
  const ReaderSession({
    required this.workId,
    required this.episodeNo,
    required this.episodeTitle,
    required this.scrollFraction,
    required this.fontSize,
  });

  final String workId;
  final int episodeNo;
  final String episodeTitle;
  final double scrollFraction;
  final double fontSize;
}

/// アプリ終了後も、最後に開いていた画面と読書位置を復元するための保存処理です。
///
/// 既存の作品・本文・履歴データとは独立した、アダプター不要のBoxを使用します。
class AppSessionService {
  AppSessionService._();

  static const String boxName = 'app_state';

  static const String _selectedTabKey = 'selected_tab';
  static const String _lastScreenKey = 'last_screen';
  static const String _workIdKey = 'reader_work_id';
  static const String _episodeNoKey = 'reader_episode_no';
  static const String _episodeTitleKey = 'reader_episode_title';
  static const String _scrollFractionKey = 'reader_scroll_fraction';
  static const String _fontSizeKey = 'reader_font_size';
  static const String _savedAtKey = 'reader_saved_at';

  static const String _readerScreen = 'reader';
  static const String _rootScreen = 'root';

  static Box<dynamic>? get _box {
    if (!Hive.isBoxOpen(boxName)) {
      return null;
    }

    return Hive.box<dynamic>(boxName);
  }

  static int get selectedTab {
    final value = _box?.get(_selectedTabKey);

    if (value is! int) {
      return 0;
    }

    return value.clamp(0, 3);
  }

  static Future<void> saveSelectedTab(int index) async {
    final box = _box;

    if (box == null) {
      return;
    }

    await box.put(_selectedTabKey, index.clamp(0, 3));
  }

  static ReaderSession? get readerSession {
    final box = _box;

    if (box == null || box.get(_lastScreenKey) != _readerScreen) {
      return null;
    }

    final workId = box.get(_workIdKey);
    final episodeNo = box.get(_episodeNoKey);
    final episodeTitle = box.get(_episodeTitleKey);
    final scrollFraction = box.get(_scrollFractionKey);
    final fontSize = box.get(_fontSizeKey);

    if (workId is! String ||
        workId.trim().isEmpty ||
        episodeNo is! int ||
        episodeNo <= 0) {
      return null;
    }

    return ReaderSession(
      workId: workId,
      episodeNo: episodeNo,
      episodeTitle: episodeTitle is String ? episodeTitle : '',
      scrollFraction: scrollFraction is num
          ? scrollFraction.toDouble().clamp(0.0, 1.0)
          : 0.0,
      fontSize: fontSize is num ? fontSize.toDouble().clamp(10.0, 32.0) : 16.0,
    );
  }

  static Future<void> saveReader({
    required String workId,
    required int episodeNo,
    required String episodeTitle,
    required double scrollFraction,
    required double fontSize,
  }) async {
    final box = _box;

    if (box == null || workId.trim().isEmpty || episodeNo <= 0) {
      return;
    }

    await box.putAll(<dynamic, dynamic>{
      _lastScreenKey: _readerScreen,
      _workIdKey: workId,
      _episodeNoKey: episodeNo,
      _episodeTitleKey: episodeTitle,
      _scrollFractionKey: scrollFraction.clamp(0.0, 1.0),
      _fontSizeKey: fontSize.clamp(10.0, 32.0),
      _savedAtKey: DateTime.now().toIso8601String(),
    });
  }

  static Future<void> clearReader() async {
    final box = _box;

    if (box == null) {
      return;
    }

    await box.put(_lastScreenKey, _rootScreen);
    await box.deleteAll(<dynamic>[
      _workIdKey,
      _episodeNoKey,
      _episodeTitleKey,
      _scrollFractionKey,
      _fontSizeKey,
      _savedAtKey,
    ]);
  }
}
