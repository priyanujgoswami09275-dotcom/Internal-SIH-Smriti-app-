import '../patient_localizations.dart';

class GameLabels {
  GameLabels._();

  static const String fallbackLanguage = 'en';

  static String of(String languageCode, String key) =>
      PatientLocalizations.forLanguage(languageCode, key);
}
