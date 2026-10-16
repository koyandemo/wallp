/// This build's version, for the catalog's `minAppVersion` checks.
///
/// Kept in step with `version:` in pubspec.yaml by test/app_version_test.dart.
const appVersion = '1.0.0';

/// Compares dotted versions numerically: `1.10.0` is newer than `1.9.2`.
/// Missing parts count as 0, and anything after `+` or `-` is ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.split(RegExp('[+-]')).first.split('.'))
      int.tryParse(p) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Whether this build is at least [minVersion].
bool meetsVersion(String minVersion, [String current = appVersion]) =>
    compareVersions(current, minVersion) >= 0;
