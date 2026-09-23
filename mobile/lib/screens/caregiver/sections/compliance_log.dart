import 'package:flutter/material.dart';

import '../../../models/shared_models.dart';
import '../../../theme/monad_theme.dart';

/// Reminder compliance log — today's events with escalation status.
class ComplianceLog extends StatelessWidget {
  const ComplianceLog({super.key, required this.events});

  final List<ReminderEventModel>? events;

  @override
  Widget build(BuildContext context) {
    final events = this.events;
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today\'s reminders', style: Monad.subheading),
            const SizedBox(height: 12),
            if (events == null)
              Text('Reminder log unavailable right now.',
                  style: Monad.monoBodySm)
            else if (events.isEmpty)
              Text('No reminders scheduled for today.',
                  style: Monad.monoBodySm)
            else
              ...events.map((e) {
                final escalated = e.status == ReminderStatus.escalated;
                final missed = e.status == ReminderStatus.missed;
                final done = !escalated && !missed;
                final tint = done
                    ? Monad.tintMint
                    : (escalated ? Monad.tintCoral : Monad.tintGold);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius:
                        BorderRadius.circular(Monad.radiusMin),
                    boxShadow: Monad.cardShadow,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle
                            : escalated
                                ? Icons.notification_important
                                : Icons.event_busy,
                        color: Monad.offBlack,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              done
                                  ? 'DONE'
                                  : e.status.name.toUpperCase(),
                              style: Monad.monoLabel,
                            ),
                            Text(
                              '${e.scheduledAt.toLocal()}'
                                  .substring(0, 16),
                              style: Monad.monoCaption.copyWith(
                                  color: Monad.offBlack),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
