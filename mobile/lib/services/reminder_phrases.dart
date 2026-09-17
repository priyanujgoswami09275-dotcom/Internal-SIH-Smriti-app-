/// Spoken reminder phrases — short, calm, elder-appropriate.
///
/// Presentation-layer only: the reminder type comes from the schedule, the
/// language from the patient's preference. Unknown languages fall back to
/// English (never an empty string — TTS must always have text to speak).
library;

import '../models/shared_models.dart';

/// Spoken text for [type] in [language] (assamese/bengali/hindi/english,
/// English fallback for anything else).
String reminderPhrase(ReminderType type, String language) {
  switch (language.toLowerCase()) {
    case 'assamese':
      switch (type) {
        case ReminderType.medicine:
          return 'ঔষধ খোৱাৰ সময় হৈছে';
        case ReminderType.water:
          return 'পানী খোৱাৰ সময় হৈছে';
        case ReminderType.food:
          return 'আহাৰ খোৱাৰ সময় হৈছে';
        case ReminderType.exercise:
          return 'লঘু ব্যায়ামৰ সময় হৈছে';
      }
    case 'bengali':
      switch (type) {
        case ReminderType.medicine:
          return 'ওষুধ খাওয়ার সময় হয়েছে';
        case ReminderType.water:
          return 'পানি খাওয়ার সময় হয়েছে';
        case ReminderType.food:
          return 'খাবার খাওয়ার সময় হয়েছে';
        case ReminderType.exercise:
          return 'হালকা ব্যায়ামের সময় হয়েছে';
      }
    case 'hindi':
      switch (type) {
        case ReminderType.medicine:
          return 'दवाई लेने का समय हो गया है';
        case ReminderType.water:
          return 'पानी पीने का समय हो गया है';
        case ReminderType.food:
          return 'खाना खाने का समय हो गया है';
        case ReminderType.exercise:
          return 'हल्की कसरत का समय हो गया है';
      }
    case 'english':
      break;
    default:
      break;
  }
  switch (type) {
    case ReminderType.medicine:
      return 'Time to take your medicine';
    case ReminderType.water:
      return 'Time to drink some water';
    case ReminderType.food:
      return 'Time for your meal';
    case ReminderType.exercise:
      return 'Time for some light movement';
  }
}
