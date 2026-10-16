import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/core/app_version.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';
import 'package:wallp/dev/dev_settings.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('DevSettings', () {
    test('network and date survive a restart', () async {
      final dev = DevSettings(enabled: true);
      await dev.load();
      await dev.setNetwork('slow');
      await dev.setPretendToday(DateTime(2026, 12, 20, 15, 30));

      final again = DevSettings(enabled: true);
      await again.load();
      expect(again.network, 'slow');
      expect(again.conditions, same(NetworkConditions.slow));
      expect(again.pretendToday, DateTime(2026, 12, 20));
    });

    test('the live clock follows the setting without being replaced', () async {
      final dev = DevSettings(enabled: true);
      await dev.load();
      final clock = dev.liveClock;
      await dev.setPretendToday(DateTime(2026, 12, 24));
      expect(clock.now().day, 24);
      await dev.setPretendToday(null);
      expect(clock.now().day, DateTime.now().day);
    });

    test('release builds ignore every switch', () async {
      final dev = DevSettings(enabled: true);
      await dev.load();
      await dev.setNetwork('offline');
      await dev.setPretendToday(DateTime(2030));

      final release = DevSettings(enabled: false);
      await release.load();
      expect(release.conditions, same(NetworkConditions.fast));
      expect(release.pretendToday, isNull);
      expect(release.clock, isA<SystemClock>());
    });

    test('an unknown saved preset falls back to fast', () async {
      await DevSettings(enabled: true).setNetwork('flaky');
      expect(
        () => DevSettings(enabled: true).setNetwork('warp'),
        throwsArgumentError,
      );
    });

    test('load() runs once however often it is called', () async {
      final dev = DevSettings(enabled: true);
      expect(identical(dev.load(), dev.load()), isTrue);
    });
  });

  test('a shifted clock keeps the real time of day', () {
    final base = FixedClock(DateTime(2026, 10, 16, 19, 47, 5));
    final shifted = ShiftedClock(DateTime(2026, 12, 25), base: base);
    expect(shifted.now(), DateTime(2026, 12, 25, 19, 47, 5));
  });

  group('app version', () {
    test('matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*([0-9.]+)',
        multiLine: true,
      ).firstMatch(pubspec)![1];
      expect(appVersion, version);
    });

    test('compares numerically, part by part', () {
      expect(compareVersions('1.10.0', '1.9.2'), 1);
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.0.0+7', '1.0.0'), 0);
      expect(compareVersions('0.9.9', '1.0.0'), -1);
      expect(meetsVersion('1.2.0', '1.2.0'), isTrue);
      expect(meetsVersion('1.2.1', '1.2.0'), isFalse);
    });
  });
}
