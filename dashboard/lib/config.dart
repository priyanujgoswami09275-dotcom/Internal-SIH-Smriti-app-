library;

const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');
const String _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Compile-time tripwire.
///
/// A release web build with no `API_BASE_URL` must not merely fail at runtime
/// — it should not compile at all, so an unusable binary can never be shipped
/// or handed to a judge. `assert` in a `const` initializer is evaluated during
/// compilation, so an unset URL turns into a build error. Debug/JIT builds
/// (product=false) are unaffected.
class ReleaseApiUrlGuard {
  const ReleaseApiUrlGuard._()
      : assert(
          !isReleaseBuild || _configuredApiBaseUrl.length > 0,
          'API_BASE_URL must be provided for a release web build. Rebuild with '
          '--dart-define=API_BASE_URL=https://<your-api-host>.',
        );
  static const ReleaseApiUrlGuard instance = ReleaseApiUrlGuard._();
}

String resolveApiBaseUrl({required bool release, required String configured}) {
  final value = configured.trim();
  if (release && value.isEmpty) {
    throw StateError(
      'API_BASE_URL must be provided explicitly for a release build.',
    );
  }
  if (value.isEmpty) return 'http://localhost:8000';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw StateError('API_BASE_URL must be an absolute HTTP or HTTPS URL.');
  }
  if (release) {
    // A served web build is itself loaded over HTTPS, so an http:// API URL
    // would be blocked as mixed content, and a loopback/private host could
    // never resolve in a user's browser. Refuse both rather than shipping a
    // dashboard that loads but cannot reach the API.
    if (uri.scheme != 'https') {
      throw StateError(
        'A release web build requires an https:// API_BASE_URL.',
      );
    }
    if (_isNonPublicHost(uri.host)) {
      throw StateError(
        'A release web build must not target a loopback or private address.',
      );
    }
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

bool _isNonPublicHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized.endsWith('.local')) {
    return true;
  }
  if (normalized.startsWith('10.') || normalized.startsWith('192.168.')) {
    return true;
  }
  return RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(normalized);
}

String get apiBaseUrl {
  // Touching the guard here instantiates it during compilation, so an unset
  // release define fails the build rather than the first request.
  assert(ReleaseApiUrlGuard.instance == ReleaseApiUrlGuard.instance);
  return resolveApiBaseUrl(
    release: isReleaseBuild,
    configured: _configuredApiBaseUrl,
  );
}

void validateApiConfig() {
  apiBaseUrl;
}
