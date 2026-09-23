import 'package:flutter/material.dart';

import '../../../theme/monad_theme.dart';
import '../../../widgets/trend_chart.dart';

class TrendsSection extends StatelessWidget {
  const TrendsSection({super.key, required this.summary});

  final Map<String, dynamic> summary;

  /// 14-day sparklines — same daily_trends array the web charts render.
  /// Server strips it for basic tier, so basic caregivers see the note.
  @override
  Widget build(BuildContext context) {
    final trends = (summary['daily_trends'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (trends.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Monad.tintGold,
          borderRadius: BorderRadius.circular(Monad.radiusMin),
          border: Border.all(color: Monad.ash, width: 1),
        ),
        child: const Row(children: [
          Icon(Icons.lock_outline, size: 22, color: Monad.graphite),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Basic view — accuracy and response-time trends are visible '
              'to linked clinical staff only.',
              style: Monad.monoBodySm,
            ),
          ),
        ]),
      );
    }
    final acc = trends
        .map((t) => (t['accuracy_pct'] as num?)?.toDouble())
        .toList();
    final rt = trends
        .map((t) => (t['avg_response_time_ms'] as num?)?.toDouble())
        .toList();
    return Column(
      children: [
        TrendChart(
            values: acc,
            title: 'Accuracy trend (14d)',
            subtitle: '% per active day'),
        const SizedBox(height: 12),
        TrendChart(
            values: rt,
            title: 'Response time trend (14d)',
            subtitle: 'ms per active day'),
      ],
    );
  }
}
