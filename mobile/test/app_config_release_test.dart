import 'package:flutter_test/flutter_test.dart';
import 'package:eldercare_mobile/config/app_config.dart';

/// Release builds must never silently target a developer machine: a shipped
/// binary pointed at localhost cannot reach real data, and an http:// URL
/// would send credentials in cleartext. These cases pin that contract against
/// the real resolver used by the app.
void main() {
  group('release configuration', () {
    test('refuses to build without an explicit API_BASE_URL', () {
      expect(
        () => resolveApiBaseUrl(configured: '', release: true),
        throwsStateError,
      );
    });

    test('refuses a whitespace-only API_BASE_URL', () {
      expect(
        () => resolveApiBaseUrl(configured: '   ', release: true),
        throwsStateError,
      );
    });

    test('refuses plain http', () {
      expect(
        () => resolveApiBaseUrl(
            configured: 'http://api.example.org', release: true),
        throwsStateError,
      );
    });

    test('refuses loopback and private addresses over https', () {
      for (final host in <String>[
        'https://localhost',
        'https://127.0.0.1',
        'https://10.0.2.2',
        'https://192.168.1.20',
        'https://10.1.2.3',
        'https://172.16.0.5',
        'https://172.31.255.1',
        'https://api.local',
      ]) {
        expect(
          () => resolveApiBaseUrl(configured: host, release: true),
          throwsStateError,
          reason: '$host must be rejected for a release build',
        );
      }
    });

    test('refuses a non-http scheme', () {
      expect(
        () => resolveApiBaseUrl(
            configured: 'ftp://api.example.org', release: true),
        throwsStateError,
      );
    });

    test('refuses a relative or malformed value', () {
      expect(
        () => resolveApiBaseUrl(configured: '/api', release: true),
        throwsStateError,
      );
    });

    test('accepts a public https URL and strips a trailing slash', () {
      expect(
        resolveApiBaseUrl(
            configured: 'https://api.example.org/', release: true),
        'https://api.example.org',
      );
    });

    test('accepts a public https URL with a path prefix', () {
      expect(
        resolveApiBaseUrl(
            configured: 'https://api.example.org/smriti', release: true),
        'https://api.example.org/smriti',
      );
    });

    test('accepts a public https host in the 172.32+ range', () {
      expect(
        resolveApiBaseUrl(configured: 'https://172.32.0.1', release: true),
        'https://172.32.0.1',
      );
    });
  });

  group('development configuration', () {
    test('falls back to localhost so `flutter run` works with no flags', () {
      expect(
        resolveApiBaseUrl(configured: '', release: false),
        'http://localhost:8000',
      );
    });

    test('accepts a plain http LAN address for on-device development', () {
      expect(
        resolveApiBaseUrl(
            configured: 'http://192.168.1.20:8000', release: false),
        'http://192.168.1.20:8000',
      );
    });

    test('accepts the Android emulator host alias in development', () {
      expect(
        resolveApiBaseUrl(
            configured: 'http://10.0.2.2:8000', release: false),
        'http://10.0.2.2:8000',
      );
    });

    test('honours an explicit development default (platform aware)', () {
      expect(
        resolveApiBaseUrl(
          configured: '',
          release: false,
          developmentDefault: 'http://10.0.2.2:8000',
        ),
        'http://10.0.2.2:8000',
      );
    });
  });

  test('apiV1 path prefix is stable', () {
    expect(AppConfig.apiV1, '/api/v1');
  });
}
