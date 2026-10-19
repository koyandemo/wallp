import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/core/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('no env file means production', () {
      final c = ApiConfig.fromValues(env: '', baseUrl: '');
      expect(c.env, ApiEnv.prod);
      expect(
        c.catalogBase.toString(),
        'https://wallp-api.justym.me/catalog/v1/',
      );
      expect(c.apiBase.toString(), 'https://wallp-api.justym.me/v1/');
    });

    test('adds the trailing slash and keeps a path prefix', () {
      final c = ApiConfig.fromValues(
        env: 'local',
        baseUrl: 'http://10.0.2.2:8080/wallp',
      );
      expect(
        c.catalogBase.toString(),
        'http://10.0.2.2:8080/wallp/catalog/v1/',
      );
    });

    test('rejects typos', () {
      expect(
        () => ApiConfig.fromValues(env: 'production', baseUrl: ''),
        throwsArgumentError,
      );
      expect(
        () => ApiConfig.fromValues(env: 'prod', baseUrl: 'wallp-api.justym.me'),
        throwsArgumentError,
      );
    });

    test('every env file parses', () {
      for (final f in Directory('env').listSync().whereType<File>()) {
        final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final c = ApiConfig.fromValues(
          env: m['WALLP_ENV'] as String,
          baseUrl: m['WALLP_API_BASE'] as String,
        );
        expect(f.path, endsWith('${c.env.name}.json'));
      }
    });
  });
}
