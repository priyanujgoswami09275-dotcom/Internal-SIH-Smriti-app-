/// Risk-screening display card (mobile caregiver dashboard).
///
/// Experimental preliminary screening — never a clinical diagnosis.
/// Uses Monad tokens; handles not_assessed / model_unavailable gracefully.
library;

import 'package:flutter/material.dart';

import '../theme/monad_theme.dart';

class RiskScreeningCard extends StatelessWidget {
  /// Response from POST/GET /patients/{id}/risk-screening, or null.
  final Map<String, dynamic>? result;
  const RiskScreeningCard({super.key, this.result});

  @override
  Widget build(BuildContext context) {
    if (result == null || result!.isEmpty) {
      return Card(
        elevation: 0,
        shape: Monad.cardShape,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Monad.radiusCard),
            color: Monad.parchment,
            boxShadow: Monad.cardShadow,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.health_and_safety, color: Monad.indigo, size: 24),
                const SizedBox(width: 8),
                // Expanded: title wraps at textScale 1.3 instead of
                // overflowing the Row on a 390px phone.
                const Expanded(
                  child: Text('COGNITIVE RISK SCREENING', style: Monad.monoLabel),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Not assessed yet',
                  style: Monad.subheading
                      .copyWith(fontSize: 18, color: Monad.graphite)),
              const SizedBox(height: 6),
              Text(
                'Run the 32-input experimental screening to record a preliminary score for this patient.',
                style: Monad.monoBodySm.copyWith(color: Monad.graphite),
              ),
              const SizedBox(height: 4),
              Text(
                'Experimental — not clinically validated.',
                style: Monad.monoCaption.copyWith(color: Monad.terracotta),
              ),
            ],
          ),
        ),
      );
    }

    final status = result?['status'] as String?;
    final ok = status == 'ok';

    Color tierColor = Monad.teaGreen;
    String tierLabel = 'Low risk';
    if (ok) {
      final tier = result?['tier'] as String? ?? '';
      if (tier == 'high_risk') {
        tierColor = Monad.terracotta;
        tierLabel = 'Higher risk — follow up';
      } else if (tier == 'moderate_risk') {
        tierColor = Monad.eriGold;
        tierLabel = 'Moderate risk — monitor';
      } else {
        tierColor = Monad.teaGreen;
        tierLabel = 'Low risk — routine';
      }
      return Card(
        elevation: 0,
        shape: Monad.cardShape,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Monad.radiusCard),
            color: Monad.parchment,
            boxShadow: Monad.cardShadow,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.health_and_safety, color: Monad.indigo, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('COGNITIVE RISK SCREENING', style: Monad.monoLabel),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(
                    'Score: ${(result?['risk_score'] ?? '--')} / 100',
                    style: Monad.subheading
                        .copyWith(fontSize: 18, color: Monad.offBlack),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: tierColor.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Row(children: [
                    Icon(Icons.circle, size: 10, color: tierColor),
                    const SizedBox(width: 6),
                    Text(tierLabel,
                        style:
                            Monad.monoBodySm.copyWith(color: tierColor)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                'Preliminary screening only — not a clinical diagnosis. '
                'Experimental / not clinically validated. '
                'Probability: ${result?['probability'] ?? '--'} · '
                'Features: ${result?['feature_count'] ?? '--'}.',
                style: Monad.monoCaption.copyWith(color: Monad.graphite),
              ),
              if (result?['note'] != null) ...[
                const SizedBox(height: 4),
                Text(result!['note'] as String,
                    style: Monad.monoBodySm.copyWith(color: Monad.smoke)),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Monad.radiusCard),
          color: Monad.periwinkleMist.withValues(alpha: 0.4),
          boxShadow: Monad.cardShadow,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: Monad.indigo, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('COGNITIVE RISK SCREENING', style: Monad.monoLabel),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Screening temporarily unavailable',
                style: Monad.subheading
                    .copyWith(fontSize: 18, color: Monad.offBlack)),
            const SizedBox(height: 6),
            Text(
              'The screening model could not be loaded in this worker. '
              'The endpoint remains active and will resume when the backend environment is restored.',
              style: Monad.monoBodySm.copyWith(color: Monad.graphite),
            ),
          ],
        ),
      ),
    );
  }
}
