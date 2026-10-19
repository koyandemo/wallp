import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wallp/core/app_theme.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/catalog/catalog_poller.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/catalog_store.dart';
import 'package:wallp/store/widgets/update_banner.dart';

import 'fakes.dart';

/// Counts manifest checks; answers "offline" (a check is a check).
class _CountingSource extends CatalogSource {
  int manifests = 0;

  @override
  Stream<List<int>> open(String path) async* {
    if (path == 'manifest.json') manifests++;
    throw CatalogFetchException(FetchFailure.offline, path);
  }
}

/// Moves with the test's fake time.
class _Clock implements Clock {
  _Clock(this.tester);

  final WidgetTester tester;
  final _start = DateTime.utc(2026, 10, 18, 9);

  @override
  DateTime now() => _start.add(tester.binding.clock.now().difference(_t0));
  late final DateTime _t0 = tester.binding.clock.now();
}

void main() {
  group('CatalogPoller', () {
    late _CountingSource source;
    late CatalogRepository repo;
    late CatalogPoller poller;

    Future<void> setUpPoller(WidgetTester tester) async {
      source = _CountingSource();
      repo = CatalogRepository(
        source: source,
        store: MemoryCatalogStore(),
        clock: _Clock(tester),
      );
      poller = CatalogPoller(repo)..start();
      await tester.pumpWidget(const SizedBox());
    }

    void goTo(WidgetTester tester, List<AppLifecycleState> states) {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    }

    const away = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const back = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    testWidgets('checks every 5 minutes while open', (tester) async {
      await setUpPoller(tester);
      await tester.pump(const Duration(minutes: 4));
      expect(source.manifests, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(source.manifests, 1);
      await tester.pump(const Duration(minutes: 10));
      expect(source.manifests, 3);
      // Before the test ends: testWidgets fails on a pending timer.
      poller.dispose();
    });

    testWidgets('stops while hidden', (tester) async {
      await setUpPoller(tester);
      await tester.pump(const Duration(minutes: 5));
      expect(source.manifests, 1);
      goTo(tester, away);
      expect(poller.isRunning, isFalse);
      await tester.pump(const Duration(minutes: 30));
      expect(source.manifests, 1);
      goTo(tester, back);
      await tester.pump();
      // Over 5 minutes since the last check: once at once.
      expect(source.manifests, 2);
      expect(poller.isRunning, isTrue);
      // Before the test ends: testWidgets fails on a pending timer.
      poller.dispose();
    });

    testWidgets('a quick trip away does not check again', (tester) async {
      await setUpPoller(tester);
      await tester.pump(const Duration(minutes: 5));
      goTo(tester, away);
      await tester.pump(const Duration(minutes: 1));
      goTo(tester, back);
      await tester.pump();
      expect(source.manifests, 1);
      // Before the test ends: testWidgets fails on a pending timer.
      poller.dispose();
    });
  });

  group('UpdateBanner', () {
    setUp(() => UpdateBanner.dismissed.value = false);

    Future<CatalogRepository> pumpBanner(
      WidgetTester tester, {
      required String appVersion,
    }) async {
      late CatalogRepository repo;
      await tester.runAsync(() async {
        repo = CatalogRepository(
          source: fixtureSource(),
          store: MemoryCatalogStore(),
          bundle: DiskBundle(),
          appVersion: appVersion,
        );
        await repo.start(refresh: false);
        await repo.refresh();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: repo,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: UpdateBanner()),
          ),
        ),
      );
      return repo;
    }

    testWidgets('hidden when this build is new enough', (tester) async {
      await pumpBanner(tester, appVersion: '9.0.0');
      expect(find.text('A newer wallp is out'), findsNothing);
    });

    testWidgets('an old build is told, softly, and can say Later', (
      tester,
    ) async {
      final repo = await pumpBanner(tester, appVersion: '0.9.0');
      expect(repo.updateRecommended, isTrue);
      expect(find.text('A newer wallp is out'), findsOneWidget);
      expect(
        find.textContaining('Update to see ${repo.hiddenForUpdate} more'),
        findsOneWidget,
      );
      await tester.tap(find.text('Later'));
      await tester.pump();
      expect(find.text('A newer wallp is out'), findsNothing);
    });
  });
}
