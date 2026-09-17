/// Voice picker languages — mobile mirror of the backend provider dicts.
///
/// Canonical names match the backend (`manipuri`, never `meitei`, as the
/// request key); the display label keeps "Meitei (Manipuri)" for elders.
/// [hardUnsupported] lists picker entries no backend provider covers (Garo):
/// they render as "not yet available" unconditionally — even when the
/// provider set is unknown (offline) — so the UI never offers a language
/// that fails when selected.
library;

class VoiceLanguages {
  static const Map<String, String> displayNames = {
    'assamese': 'অসমীয়া',
    'bengali': 'বাংলা',
    'hindi': 'हिन्दी',
    'english': 'English',
    'mizo': 'Mizo',
    'manipuri': 'Meitei (Manipuri)',
    'khasi': 'Khasi',
    'bodo': 'Bodo',
    'garo': 'Garo',
    'nepali': 'Nepali',
  };

  static const Map<String, String> inputHints = {
    'assamese': 'বার্তা লিখক…',
    'bengali': 'একটি বার্তা লিখুন…',
    'hindi': 'एक संदेश लिखें…',
    'english': 'Type a message…',
    'mizo': 'Message emai…',
    'manipuri': 'Message ei chaba…',
    'khasi': 'Nongsain ka jingiew…',
    'bodo': 'Message jawabo…',
    'garo': 'Message gnaty e…',
    'nepali': 'Sandaitha…',
  };

  /// Picker entries with no provider code on any backend (see
  /// language_service.py: do not add Garo there until a provider covers it).
  static const Set<String> hardUnsupported = {'garo'};

  /// Whether [code] may be selected: never for hard-unsupported entries,
  /// otherwise gated by the active provider set (null = unknown/offline,
  /// everything else stays enabled as before).
  static bool available(String code, Set<String>? providerLanguages) {
    if (hardUnsupported.contains(code)) return false;
    return providerLanguages == null || providerLanguages.contains(code);
  }
}
