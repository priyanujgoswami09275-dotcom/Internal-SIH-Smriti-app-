import 'package:flutter/material.dart';

import '../../../theme/monad_theme.dart';
import '../../../widgets/monad/monad_pill_button.dart';

class AlertsCard extends StatelessWidget {
  const AlertsCard({
    super.key,
    required this.summary,
    required this.onAcknowledge,
  });

  final Map<String, dynamic> summary;
  final Future<void> Function(String alertId) onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final alerts = summary['active_alerts'] as List? ?? const [];
    final flags = summary['clinical_flags'] as Map<String, dynamic>? ?? const {};
    final drop = flags['cognitive_drop_detected'] == true;
    final missed = flags['high_missed_reminders'] == true;
    if (alerts.isEmpty && flags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (alerts.isNotEmpty) ...[
          ...alerts.map((a) {
            final map = a as Map<String, dynamic>;
            final critical =
                map['severity'] == 'critical' || map['severity'] == 'warning';
            final tint =
                critical ? Monad.tintCoral : Monad.tintGold;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              // Alert card: tint fill + 1px ash hairline, no shadow
              // (only game faces + status chips get elevation).
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(Monad.radiusCard),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _chip(
                    label: (map['severity'] as String? ?? 'notice'),
                    icon: critical
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    tint: Monad.parchment,
                  ),
                  const SizedBox(height: 10),
                  Text(map['summary'] as String? ?? 'Risk alert',
                      style: Monad.patientBody),
                  const SizedBox(height: 4),
                  Text('Type: ${map['trigger_type']}',
                      style: Monad.monoBodySm),
                  const SizedBox(height: 12),
                  MonadPillButton(
                    label: 'Resolve',
                    variant: MonadPillVariant.secondary,
                    onPressed: () => onAcknowledge(map['id'] as String),
                  ),
                ],
              ),
            );
          }),
        ],
        // Threshold flags — exactly as the backend computes them, surfaced
        // as one elevated periwinkle banner.
        if (drop || missed)
          Container(
            decoration: BoxDecoration(
              color: Monad.periwinkleMist,
              borderRadius: BorderRadius.circular(Monad.radiusCard),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (drop)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.trending_down,
                        color: Monad.crimson, size: 32),
                    title: Text('Cognitive drop detected (<60% accuracy)',
                        style: Monad.patientBody),
                  ),
                if (missed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_off,
                        color: Monad.crimson, size: 32),
                    title: Text('3+ missed reminders in 7 days',
                        style: Monad.patientBody),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Pill status chip: tinted fill + icon + uppercase label. Chips are one
  /// of the two surfaces allowed the ambient shadow (DESIGN.md amendment).
  Widget _chip({required String label, required IconData icon, required Color tint}) {
    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(Monad.radiusPill),
        boxShadow: Monad.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Monad.offBlack),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: Monad.monoCaption.copyWith(color: Monad.offBlack)),
        ],
      ),
    );
  }
}
