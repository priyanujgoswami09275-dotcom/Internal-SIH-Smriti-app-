import 'package:flutter/material.dart';

import '../../../theme/monad_theme.dart';

class PatientSwitcher extends StatelessWidget {
  const PatientSwitcher({
    super.key,
    required this.patients,
    required this.selectedPatientId,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> patients;
  final String? selectedPatientId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: Monad.softShape,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedPatientId,
            isExpanded: true,
            hint: Text('Select patient', style: Monad.monoBody),
            items: patients.map((p) {
              return DropdownMenuItem<String>(
                value: p['patient_id'] as String,
                child: Text(
                  '${p['name']} (${p['district'] ?? 'NER'}) — ${(p['relationship_type'] ?? '').toString().toUpperCase()}',
                  style: Monad.monoBody.copyWith(color: Monad.offBlack),
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onSelect(v);
            },
          ),
        ),
      ),
    );
  }
}
