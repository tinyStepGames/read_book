import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/episode.dart';
import 'models/favorite.dart';
import 'models/history_entry.dart';
import 'models/saved_search.dart';
import 'models/work.dart';
import 'models/download_job.dart';
import 'screens/favorite_screen.dart';
import 'screens/history_screen.dart';
import 'screens/search_screen.dart';
import 'screens/archive_screen.dart';
import 'services/backup_service.dart';

import 'services/novel_repository.dart';
import 'services/search_request_controller.dart';
import 'services/download_manager.dart';
import 'models/download.dart';
import 'models/read_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hiveを開く前に、保留中のバックアップを復元します。
  final startupMessage = await BackupService.applyPendingRestoreIfNeeded();

  await Hive.initFlutter();

  Hive.registerAdapter(WorkAdapter());
  Hive.registerAdapter(EpisodeAdapter());
  Hive.registerAdapter(FavoriteAdapter());
  Hive.registerAdapter(SavedSearchAdapter());
  Hive.registerAdapter(HistoryEntryAdapter());
  Hive.registerAdapter(DownloadJobAdapter());
  Hive.registerAdapter(DownloadAdapter());
  Hive.registerAdapter(ReadMarkAdapter());

  await _openBoxSafely<Work>('works');
  await _openBoxSafely<Episode>('episodes');
  await _openBoxSafely<Favorite>('favorites');
  await _openBoxSafely<SavedSearch>('saved_searches');
  await _openBoxSafely<HistoryEntry>('history');
  await _openBoxSafely<DownloadJob>('download_jobs');
  await _openBoxSafely<Download>('downloads');
  await _openBoxSafely<ReadMark>('read_marks');

  runApp(MyApp(startupMessage: startupMessage));
}

Future<void> _openBoxSafely<T>(String name) async {
  try {
    await Hive.openBox<T>(name);
  } catch (error, stackTrace) {
    debugPrint('Box "$name" の読み込みに失敗しました: $error');
    debugPrintStack(stackTrace: stackTrace);

    // 自動削除は行いません。
    // 復元データや既存データを誤って消さないためです。
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  final String? startupMessage;

  const MyApp({super.key, this.startupMessage});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Read Book',
    themeMode: ThemeMode.system,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.light,
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
        surface: Colors.black,
      ).copyWith(surface: Colors.black),
    ),
    home: RootScreen(startupMessage: startupMessage),
  );
}

class RootScreen extends StatefulWidget {
  final String? startupMessage;

  const RootScreen({super.key, this.startupMessage});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final NovelRepository _repository = NovelRepository();
  final SearchRequestController _searchRequestController =
      SearchRequestController();
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    SearchScreen(
      repository: _repository,
      searchRequestController: _searchRequestController,
    ),
    FavoriteScreen(
      repository: _repository,
      searchRequestController: _searchRequestController,
      onNavigateToSearch: () {
        setState(() {
          _currentIndex = 0;
        });
      },
    ),
    HistoryScreen(
      repository: _repository,
      searchRequestController: _searchRequestController,
      onNavigateToSearch: () {
        setState(() {
          _currentIndex = 0;
        });
      },
    ),
    ArchiveScreen(
      repository: _repository,
      searchRequestController: _searchRequestController,
      onNavigateToSearch: () {
        setState(() {
          _currentIndex = 0;
        });
      },
    ),
  ];

  @override
  void initState() {
    super.initState();

    DownloadManager.init(_repository);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = widget.startupMessage;

      if (!mounted || message == null || message.trim().isEmpty) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: '検索'),
          NavigationDestination(icon: Icon(Icons.star), label: 'お気に入り'),
          NavigationDestination(icon: Icon(Icons.history), label: '履歴'),
          NavigationDestination(icon: Icon(Icons.folder), label: '書庫'),
        ],
      ),
    );
  }
}
