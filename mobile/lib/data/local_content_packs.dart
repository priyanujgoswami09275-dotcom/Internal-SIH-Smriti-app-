/// Offline NER Match It packs — same themes as the backend seed, so the game
/// is fully playable with no network. Cards use multilingual labels (the
/// Flutter UI already renders text cards rather than missing PNGs).
library;

import 'dart:math';

import '../games/level_config.dart';
import '../models/game_models.dart';
import '../models/shared_models.dart';

class LocalContentPacks {
  static final _rng = Random();

  static const List<ContentPackSummary> summaries = [
    ContentPackSummary(
      id: 'festivals_ner',
      name: 'NER Festivals & Celebrations',
      region: 'North East India',
      description: 'Traditional festivals across the 8 northeastern states.',
      itemCount: 10,
    ),
    ContentPackSummary(
      id: 'fruits_flora_ner',
      name: 'NER Fruits & Flora',
      region: 'North East India',
      description: 'Indigenous fruits and plants familiar to NER elders.',
      itemCount: 10,
    ),
    ContentPackSummary(
      id: 'heritage_household_ner',
      name: 'Heritage & Household Objects',
      region: 'North East India',
      description: 'Everyday traditional items and symbols of the North East.',
      itemCount: 12,
    ),
  ];

  static const Map<String, List<Map<String, String>>> _items = {
    'festivals_ner': [
      {'id': 'bihu', 'en': 'Rongali Bihu', 'as': 'ৰঙালী বিহু'},
      {'id': 'hornbill', 'en': 'Hornbill Festival', 'as': 'হৰ্ণবিল মহোৎসৱ'},
      {'id': 'chapchar_kut', 'en': 'Chapchar Kut', 'as': 'চাপচাৰ কুট'},
      {'id': 'nongkrem', 'en': 'Nongkrem Dance', 'as': 'নংক্রেম নৃত্য'},
      {'id': 'losar', 'en': 'Losar', 'as': 'লোচাৰ'},
      {'id': 'sangken', 'en': 'Sangken Water Festival', 'as': 'চাংকেন'},
      {'id': 'wangala', 'en': 'Wangala 100 Drums', 'as': 'ৱাংগালা'},
      {'id': 'moatsu', 'en': 'Moatsu Festival', 'as': 'মোৱাতচু'},
      {'id': 'dree', 'en': 'Dree Festival', 'as': 'ড্ৰী উৎসৱ'},
      {'id': 'ningol_chakouba', 'en': 'Ningol Chakouba', 'as': 'নিঙল চাকৌবা'},
    ],
    'fruits_flora_ner': [
      {'id': 'kaji_nemu', 'en': 'Kaji Nemu (Assam Lemon)', 'as': 'কাজী নেমু'},
      {'id': 'bhut_jolokia', 'en': 'Bhut Jolokia', 'as': 'ভূত জলকীয়া'},
      {'id': 'ou_tenga', 'en': 'Ou Tenga', 'as': 'ঔ টেঙা'},
      {'id': 'jolpai', 'en': 'Jolpai (Indian Olive)', 'as': 'জলফাই'},
      {'id': 'bamboo_shoot', 'en': 'Khorisa / Bamboo Shoot', 'as': 'খৰিচা'},
      {'id': 'lakadong', 'en': 'Lakadong Turmeric', 'as': 'লাকাডং হালধি'},
      {'id': 'starfruit', 'en': 'Kordoi (Starfruit)', 'as': 'কৰ্দৈ'},
      {'id': 'tamul_pan', 'en': 'Tamul-Paan', 'as': 'তামোল-পাণ'},
      {'id': 'kopou', 'en': 'Kopou Phool', 'as': 'কপৌ ফুল'},
      {'id': 'assam_tea_leaf', 'en': 'Assam Tea Leaf', 'as': 'চাহ পাত'},
    ],
    'heritage_household_ner': [
      {'id': 'jaapi', 'en': 'Jaapi', 'as': 'জাপি'},
      {'id': 'xorai', 'en': 'Xorai', 'as': 'শৰাই'},
      {'id': 'gamosa', 'en': 'Gamosa', 'as': 'গামোচা'},
      {'id': 'rhino', 'en': 'One-Horned Rhino', 'as': 'এশিঙীয়া গঁড়'},
      {'id': 'red_panda', 'en': 'Red Panda', 'as': 'ৰেড পাণ্ডা'},
      {'id': 'dhol', 'en': 'Bihu Dhol', 'as': 'বিহু ঢোল'},
      {'id': 'pepa', 'en': 'Pepa', 'as': 'পেঁপা'},
      {'id': 'mekhela', 'en': 'Mekhela Sador', 'as': 'মেখেলা চাদৰ'},
      {'id': 'puan', 'en': 'Mizo Puan', 'as': 'পুৱান'},
      {'id': 'eri_silk', 'en': 'Eri Silk', 'as': 'এৰি পাট'},
      {'id': 'bamboo_craft', 'en': 'Bamboo Craft', 'as': 'বাঁহৰ শিল্প'},
      {'id': 'naga_shawl', 'en': 'Naga Shawl', 'as': 'নাগা চাদৰ'},
    ],
  };

