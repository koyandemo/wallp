import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/launcher/home_arrangement.dart';

void main() {
  HomeArrangement make(
    List<List<String>> pages, [
    List<String> dock = const [],
  ]) => HomeArrangement(pages: pages, dock: dock);

  test('moves an app within a page', () {
    final a = make([
      ['a', 'b', 'c', 'd'],
    ]);
    expect(a.move('d', const SlotRef.page(0, 0)).pages, [
      ['d', 'a', 'b', 'c'],
    ]);
  });

  test('moves an app into the dock, and ignores a full dock', () {
    final a = make(
      [
        ['a', 'b'],
      ],
      ['x', 'y', 'z'],
    );
    final moved = a.move('a', const SlotRef.dock(1));
    expect(moved.dock, ['x', 'a', 'y', 'z']);
    expect(moved.pages.first, ['b']);
    expect(moved.move('b', const SlotRef.dock(0)), moved);
  });

  test('a full page pushes its last app to the next page', () {
    final full = [for (var i = 0; i < HomeArrangement.pageSlots; i++) 'p$i'];
    final a = make([full], ['new']);
    final moved = a.move('new', const SlotRef.page(0, 0));
    expect(moved.pages, hasLength(2));
    expect(moved.pages[0].first, 'new');
    expect(moved.pages[0], hasLength(HomeArrangement.pageSlots));
    expect(moved.pages[1], ['p15']);
    expect(moved.dock, isEmpty);
  });

  test('add uses the first page with room and skips duplicates', () {
    final full = [for (var i = 0; i < HomeArrangement.pageSlots; i++) 'p$i'];
    final a = make([full, []]);
    expect(a.add('n').pages[1], ['n']);
    expect(a.add('p3'), a);
  });

  test('removing, pruning and dropping empty pages', () {
    final a = make(
      [
        ['a'],
        [],
        ['b', 'gone'],
      ],
      ['gone', 'c'],
    );
    expect(a.remove('a').withoutEmptyPages().pages, [
      ['b', 'gone'],
    ]);
    final pruned = a.retainInstalled({'a', 'b', 'c'});
    expect(pruned.dock, ['c']);
    expect(pruned.pages[2], ['b']);
    expect(make([[]]).withoutEmptyPages().pages, [<String>[]]);
  });

  test('HomeStore saves and loads the arrangement', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = HomeStore();
    expect(await store.load(), isNull);
    final a = make(
      [
        ['a', 'b'],
        ['c'],
      ],
      ['d'],
    );
    await store.save(a);
    expect(await store.load(), a);
  });
}
