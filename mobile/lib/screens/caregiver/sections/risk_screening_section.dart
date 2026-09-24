/// Risk-screening dashboard section — clinical gating + consent state.
///
/// Verbatim extraction of the orchestrator's inline risk block, plus the
/// tinted health_data consent-required state (same visual pattern as
/// documents_card: tintGold, radiusMin, 1px ash, lock icon). The Run
/// Screening button stays enabled in the consent state (server
/// authoritative — re-push after consent is granted).
library;

import 'package:flutter/material.dart';

import '../../risk_intake_screen.dart';
import '../../../theme/monad_theme.dart';
import '../../../widgets/monad/monad_pill_button.dart';
import '../../../widgets/risk_screening_card.dart';

class RiskScreeningSection extends StatelessWidget {
  const RiskScreeningSection({
    super.key,
    required this.isClinical,
    required this.patientId,
    required this.patientName,
    required this.result,
    required this.consentMissing,
    required this.onResult,
    required this.onConsentMissing,
  });

  final bool isClinical;
  final String patientId;
  final String patientName;
  final Map<String, dynamic>? result;
  final bool consentMissing;
  final ValueChanged<Map<String, dynamic>> onResult;
  final VoidCallback onConsentMissing;

  @override
  Widget build(BuildContext context) {
    if (!isClinical) {
      // Gold lock note — exact existing basic-branch copy (no section header).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Monad.gold.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(Monad.radiusMin),
              border: Border.all(color: Monad.ash, width: 1),
            ),
            child: const Row(children: [
              Icon(Icons.lock_outline, size: 22, color: Monad.graphite),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Screening needs clinical tier / health-data consent — '
                  'available to linked clinical staff only.',
                  style: Monad.monoBodySm,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Risk screening', style: Monad.subheading),
        const SizedBox(height: 12),
        if (consentMissing)
          Container(
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
                  "health_data consent required — this patient has not granted consent for health data, so screening can't run until they do.",
                  style: Monad.monoBodySm,
                ),
              ),
            ]),
          )
        else
          RiskScreeningCard(result: result),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: MonadPillButton(
            label: 'Run Screening (32 inputs)',
            variant: MonadPillVariant.secondary,
            onPressed: () {
              if (patientId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RiskIntakeScreen(
                    patientId: patientId,
                    patientName: patientName,
                    onResult: onResult,
                    onConsentMissing: onConsentMissing,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
