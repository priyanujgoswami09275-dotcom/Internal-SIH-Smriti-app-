/// ASHA worker clinical notes entry — lightweight on-device form for
/// field observations during a patient visit. Notes are stored locally
/// in the offline outbox (drift) and replayed to the backend when the
/// mobile reconnects. Backend ingestion target: /api/v1/sync (offline outbox).
library;

import 'package:flutter/material.dart';
import '../models/shared_models.dart';
import '../services/auth_session.dart';
import '../services/offline_sync_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class ClinicalNotesScreen extends StatefulWidget {
  final String patientId;
  final OfflineSyncService? sync;
  const ClinicalNotesScreen({super.key, required this.patientId, this.sync});

  @override
  State<ClinicalNotesScreen> createState() => _ClinicalNotesScreenState();
}

class _ClinicalNotesScreenState extends State<ClinicalNotesScreen> {
  final _notes = TextEditingController();
  final _observation = TextEditingController();
  String _severity = 'low';
  bool _saving = false;
  String? _result;

  @override
  void dispose() {
    _notes.dispose();
    _observation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notesText = _notes.text.trim();
    if (notesText.isEmpty) {
      setState(() => _result = 'Please enter notes.');
      return;
    }
    final user = AuthSession.instance.user;
    if (user == null) {
      setState(() => _result = 'Please sign in again.');
      return;
    }
    setState(() { _saving = true; _result = null; });
    try {
      // Offline-safe: enqueue onto the offline_symptom pipeline (the same one
      // used by symptom logs). The backend categorizes on its end by source.
      // SymptomLog.severity is a 1-5 scale; the screen offers low/medium/high.
      final severity = _severity == 'high' ? 4 : _severity == 'medium' ? 3 : 2;
      final source =
          user.role == Role.ashaWorker ? 'manual_asha' : 'manual_caregiver';
      final observationText = _observation.text.trim();
      final combined = observationText.isEmpty
          ? notesText
          : '$observationText\n$notesText';
      await (widget.sync ?? OfflineSyncService.instance).enqueueClinicalNote(
        patientId: widget.patientId,
        enteredBy: user.id,
        source: source,
        severity: severity,
        notes: combined,
        recordedAt: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _result = 'Queued — will send when online.';
        _notes.clear();
        _observation.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _result = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Notes'),
        backgroundColor: Monad.parchment,
        elevation: 0,
      ),
      body: Container(
        color: Monad.parchment,
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text('Field visit observation', style: Monad.subheading),
            const SizedBox(height: 8),
            Text('ASHA worker — add clinical notes from today\'s visit.', style: Monad.monoBody),
            const SizedBox(height: 24),
            _label('Severity'),
            Row(children: [
              for (final s in const ['low', 'medium', 'high'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: _severity == s,
                    onSelected: (_) => setState(() => _severity = s),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            _label('Observation (brief)'),
            TextField(
              controller: _observation,
              maxLines: 2,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g. walking slower than usual'),
            ),
            const SizedBox(height: 16),
            _label('Notes (detailed)'),
            TextField(
              controller: _notes,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Detailed clinical observation'),
            ),
            const SizedBox(height: 20),
            MonadPillButton(
              label: _saving ? 'Saving…' : 'Save Notes',
              onPressed: _saving ? null : _save,
              busy: _saving,
              expanded: true,
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Text(_result!, style: Monad.monoBodySm.copyWith(
                color: _result!.contains('Queued') || _result!.contains('successfully') || _result!.contains('Saved') ? Monad.teaGreen : Monad.crimson,
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Monad.monoLabel),
  );
}
