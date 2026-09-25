/// Risk-screening display card (dashboard only — not a diagnosis).
/// Uses DESIGN.md / Monad tokens: cardShape, cardShadow, parchment, indigo,
/// teaGreen, terracotta, monoBody, monoCaption, monoLabel.
/// Framed explicitly as a screening indicator; avoids alarming red.
/// Handles model_unavailable gracefully (clear message, not blank).
library;

import 'package:flutter/material.dart';
import '../theme/monad_theme.dart';

class RiskScreeningCard extends StatelessWidget {
  final Map<String, dynamic>? result; // response from POST /patients/{id}/risk-screening
  const RiskScreeningCard({super.key, this.result});

  @override
  Widget build(BuildContext context) {
    // Null / not-yet-assessed: transparent that intake data isn't collected.
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.health_and_safety, color: Monad.indigo, size: 28),
                const SizedBox(width: 10),
                Text('COGNITIVE RISK SCREENING', style: Monad.monoLabel),
              ]),
              const SizedBox(height: 12),
              Text('Not assessed yet', style: Monad.subheading.copyWith(fontSize: 20, color: Monad.graphite)),
              const SizedBox(height: 8),
              Text(
                'The 32 screening inputs (Age, BMI, MMSE, Smoking, etc.) are not collected in the current intake form. '
                'When clinical intake is added, this card will show a screening score; until then it reflects the endpoint\'s graceful no-data state.',
                style: Monad.monoBodySm.copyWith(color: Monad.graphite),
              ),
              const SizedBox(height: 4),
              Text('Screening temporarily unavailable', style: Monad.monoCaption.copyWith(color: Monad.terracotta)),
            ],
          ),
        ),
      );
    }

    final status = result?['status'] as String?;
    final ok = status == 'ok';

    // Tier colors: calm, never harsh red. Low = teaGreen, moderate = eriGold,
    // high = terracotta (not crimson) — all paired with icon + text.
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.health_and_safety, color: Monad.indigo, size: 28),
                const SizedBox(width: 10),
                Text('COGNITIVE RISK SCREENING', style: Monad.monoLabel),
              ]),
              const SizedBox(height: 12),
              // Score + tier together — never color-alone.
              Row(children: [
                Expanded(
                  child: Text(
                    'Screening score: ${(result?['risk_score'] ?? '--').toString()} / 100',
                    style: Monad.subheading.copyWith(fontSize: 20, color: Monad.offBlack),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: tierColor.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Row(children: [
                    Icon(Icons.circle, size: 10, color: tierColor),
                    const SizedBox(width: 6),
                    Text(tierLabel, style: Monad.monoBodySm.copyWith(color: tierColor)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Preliminary screening only — not a clinical diagnosis. '
                'Probability: ${(result?['probability'] ?? '--').toString()} · '
                'Features: ${(result?['feature_count'] ?? '--').toString()}.',
                style: Monad.monoCaption.copyWith(color: Monad.graphite),
              ),
              const SizedBox(height: 8),
              if (result?['note'] != null)
                Text(result!['note'] as String, style: Monad.monoBodySm.copyWith(color: Monad.smoke)),
            ],
          ),
        ),
      );
    }

    // Graceful fallback — clear message, never blank / broken.
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Monad.radiusCard),
          color: Monad.periwinkleMist.withValues(alpha: 0.4),
          boxShadow: Monad.cardShadow,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: Monad.indigo, size: 28),
              const SizedBox(width: 10),
              Text('COGNITIVE RISK SCREENING', style: Monad.monoLabel),
            ]),
            const SizedBox(height: 12),
            Text('Screening temporarily unavailable', style: Monad.subheading.copyWith(fontSize: 20, color: Monad.offBlack)),
            const SizedBox(height: 8),
            Text(
              'The screening model could not be loaded (TensorFlow / .keras artifacts missing). '
              'This is a configuration issue — the endpoint remains active and will resume when the backend environment is restored.',
              style: Monad.monoBodySm.copyWith(color: Monad.graphite),
            ),
          ],
        ),
      ),
    );
  }
}
