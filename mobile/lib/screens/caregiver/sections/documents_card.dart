import 'package:flutter/material.dart';

import '../../../theme/monad_theme.dart';
import '../../../widgets/monad/monad_pill_button.dart';

/// RAG medical-document entry — staff-only by construction (this screen
/// never renders for patients). Shows the normal helper text + upload
/// button, or the tinted "health_data consent required" state when the
/// server has reported a missing consent for the selected patient.
class DocumentsCard extends StatelessWidget {
  const DocumentsCard({
    super.key,
    required this.patientId,
    required this.consentMissing,
    required this.onUpload,
  });

  final String? patientId;
  final bool consentMissing;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Medical Documents', style: Monad.subheading),
            const SizedBox(height: 8),
            if (consentMissing)
              // Same visual pattern as the trends lock note: tinted gold,
              // radiusMin, 1px ash border, lock icon (Amendment 1).
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
                      "health_data consent required — this patient has not granted consent for health data, so documents can't be uploaded until they do.",
                      style: Monad.monoBodySm,
                    ),
                  ),
                ]),
              )
            else
              const Text(
                'Upload prescriptions, discharge summaries, care plans. '
                'They are embedded and searchable in the clinical Q&A flow.',
                style: Monad.monoBodySm,
              ),
            const SizedBox(height: 16),
            // Button stays enabled in both states (server authoritative —
            // re-push allowed after consent is granted).
            MonadPillButton(
              label: 'Upload Document',
              variant: MonadPillVariant.secondary,
              onPressed: onUpload,
            ),
          ],
        ),
      ),
    );
  }
}
