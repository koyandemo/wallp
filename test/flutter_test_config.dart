import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/data/catalog/built_in_catalog.dart';

/// Runs before every test file.
///
/// The built-in catalog is read from the asset bundle; inside testWidgets'
/// fake clock that read never finishes. Reading it once here, for real,
/// lets every later use finish at once.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await BuiltInCatalog.shared.preload();
  await testMain();
}
