import 'package:flutter/material.dart';
import '../theme/monad_theme.dart';

enum RiskScreeningState {
  notAssessed,
  consentRequired,
  validationFailed,
  inferenceFailed,
  modelUnavailable,
  transportFailure,
  result,
}

RiskScreeningState riskScreeningStateFromResponse(Map<String, dynamic>? response) {
  switch (response?['status']) {
    case 'ok':
      return RiskScreeningState.result;
    case 'consent_required':
      return RiskScreeningState.consentRequired;
    case 'validation_failed':
      return RiskScreeningState.validationFailed;
    case 'inference_failed':
      return RiskScreeningState.inferenceFailed;
    case 'model_unavailable':
      return RiskScreeningState.modelUnavailable;
    case 'transport_failure':
      return RiskScreeningState.transportFailure;
    default:
      return RiskScreeningState.notAssessed;
  }
}

class RiskScreeningCard extends StatelessWidget {
  final Map<String, dynamic>? result;
  final RiskScreeningState? state;
  final String? errorMessage;

  const RiskScreeningCard({
    super.key,
    this.result,
    this.state,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = state ?? riskScreeningStateFromResponse(result);
    if (resolved == RiskScreeningState.result) {
      return _resultCard();
    }
    return _messageCard(resolved);
  }

  Widget _shell({
    required IconData icon,
    required String title,
    required String body,
    Color? color,
  }) {
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Monad.radiusCard),
          color: color ?? Monad.parchment,
          boxShadow: Monad.cardShadow,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: Monad.indigo, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'COGNITIVE RISK SCREENING',
                  style: Monad.monoLabel,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              title,
              style: Monad.subheading.copyWith(
                fontSize: 20,
                color: Monad.offBlack,
              ),
            ),
            const SizedBox(height: 8),
            Text(body, style: Monad.monoBodySm.copyWith(color: Monad.graphite)),
            const SizedBox(height: 8),
            Text(
              'Experimental — not clinically validated.',
              style: Monad.monoCaption.copyWith(color: Monad.terracotta),
            ),
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                errorMessage!,
                style: Monad.monoCaption.copyWith(color: Monad.smoke),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _messageCard(RiskScreeningState resolved) {
    switch (resolved) {
      case RiskScreeningState.notAssessed:
        return _shell(
          icon: Icons.health_and_safety,
          title: 'No screening result yet',
          body:
              'No preliminary screening result is recorded for this patient. The 32-input form is required to create one.',
        );
      case RiskScreeningState.consentRequired:
        return _shell(
          icon: Icons.lock_outline,
          title: 'health_data consent required',
          body:
              'Screening cannot run until active consent for health_data is granted. No screening inputs are collected before that consent.',
          color: Monad.tintGold,
        );
      case RiskScreeningState.validationFailed:
        final errors = result?['errors'];
        final detail = errors is List
            ? errors.map((value) => value.toString()).join('\n')
            : errorMessage ?? 'One or more screening inputs are invalid.';
        return _shell(
          icon: Icons.rule_folder_outlined,
          title: 'Screening validation failed',
          body: 'The screening inputs need correction before they can be submitted.\n$detail',
          color: Monad.tintGold,
        );
      case RiskScreeningState.inferenceFailed:
        return _shell(
          icon: Icons.warning_amber_rounded,
          title: 'Screening inference failed',
          body:
              'The screening service could not produce a valid result. No result was recorded; review the inputs or try again.',
          color: Monad.tintCoral,
        );
      case RiskScreeningState.modelUnavailable:
        return _shell(
          icon: Icons.memory_outlined,
          title: 'Screening model unavailable',
          body:
              'The screening model artifacts are unavailable in this worker. The endpoint remains active, but no score was produced.',
          color: Monad.periwinkleMist,
        );
      case RiskScreeningState.transportFailure:
        return _shell(
          icon: Icons.cloud_off,
          title: 'Screening service unavailable',
          body:
              'Could not reach the screening service. No result was recorded; check the connection and retry.',
          color: Monad.periwinkleMist,
        );
      case RiskScreeningState.result:
        return _resultCard();
    }
  }

  Widget _resultCard() {
    final response = result ?? const <String, dynamic>{};
    final tier = response['tier'] as String? ?? '';
    final score = (response['risk_score'] as num?)?.toDouble();
    var tierColor = Monad.teaGreen;
    var tierLabel = 'Low risk — routine';
    if (tier == 'high_risk') {
      tierColor = Monad.terracotta;
      tierLabel = 'Higher risk — follow up';
    } else if (tier == 'moderate_risk') {
      tierColor = Monad.eriGold;
      tierLabel = 'Moderate risk — monitor';
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
              Expanded(
                child: Text(
                  'COGNITIVE RISK SCREENING',
                  style: Monad.monoLabel,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(
                  'Screening score: ${(response['risk_score'] ?? '--').toString()} / 100',
                  style: Monad.subheading.copyWith(
                    fontSize: 20,
                    color: Monad.offBlack,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: tierColor.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.circle, size: 10, color: tierColor),
                  const SizedBox(width: 6),
                  Text(
                    tierLabel,
                    style: Monad.monoBodySm.copyWith(color: tierColor),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Preliminary screening only — not a clinical diagnosis. '
              'Experimental — not clinically validated. '
              'Probability: ${(response['probability'] ?? '--').toString()} · '
              'Features: ${(response['feature_count'] ?? '--').toString()}.',
              style: Monad.monoCaption.copyWith(color: Monad.graphite),
            ),
            if (response['note'] != null) ...[
              const SizedBox(height: 8),
              Text(
                response['note'] as String,
                style: Monad.monoBodySm.copyWith(color: Monad.smoke),
              ),
            ],
            if (score == null)
              Text(
                'The server did not return a numeric score.',
                style: Monad.monoCaption.copyWith(color: Monad.smoke),
              ),
          ],
        ),
      ),
    );
  }
}
