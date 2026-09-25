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

  static const Set<String> hardUnsupported = {'garo'};

  static bool available(String code, Set<String>? providerLanguages) {
    if (hardUnsupported.contains(code)) return false;
    return providerLanguages == null || providerLanguages.contains(code);
  }

  static bool availableForOperation(
    String code,
    String operation,
    LanguageCapabilityStatus? capabilities,
  ) {
    if (hardUnsupported.contains(code)) return false;
    return capabilities?.supports(operation, code) ?? false;
  }
}

class LanguageCapabilityStatus {
  LanguageCapabilityStatus({
    required this.provider,
    required this.asrLanguages,
    required this.nmtLanguages,
    required this.ttsLanguages,
    required this.capabilitiesKnown,
    required this.simulated,
  });

  final String provider;
  final Set<String> asrLanguages;
  final Set<String> nmtLanguages;
  final Set<String> ttsLanguages;
  final bool capabilitiesKnown;
  final bool simulated;

  factory LanguageCapabilityStatus.fromJson(Map<String, dynamic> json) {
    final capabilities = json['capabilities'];
    final known = capabilities is Map;
    String providerOf(String operation) {
      if (!known) return 'unknown';
      final value = capabilities[operation];
      return value is Map ? '${value['provider'] ?? 'unknown'}' : 'unknown';
    }

    Set<String> languagesOf(String operation) {
      if (!known) return const <String>{};
      final value = capabilities[operation];
      if (value is! Map || value['languages'] is! List) return const <String>{};
      return (value['languages'] as List)
          .map((item) => item.toString().toLowerCase())
          .toSet();
    }

    return LanguageCapabilityStatus(
      provider: '${json['provider'] ?? 'unknown'}',
      asrLanguages: languagesOf('asr'),
      nmtLanguages: languagesOf('nmt'),
      ttsLanguages: languagesOf('tts'),
      capabilitiesKnown: known,
      simulated: known &&
          ['asr', 'nmt', 'tts']
              .any((operation) => providerOf(operation) == 'mock'),
    );
  }

  bool supports(String operation, String languageCode) {
    if (!capabilitiesKnown || simulated) return false;
    final languages = switch (operation) {
      'asr' => asrLanguages,
      'nmt' => nmtLanguages,
      'tts' => ttsLanguages,
      _ => const <String>{},
    };
    return languages.contains(languageCode.toLowerCase());
  }

  bool get hasMockProvider => provider.toLowerCase() == 'mock' || simulated;
}
