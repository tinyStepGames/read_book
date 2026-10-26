import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/search_filters.dart';
import '../models/site.dart';

class SearchFilterBar extends StatelessWidget {
  final Site site;
  final SearchFilters filters;
  final bool enabled;
  final ValueChanged<SearchFilters> onChanged;

  const SearchFilterBar({
    super.key,
    required this.site,
    required this.filters,
    required this.onChanged,
    this.enabled = true,
  });

  int get _activeFilterCount {
    var count = 0;

    if (filters.serialStatus != SearchSerialStatus.all) {
      count += 1;
    }

    if (filters.lengthPreset != SearchLengthPreset.all) {
      count += 1;
    }

    return count;
  }

  @override
  Widget build(BuildContext context) {
    final activeFilterCount = _activeFilterCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          key: const Key('search-filter-button'),
          onPressed: enabled
              ? () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) {
                      return _SearchFilterSheet(
                        site: site,
                        filters: filters,
                        onApply: onChanged,
                      );
                    },
                  );
                }
              : null,
          icon: const Icon(Icons.tune, size: 18),
          label: Text(
            activeFilterCount == 0 ? '絞り込み' : '絞り込み ($activeFilterCount)',
          ),
        ),
      ),
    );
  }
}

class _SearchFilterSheet extends StatefulWidget {
  final Site site;
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onApply;

  const _SearchFilterSheet({
    required this.site,
    required this.filters,
    required this.onApply,
  });

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late SearchSerialStatus _serialStatus;
  late SearchLengthPreset _lengthPreset;
  late final TextEditingController _minimumController;
  late final TextEditingController _maximumController;

  String? _validationMessage;

  bool get _isNarou => widget.site == Site.narou;

  @override
  void initState() {
    super.initState();

    _serialStatus =
        !_isNarou &&
            widget.filters.serialStatus == SearchSerialStatus.shortStory
        ? SearchSerialStatus.all
        : widget.filters.serialStatus;

    _lengthPreset = widget.filters.lengthPreset;

    _minimumController = TextEditingController(
      text: widget.filters.customMinimumLength?.toString() ?? '',
    );

    _maximumController = TextEditingController(
      text: widget.filters.customMaximumLength?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _minimumController.dispose();
    _maximumController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<SearchSerialStatus>> get _serialStatusItems {
    return <DropdownMenuItem<SearchSerialStatus>>[
      const DropdownMenuItem<SearchSerialStatus>(
        value: SearchSerialStatus.all,
        child: Text('すべて'),
      ),
      const DropdownMenuItem<SearchSerialStatus>(
        value: SearchSerialStatus.ongoing,
        child: Text('連載中'),
      ),
      const DropdownMenuItem<SearchSerialStatus>(
        value: SearchSerialStatus.completed,
        child: Text('完結済み'),
      ),
      if (_isNarou)
        const DropdownMenuItem<SearchSerialStatus>(
          value: SearchSerialStatus.shortStory,
          child: Text('短編'),
        ),
    ];
  }

  List<DropdownMenuItem<SearchLengthPreset>> get _lengthItems {
    return const <DropdownMenuItem<SearchLengthPreset>>[
      DropdownMenuItem<SearchLengthPreset>(
        value: SearchLengthPreset.all,
        child: Text('すべて'),
      ),
      DropdownMenuItem<SearchLengthPreset>(
        value: SearchLengthPreset.short,
        child: Text('短編（2万文字以下）'),
      ),
      DropdownMenuItem<SearchLengthPreset>(
        value: SearchLengthPreset.medium,
        child: Text('中編（2万〜10万文字）'),
      ),
      DropdownMenuItem<SearchLengthPreset>(
        value: SearchLengthPreset.long,
        child: Text('長編（10万文字以上）'),
      ),
      DropdownMenuItem<SearchLengthPreset>(
        value: SearchLengthPreset.veryLong,
        child: Text('大長編（50万文字以上）'),
      ),
      DropdownMenuItem<SearchLengthPreset>(
        value: SearchLengthPreset.custom,
        child: Text('文字数を指定'),
      ),
    ];
  }

  int? _parseOptionalLength(TextEditingController controller) {
    final text = controller.text.trim();

    if (text.isEmpty) {
      return null;
    }

    return int.tryParse(text);
  }

  void _reset() {
    setState(() {
      _serialStatus = SearchSerialStatus.all;
      _lengthPreset = SearchLengthPreset.all;
      _minimumController.clear();
      _maximumController.clear();
      _validationMessage = null;
    });
  }

  void _apply() {
    final minimumLength = _parseOptionalLength(_minimumController);
    final maximumLength = _parseOptionalLength(_maximumController);

    if (_lengthPreset == SearchLengthPreset.custom) {
      if (_minimumController.text.trim().isNotEmpty && minimumLength == null) {
        setState(() {
          _validationMessage = '最小文字数を半角数字で入力してください';
        });
        return;
      }

      if (_maximumController.text.trim().isNotEmpty && maximumLength == null) {
        setState(() {
          _validationMessage = '最大文字数を半角数字で入力してください';
        });
        return;
      }
    }

    final filters = SearchFilters(
      serialStatus: _serialStatus,
      lengthPreset: _lengthPreset,
      customMinimumLength: _lengthPreset == SearchLengthPreset.custom
          ? minimumLength
          : null,
      customMaximumLength: _lengthPreset == SearchLengthPreset.custom
          ? maximumLength
          : null,
    );

    final validationMessage = filters.validate();

    if (validationMessage != null) {
      setState(() {
        _validationMessage = validationMessage;
      });
      return;
    }

    widget.onApply(filters);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('検索の絞り込み', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: '閉じる',
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SearchSerialStatus>(
            key: const Key('serial-status-dropdown'),
            initialValue: _serialStatus,
            decoration: const InputDecoration(
              labelText: '連載状態',
              border: OutlineInputBorder(),
            ),
            items: _serialStatusItems,
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _serialStatus = value;
                _validationMessage = null;
              });
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SearchLengthPreset>(
            key: const Key('length-preset-dropdown'),
            initialValue: _lengthPreset,
            decoration: const InputDecoration(
              labelText: '小説の長さ',
              border: OutlineInputBorder(),
            ),
            items: _lengthItems,
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _lengthPreset = value;
                _validationMessage = null;
              });
            },
          ),
          if (_lengthPreset == SearchLengthPreset.custom) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('minimum-length-field'),
                    controller: _minimumController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: '最小文字数',
                      hintText: '指定なし',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('〜'),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('maximum-length-field'),
                    controller: _maximumController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: '最大文字数',
                      hintText: '指定なし',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_validationMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _validationMessage!,
              key: const Key('filter-validation-message'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                key: const Key('reset-search-filters'),
                onPressed: _reset,
                child: const Text('リセット'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('apply-search-filters'),
                onPressed: _apply,
                icon: const Icon(Icons.search),
                label: const Text('この条件で検索'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
