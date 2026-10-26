import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/search_filters.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/widgets/search_filter_bar.dart';

void main() {
  Future<void> openFilterSheet(
    WidgetTester tester, {
    required Site site,
    SearchFilters filters = const SearchFilters(),
    ValueChanged<SearchFilters>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchFilterBar(
            site: site,
            filters: filters,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('search-filter-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('なろうでは連載状態に短編を表示する', (tester) async {
    await openFilterSheet(tester, site: Site.narou);

    await tester.tap(find.byKey(const Key('serial-status-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('短編'), findsOneWidget);
  });

  testWidgets('カクヨムでは連載状態に短編を表示しない', (tester) async {
    await openFilterSheet(tester, site: Site.kakuyomu);

    await tester.tap(find.byKey(const Key('serial-status-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('連載中'), findsOneWidget);
    expect(find.text('完結済み'), findsOneWidget);
    expect(find.text('短編'), findsNothing);
  });

  testWidgets('文字数指定を選ぶと最小・最大文字数欄を表示する', (tester) async {
    await openFilterSheet(tester, site: Site.kakuyomu);

    await tester.tap(find.byKey(const Key('length-preset-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('文字数を指定').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('minimum-length-field')), findsOneWidget);
    expect(find.byKey(const Key('maximum-length-field')), findsOneWidget);
  });

  testWidgets('絞り込み条件を適用できる', (tester) async {
    SearchFilters? appliedFilters;

    await openFilterSheet(
      tester,
      site: Site.narou,
      onChanged: (filters) {
        appliedFilters = filters;
      },
    );

    await tester.tap(find.byKey(const Key('serial-status-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('短編').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('length-preset-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('短編（2万文字以下）').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('apply-search-filters')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(appliedFilters, isNotNull);
    expect(appliedFilters!.serialStatus, SearchSerialStatus.shortStory);
    expect(appliedFilters!.lengthPreset, SearchLengthPreset.short);
  });

  testWidgets('最小文字数が最大文字数を超える場合は拒否する', (tester) async {
    await openFilterSheet(tester, site: Site.narou);

    await tester.tap(find.byKey(const Key('length-preset-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('文字数を指定').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const Key('minimum-length-field')),
      '100001',
    );
    await tester.enterText(
      find.byKey(const Key('maximum-length-field')),
      '100000',
    );

    await tester.tap(find.byKey(const Key('apply-search-filters')));
    await tester.pump();

    expect(find.byKey(const Key('filter-validation-message')), findsOneWidget);
    expect(find.text('最小文字数は最大文字数以下にしてください'), findsOneWidget);
  });
}
