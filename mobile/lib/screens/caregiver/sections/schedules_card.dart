import 'package:flutter/material.dart';

import '../../../models/shared_models.dart';
import '../../../theme/monad_theme.dart';

/// Schedule editing — same create/delete endpoints as the web dashboard.
class SchedulesCard extends StatelessWidget {
  const SchedulesCard({
    super.key,
    required this.schedules,
    required this.onAdd,
    required this.onRemove,
  });

  final List<ReminderScheduleModel>? schedules;
  final VoidCallback onAdd;
  final Future<void> Function(String scheduleId) onRemove;

  @override
  Widget build(BuildContext context) {
    final schedules = this.schedules;
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Schedules', style: Monad.subheading),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('ADD'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (schedules == null)
              Text('Schedules unavailable right now.', style: Monad.monoBodySm)
            else if (schedules.isEmpty)
              Text('No schedules yet.', style: Monad.monoBodySm)
            else
              ...schedules.map((s) {
                final typeColor =
                    Monad.reminderColor(s.reminderType.name);
                // Fixed type mapping: medicine = lakeBlue, water = skyBlue,
                // food = gold, exercise = mint (tinted surfaces + icon +
                // label together).
                final tint = s.reminderType == ReminderType.medicine
                    ? Color.lerp(Monad.parchment, Monad.lakeBlue, 0.12)!
                    : s.reminderType == ReminderType.water
                        ? Monad.tintSky
                        : s.reminderType == ReminderType.food
                            ? Monad.tintGold
                            : Monad.tintMint;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius:
                          BorderRadius.circular(Monad.radiusMin),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      s.reminderType == ReminderType.medicine
                          ? Icons.medication
                          : s.reminderType == ReminderType.water
                              ? Icons.water_drop
                              : s.reminderType == ReminderType.food
                                  ? Icons.restaurant
                                  : Icons.directions_walk,
                      color: typeColor == Monad.mint || typeColor == Monad.gold
                          ? Monad.offBlack
                          : typeColor,
                      size: 24,
                    ),
                  ),
                  title: Text(s.reminderType.name.toUpperCase(),
                      style: Monad.patientBody),
                  subtitle: Text('${s.cadence} · ${s.isActive ? 'active' : 'paused'}',
                      style: Monad.monoBodySm),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Monad.graphite,
                    onPressed: () => onRemove(s.id),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