  /// Offline board. Pair count comes from [LevelConfig] (server-synced
  /// via refresh at game start, bundled fallback offline).
  static MatchItBoard board(
    String packId,
    int difficultyLevel,
    String packName, [
    LevelConfig? levels,
  ]) {
    // Canonical grids: L1 = 2x2 (2 pairs), L2 = 4x2 (4 pairs),
    // L3 = 4x3 (6 pairs) built from VISUALLY RELATED pairs so "harder"
    // is concrete (textiles vs textiles, instruments vs instruments).
    final pairCount =
        (levels ?? LevelConfig.bundled).matchPairs(difficultyLevel);
    final source = List<Map<String, String>>.from(
      _items[packId] ?? _items['festivals_ner']!,
    )..shuffle(_rng);

    List<Map<String, String>> selected;
    if (difficultyLevel == 3) {
      // Hard mode: prefer semantically related clusters first.
      const relatedIds = [
        'gamosa', 'mekhela', 'puan', 'naga_shawl', // textiles
        'dhol', 'pepa', // instruments
      ];
      final related = source.where((i) => relatedIds.contains(i['id'])).toList();
      related.shuffle(_rng);
      selected = related.take(pairCount).toList();
      if (selected.length < pairCount) {
        final rest = source.where((i) => !relatedIds.contains(i['id'])).toList();
        selected.addAll(rest.take(pairCount - selected.length));
      }
    } else {
      selected = source.take(pairCount).toList();
    }

    final cards = <MatchItCard>[];
    var n = 1;
    for (final item in selected) {
      for (var copy = 0; copy < 2; copy++) {
        cards.add(MatchItCard(
          id: '$n',
          pairId: item['id']!,
          imageKey: item['id']!,
          labelEn: item['en']!,
          labelLocal: item['as'] ?? item['en']!,
        ));
        n++;
      }
    }
    cards.shuffle(_rng);
    return MatchItBoard(
      packId: packId,
      packName: packName,
      difficultyLevel: difficultyLevel,
      pairCount: pairCount,
      totalCards: cards.length,
      cards: cards,
      generatedAt: DateTime.now(),
    );
  }

  static RoutineBoard defaultRoutineBoard({
    int difficultyLevel = 1,
    LevelConfig? levels,
  }) {
    const steps = [
      RoutineStep(stepId: 'wake', order: 1, time: '06:30', titleEn: 'Wake up', titleAs: 'শুই উঠা', icon: 'wb_sunny'),
      RoutineStep(stepId: 'brush', order: 2, time: '06:45', titleEn: 'Brush teeth', titleAs: 'দাঁত ঘঁহা', icon: 'brush'),
      RoutineStep(stepId: 'tea', order: 3, time: '07:00', titleEn: 'Morning Bihu Tea', titleAs: 'পুৱাৰ বিহু চাহ', icon: 'local_cafe'),
      RoutineStep(stepId: 'meds', order: 4, time: '08:00', titleEn: 'Take medicine', titleAs: 'ঔষধ লোৱা', icon: 'medication'),
      RoutineStep(stepId: 'bath', order: 5, time: '09:30', titleEn: 'Bathing', titleAs: 'গা ধোৱা', icon: 'shower'),
      RoutineStep(stepId: 'dress', order: 6, time: '09:45', titleEn: 'Dress in Traditional Attire', titleAs: 'পৰম্পৰাগত পোছাক', icon: 'checkroom'),
    ];
    // Canonical: L1 = 3 steps, L2 = 4 steps, L3 = 6 steps (fewer hints).
    final count =
        (levels ?? LevelConfig.bundled).routineSteps(difficultyLevel);
    final chosen = steps.take(count).toList();
    final shuffled = List<RoutineStep>.from(chosen)..shuffle(_rng);
    return RoutineBoard(
      difficultyLevel: difficultyLevel,
      stepCount: chosen.length,
      hasHints: difficultyLevel <= 2, // L3: fewer free hints
      hasIcons: true,
      shuffledItems: shuffled,
      correctSequence: chosen.map((s) => s.stepId).toList(),
    );
  }
}
