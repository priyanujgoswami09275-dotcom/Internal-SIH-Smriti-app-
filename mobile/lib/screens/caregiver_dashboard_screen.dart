/// Native caregiver dashboard — family, ASHA worker, clinician.
///
/// Every view reads/writes the exact endpoints the web dashboard uses;
/// the server enforces roles and permission tiers — this screen only
/// reflects them (e.g. hides clinical charts when the summary says
/// view=basic, shows the audit panel only if the server allows it).
/// Dashboard views require a live connection; only reminder
/// acknowledgment is queued offline (by the existing patient app path).
library;

import 'package:flutter/material.dart';
import 'dart:developer' as developer;

import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import '../theme/monad_theme.dart';
import '../widgets/dev_role_menu.dart';
import '../widgets/monad/monad_pill_button.dart';
import 'caregiver/audit_viewer_screen.dart';
import 'caregiver/sections/alerts_card.dart';
import 'caregiver/sections/compliance_log.dart';
import 'caregiver/sections/documents_card.dart';
import 'caregiver/sections/metrics_tiles.dart';
import 'caregiver/sections/patient_switcher.dart';
import 'caregiver/sections/risk_screening_section.dart';
import 'caregiver/sections/schedules_card.dart';
import 'caregiver/sections/trends_section.dart';
import 'clinical_notes_screen.dart';
import 'rag_upload_screen.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  final String caregiverId;

  const CaregiverDashboardScreen({super.key, required this.caregiverId});

  @override
  State<CaregiverDashboardScreen> createState() =>
      _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  final ApiService _api = ApiService.instance;

  List<Map<String, dynamic>>? _patients;
  String? _selectedPatientId;
  Map<String, dynamic>? _summary;
  List<ReminderEventModel>? _events;
  List<ReminderScheduleModel>? _schedules;
  Map<String, dynamic>? _riskScreeningResult;
  bool _screeningConsentMissing = false;
  bool _consentMissing = false;
  bool _loading = true;
  String? _error;

  /// Rate-limit / tier notice banner text (429 body or clinical-tier gate).
  String? _notice;

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  Future<void> _fetchPatients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await _api.caregiverPatients(widget.caregiverId);
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _loading = false;
      });
      if (patients.isNotEmpty) {
        await _select(patients.first['patient_id'] as String);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 429
            ? 'Too many requests — please wait a moment and retry.'
            : 'Could not load your patient list. ${e.message}';
        if (e.statusCode == 429) _notice = 'Rate limit reached (100 req/min).';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your patient list. $e';
      });
    }
  }

  /// Loads everything the selected patient's views need. Live connection only.
  Future<void> _select(String patientId) async {
    setState(() {
      _loading = true;
      _consentMissing = false; // never show the previous patient's consent state
      _riskScreeningResult = null; // never show the previous patient's score
      _screeningConsentMissing = false; // never show the previous patient's screening consent state
    });
    try {
      final summary = await _api.patientSummary(patientId);
      if (!mounted) return;
      setState(() {
        _selectedPatientId = patientId;
        _summary = summary;
        _loading = false;
      });
      // Secondary views degrade individually; the roster + summary stay.
      try {
        final events = await _api.reminderEvents(patientId);
        if (mounted) setState(() => _events = events);
      } on ApiException catch (e) {
        if (mounted && e.statusCode == 429) {
          setState(() => _notice = 'Rate limit reached (100 req/min).');
        }
      } on Exception {
        if (mounted) setState(() => _events = null);
      }
      try {
        final schedules = await _api.reminderSchedules(patientId);
        if (mounted) setState(() => _schedules = schedules);
      } on Exception {
        if (mounted) setState(() => _schedules = null);
      }
      // Risk screening rehydration — clinical view only; 404 (endpoint
      // not deployed yet), 403, and request failures are swallowed by
      // getRiskScreening (treated as no prior result).
      if (summary['view'] == 'clinical') {
        try {
          final risk = await _api.getRiskScreening(patientId);
          if (mounted && _selectedPatientId == patientId) {
            setState(() => _riskScreeningResult = risk);
          }
        } on Exception catch (e) {
          developer.log('risk screening load failed: $e',
              name: 'CaregiverDashboard');
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 429
            ? 'Too many requests — please wait a moment and retry.'
            : 'Could not load the summary. ${e.message}';
        if (e.statusCode == 429) _notice = 'Rate limit reached (100 req/min).';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the summary. $e';
      });
    }
  }

  Future<void> _acknowledge(String alertId) async {
    try {
      await _api.acknowledgeAlert(alertId);
      await _select(_selectedPatientId!);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not acknowledge: $e')),
      );
    }
  }

  Future<void> _addSchedule() async {
    const types = ['medicine', 'water', 'food', 'exercise'];
    var type = 'medicine';
    final timeCtl = TextEditingController(text: '08:00');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add reminder schedule', style: Monad.subheading),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: type,
                isExpanded: true,
                items: [
                  for (final t in types)
                    DropdownMenuItem(value: t, child: Text(t.toUpperCase()))
                ],
                onChanged: (v) => setSheet(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timeCtl,
                decoration: const InputDecoration(
                    labelText: 'Time (HH:MM, comma-separated)'),
              ),
              const SizedBox(height: 16),
              MonadPillButton(
                label: 'Save',
                onPressed: () => Navigator.pop(context, true),
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.createSchedule(
        patientId: _selectedPatientId!,
        reminderType: type,
        cadence: 'daily@${timeCtl.text.trim()}',
      );
      await _select(_selectedPatientId!);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.statusCode == 429
              ? 'Rate limit reached — try again shortly.'
              : 'Could not add schedule: ${e.message}')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add schedule: $e')));
    }
  }

  Future<void> _removeSchedule(String scheduleId) async {
    try {
      await _api.deleteSchedule(scheduleId);
      await _select(_selectedPatientId!);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
    }
  }

  /// Pushes the RAG upload screen for the selected patient; a consent 403
  /// fires `onConsentMissing`, flipping the documents card to its tinted
  /// health_data-consent-required state (server 403s surface inline there).
  Future<void> _openUpload() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RagUploadScreen(
          patientId: _selectedPatientId!,
          onConsentMissing: () {
            if (mounted) setState(() => _consentMissing = true);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DevRoleMenu.enabled ? const DevRoleMenu() : null,
      appBar: AppBar(
        title: const Text('Caregiver Dashboard / তত্ত্বাৱধায়ক'),        centerTitle: false,
        actions: [
          if (AuthSession.instance.user?.role == Role.admin)
            IconButton(
              tooltip: 'Compliance audit trail (admin)',
              icon: const Icon(Icons.fact_check_outlined),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const AuditViewerScreen()),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => AuthSession.instance.logout(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _selectedPatientId != null
                ? () => _select(_selectedPatientId!)
                : _fetchPatients,
          ),
          // Clinical notes — ASHA workers and clinical staff; family sees it too
          // (shared notes for home caregivers are legitimate). Hidden if no
          // patient is selected yet.
          if (_selectedPatientId != null)
            IconButton(
              tooltip: 'Add clinical note',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ClinicalNotesScreen(patientId: _selectedPatientId!),
                  ),
                );
              },
            ),
          // RAG medical-document upload — staff-only surface (patients 403
          // even authenticated: backend requires staff roles + clinical
          // tier + health-data consent). Hidden until a patient is selected.
          if (_selectedPatientId != null)
            IconButton(
              tooltip: 'Upload medical document',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RagUploadScreen(patientId: _selectedPatientId!),
                  ),
                );
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final notice = _notice;
    return Column(
      children: [
        if (notice != null)
          Container(
            width: double.infinity,
            color: Monad.tintGold,
            padding: const EdgeInsets.all(12),
            child: Text(notice, style: Monad.monoBodySm.copyWith(color: Monad.offBlack)),
          ),
        Expanded(child: _buildMain()),
      ],
    );
  }

  Widget _buildMain() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Monad.smoke),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: Monad.monoBodyLg),
              const SizedBox(height: 16),
              MonadPillButton(label: 'Retry', onPressed: _fetchPatients),
            ],
          ),
        ),
      );
    }
    final patients = _patients ?? const [];
    if (patients.isEmpty) {
      return Center(
        child: Text('No patients assigned to this caregiver account yet.',
            style: Monad.monoBodyLg.copyWith(color: Monad.smoke)),
      );
    }
    final summary = _summary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_showPatientSwitcher) ...[
          PatientSwitcher(patients: patients, selectedPatientId: _selectedPatientId, onSelect: (v) => _select(v)),
          const SizedBox(height: 16),
        ],
        if (summary != null) ...[
          _sectionHeader('Overview'),
          const SizedBox(height: 12),
          AlertsCard(summary: summary, onAcknowledge: _acknowledge),
          if ((summary['active_alerts'] as List? ?? []).isNotEmpty)
            const SizedBox(height: 16),
          MetricsTiles(summary: summary),
          const SizedBox(height: 24),
          RiskScreeningSection(
            isClinical: summary['view'] == 'clinical',
            patientId: _selectedPatientId!,
            patientName: (summary['patient_name'] as String?) ?? 'this patient',
            result: _riskScreeningResult,
            consentMissing: _screeningConsentMissing,
            onResult: (r) => setState(() => _riskScreeningResult = r),
            onConsentMissing: () {
              if (mounted) setState(() => _screeningConsentMissing = true);
            },
          ),
          _sectionHeader('Trends'),
          const SizedBox(height: 12),
          TrendsSection(summary: summary), // hidden server-side for view=basic
          const SizedBox(height: 24),
          _sectionHeader('Compliance'),
          const SizedBox(height: 12),
          ComplianceLog(events: _events),
          const SizedBox(height: 24),
          _sectionHeader('Schedules'),
          const SizedBox(height: 12),
          SchedulesCard(schedules: _schedules, onAdd: _addSchedule, onRemove: _removeSchedule),
          const SizedBox(height: 24),
          _sectionHeader('Medical Documents'),
          const SizedBox(height: 12),
          DocumentsCard(
            patientId: _selectedPatientId,
            consentMissing: _consentMissing,
            onUpload: _selectedPatientId == null ? null : _openUpload,
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) => Text(title, style: Monad.subheading);

  /// Patient switcher — ASHA-worker tier only. Family accounts never see it
  /// (the server returns exactly their one linked patient anyway).
  bool get _showPatientSwitcher =>
      AuthSession.instance.user?.role == Role.ashaWorker;

  /// RAG medical-document entry moved to `caregiver/sections/documents_card.dart`.

}
