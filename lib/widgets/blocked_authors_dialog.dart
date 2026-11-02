import 'package:flutter/material.dart';

import '../models/site.dart';
import '../services/blocked_author_service.dart';

Future<void> showBlockedAuthorsDialog(BuildContext context) async {
  final initialEntries = BlockedAuthorService.entries;

  if (initialEntries.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ブロック中の作者はいません')));
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return const _BlockedAuthorsSheet();
    },
  );
}

class _BlockedAuthorsSheet extends StatefulWidget {
  const _BlockedAuthorsSheet();

  @override
  State<_BlockedAuthorsSheet> createState() => _BlockedAuthorsSheetState();
}

class _BlockedAuthorsSheetState extends State<_BlockedAuthorsSheet> {
  bool _isUpdating = false;

  Future<void> _unblock(BlockedAuthorEntry entry) async {
    if (_isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    await BlockedAuthorService.unblock(entry.key);

    if (!mounted) {
      return;
    }

    setState(() {
      _isUpdating = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${entry.authorName.isEmpty ? '作者' : entry.authorName}'
          'のブロックを解除しました。再検索すると表示されます',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = BlockedAuthorService.entries;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'ブロック中の作者',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'ブロックを解除した作者の作品は、次の検索から表示されます。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('ブロック中の作者はいません'))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final siteName = entry.site?.displayName ?? '不明な掲載サイト';
                        final authorName = entry.authorName.isEmpty
                            ? '(作者名なし)'
                            : entry.authorName;

                        return ListTile(
                          leading: const Icon(Icons.person_off_outlined),
                          title: Text(authorName),
                          subtitle: Text(siteName),
                          trailing: TextButton(
                            onPressed: _isUpdating
                                ? null
                                : () {
                                    _unblock(entry);
                                  },
                            child: const Text('解除'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
