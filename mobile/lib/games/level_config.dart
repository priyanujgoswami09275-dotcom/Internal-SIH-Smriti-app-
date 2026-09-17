/// Level config — mobile mirror of the backend game_level_config table.
///
/// The server is the single source of truth. [LevelConfig.refresh] pulls
/// GET /games/level-config at game start, caches it in SharedPreferences,
/// and installs it as [LevelConfig.current]; offline play falls back to the
/// last cache, then to [bundled] (which mirrors the server seeds and is
/// pinned by level_config_test + the backend matrix test together).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class LevelConfig {
  final Map<String, Map<int, Map<String, Object>>> _games;

  const LevelConfig(this._games);

  /// Bundled canonical grids (mirror of the server seeds — change only
  /// together with level_config_service.DEFAULT_LEVEL_CONFIG).
  static const LevelConfig bundled = LevelConfig({
    'match_it': {
      1: {'pairs': 2, 'grid': '2x2', 'target_seconds': 90},
      2: {'pairs': 4, 'grid': '4x2', 'target_seconds': 150},
      3: {'pairs': 6, 'grid': '4x3', 'target_seconds': 240},
    },
    'routine_sequencing': {
      1: {'steps': 3, 'hints': true, 'icons': true, 'target_seconds': 45},
      2: {'steps': 4, 'hints': true, 'icons': true, 'target_seconds': 70},
      3: {'steps': 6, 'hints': false, 'icons': true, 'target_seconds': 120},
    },
  });

  static LevelConfig _current = bundled;

  /// Active config: server-synced after [refresh], bundled until then.
  static LevelConfig get current => _current;

  static const String prefsKey = 'smriti_level_config_v1';

  /// Pull the server map, cache it, install as current. Never throws —
  /// offline play falls back to cache, then bundled.
  static Future<void> refresh(ApiService api) async {
    try {
      final data = await api.fetchLevelConfig();
      final parsed = LevelConfig.fromServerJson(
        (data['config'] as Map).cast<String, dynamic>(),
      );
      _current = parsed;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefsKey, jsonEncode(data['config']));
      } catch (_) {}
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(prefsKey);
        if (raw != null) {
          _current = LevelConfig.fromServerJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>(),
          );
          return;
        }
      } catch (_) {}
      _current = bundled;
    }
  }

  factory LevelConfig.fromServerJson(Map<String, dynamic> json) {
    final games = <String, Map<int, Map<String, Object>>>{};
    json.forEach((game, levels) {
      final byLevel = <int, Map<String, Object>>{};
      (levels as Map).forEach((level, params) {
        byLevel[int.parse(level.toString())] =
            Map<String, Object>.from(params as Map);
      });
      games[game] = byLevel;
    });
    return LevelConfig(games);
  }

  Map<String, Object> _params(String game, int level) =>
      _games[game]?[level] ??
      bundled._games[game]?[level] ??
      const <String, Object>{};

  int matchPairs(int level) =>
      (_params('match_it', level)['pairs'] as num?)?.toInt() ?? 2;

  int routineSteps(int level) =>
      (_params('routine_sequencing', level)['steps'] as num?)?.toInt() ?? 3;

  bool routineHints(int level) =>
      _params('routine_sequencing', level)['hints'] as bool? ?? level <= 2;

  bool routineIcons(int level) =>
      _params('routine_sequencing', level)['icons'] as bool? ?? true;

  int targetSeconds(String game, int level) =>
      (_params(game, level)['target_seconds'] as num?)?.toInt() ?? 60;
}
