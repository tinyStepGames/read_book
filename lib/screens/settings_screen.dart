import 'package:flutter/material.dart';

import '../services/blocked_author_service.dart';
import '../widgets/blocked_authors_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _openBlockedAuthors() async {
    await showBlockedAuthorsDialog(context);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final blockedAuthorCount = BlockedAuthorService.entries.length;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '検索',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: const Text('ブロック中の作者'),
            subtitle: Text(
              blockedAuthorCount == 0
                  ? 'ブロック中の作者はいません'
                  : '$blockedAuthorCount人をブロック中',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openBlockedAuthors,
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '今後、アプリ全体の設定をこの画面へ追加できます。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
