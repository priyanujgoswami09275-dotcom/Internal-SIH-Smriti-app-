import 'package:flutter/material.dart';

import '../../../theme/monad_theme.dart';

class MetricsTiles extends StatelessWidget {
  const MetricsTiles({super.key, required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final isClinical = summary['view'] == 'clinical';
    final compliance = (summary['compliance_pct'] as num? ?? 0).toDouble();
    final games = summary['games_played'] as int? ?? 0;
    final ack = summary['reminders_acknowledged'] as int? ?? 0;
    final total = summary['reminders_total'] as int? ?? 0;
    final missed = summary['reminders_missed'] as int? ?? 0;
    final tiles = <Widget>[
      if (isClinical)
        _tile(
          'Cognitive accuracy',
          '${((summary['accuracy_pct'] as num? ?? 0) as double).toStringAsFixed(0)}%',
          '$games games (7d)',
          Icons.psychology,
          Monad.tintSky,
        ),
      _tile('Compliance', '${compliance.toStringAsFixed(0)}%',
          '$ack/$total acknowledged', Icons.alarm_on, Monad.tintMint),
      _tile('Missed', '$missed', 'last 7 days', Icons.event_busy,
          missed > 0 ? Monad.tintCoral : Monad.tintGold),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: tiles,
    );
  }

  Widget _tile(
      String title, String value, String subtitle, IconData icon, Color tint) {
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(Monad.radiusMin),
              ),
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Monad.offBlack, size: 22),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: Monad.headingSm.copyWith(fontSize: 32),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(title.toUpperCase(),
                style: Monad.monoCaption, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: Monad.monoCaption),
          ],
        ),
      ),
    );
  }
}
