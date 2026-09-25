library;

const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');
const String _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

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
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String get apiBaseUrl => resolveApiBaseUrl(
      release: isReleaseBuild,
      configured: _configuredApiBaseUrl,
    );

void validateApiConfig() {
  apiBaseUrl;
}
