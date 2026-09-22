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

import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import '../theme/monad_theme.dart';
import '../widgets/dev_role_menu.dart';
import '../widgets/monad/monad_pill_button.dart';
import '../widgets/trend_chart.dart';
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
    setState(() => _loading = true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const DevRoleMenu(),
      appBar: AppBar(
        title: const Text('Caregiver Dashboard / তত্ত্বাৱধায়ক'),        centerTitle: false,
        actions: [
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
          _patientSelector(patients),
          const SizedBox(height: 16),
        ],
        if (summary != null) ...[
          _sectionHeader('Overview'),
          const SizedBox(height: 12),
          _alerts(summary),
          if ((summary['active_alerts'] as List? ?? []).isNotEmpty)
            const SizedBox(height: 16),
          _metrics(summary),
          const SizedBox(height: 24),
          _sectionHeader('Trends'),
          const SizedBox(height: 12),
          _trends(summary), // hidden server-side for view=basic
          const SizedBox(height: 24),
          _sectionHeader('Compliance'),
          const SizedBox(height: 12),
          _complianceLog(),
          const SizedBox(height: 24),
          _sectionHeader('Schedules'),
          const SizedBox(height: 12),
          _schedulesCard(),
          const SizedBox(height: 24),
          _sectionHeader('Medical Documents'),
          const SizedBox(height: 12),
          _documentsCard(),
          const SizedBox(height: 24),
          _sectionHeader('Audit trail'),
          const SizedBox(height: 12),
          _auditCard(),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) => Text(title, style: Monad.subheading);

  /// Pill status chip: tinted fill + icon + uppercase label. Chips are one
  /// of the two surfaces allowed the ambient shadow (DESIGN.md amendment).
  Widget _chip({required String label, required IconData icon, required Color tint}) {
    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(Monad.radiusPill),
        boxShadow: Monad.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Monad.offBlack),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: Monad.monoCaption.copyWith(color: Monad.offBlack)),
        ],
      ),
    );
  }

  /// Patient switcher — ASHA-worker tier only. Family accounts never see it
  /// (the server returns exactly their one linked patient anyway).
  bool get _showPatientSwitcher =>
      AuthSession.instance.user?.role == Role.ashaWorker;
  Widget _patientSelector(List<Map<String, dynamic>> patients) {
    return Card(
      elevation: 0,
      shape: Monad.softShape,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedPatientId,
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
              if (v != null) _select(v);
            },
          ),
        ),
      ),
    );
  }

  /// Risk flags + active alerts, acknowledged via the same endpoint as web.
  Widget _alerts(Map<String, dynamic> summary) {
    final alerts = summary['active_alerts'] as List? ?? const [];
    final flags = summary['clinical_flags'] as Map<String, dynamic>? ?? const {};
    final drop = flags['cognitive_drop_detected'] == true;
    final missed = flags['high_missed_reminders'] == true;
    if (alerts.isEmpty && flags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (alerts.isNotEmpty) ...[
          ...alerts.map((a) {
            final map = a as Map<String, dynamic>;
            final critical =
                map['severity'] == 'critical' || map['severity'] == 'warning';
            final tint =
                critical ? Monad.tintCoral : Monad.tintGold;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              // Alert card: tint fill + 1px ash hairline, no shadow
              // (only game faces + status chips get elevation).
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(Monad.radiusCard),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _chip(
                    label: (map['severity'] as String? ?? 'notice'),
                    icon: critical
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    tint: Monad.parchment,
                  ),
                  const SizedBox(height: 10),
                  Text(map['summary'] as String? ?? 'Risk alert',
                      style: Monad.patientBody),
                  const SizedBox(height: 4),
                  Text('Type: ${map['trigger_type']}',
                      style: Monad.monoBodySm),
                  const SizedBox(height: 12),
                  MonadPillButton(
                    label: 'Resolve',
                    variant: MonadPillVariant.secondary,
                    onPressed: () => _acknowledge(map['id'] as String),
                  ),
                ],
              ),
            );
          }),
        ],
        // Threshold flags — exactly as the backend computes them, surfaced
        // as one elevated periwinkle banner.
        if (drop || missed)
          Container(
            decoration: BoxDecoration(
              color: Monad.periwinkleMist,
              borderRadius: BorderRadius.circular(Monad.radiusCard),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (drop)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.trending_down,
                        color: Monad.crimson, size: 32),
                    title: Text('Cognitive drop detected (<60% accuracy)',
                        style: Monad.patientBody),
                  ),
                if (missed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_off,
                        color: Monad.crimson, size: 32),
                    title: Text('3+ missed reminders in 7 days',
                        style: Monad.patientBody),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _metrics(Map<String, dynamic> summary) {
    final isClinical = summary['view'] == 'clinical';
    final compliance = (summary['compliance_pct'] as num? ?? 0).toDouble();
    final games = summary['games_played'] as int? ?? 0;
    final ack = summary['reminders_acknowledged'] as int? ?? 0;
    final total = summary['reminders_total'] as int? ?? 0;
    final missed = summary['reminders_missed'] as int? ?? 0;
    final tiles = <Widget>[
      if (isClinical)
        _tile(
          'Cognitive accuracy',
          '${((summary['accuracy_pct'] as num? ?? 0) as double).toStringAsFixed(0)}%',
          '$games games (7d)',
          Icons.psychology,
          Monad.tintSky,
        ),
      _tile('Compliance', '${compliance.toStringAsFixed(0)}%',
          '$ack/$total acknowledged', Icons.alarm_on, Monad.tintMint),
      _tile('Missed', '$missed', 'last 7 days', Icons.event_busy,
          missed > 0 ? Monad.tintCoral : Monad.tintGold),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: tiles,
    );
  }

  /// 14-day sparklines — same daily_trends array the web charts render.
  /// Server strips it for basic tier, so basic caregivers see the note.
  Widget _trends(Map<String, dynamic> summary) {
    final trends = (summary['daily_trends'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (trends.isEmpty) {
      return Container(
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
              'Basic view — accuracy and response-time trends are visible '
              'to linked clinical staff only.',
              style: Monad.monoBodySm,
            ),
          ),
        ]),
      );
    }
    final acc = trends
        .map((t) => (t['accuracy_pct'] as num?)?.toDouble())
        .toList();
    final rt = trends
        .map((t) => (t['avg_response_time_ms'] as num?)?.toDouble())
        .toList();
    return Column(
      children: [
        TrendChart(
            values: acc,
            title: 'Accuracy trend (14d)',
            subtitle: '% per active day'),
        const SizedBox(height: 12),
        TrendChart(
            values: rt,
            title: 'Response time trend (14d)',
            subtitle: 'ms per active day'),
      ],
    );
  }

  /// Reminder compliance log — today's events with escalation status.
  Widget _complianceLog() {
    final events = _events;
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

  /// Schedule editing — same create/delete endpoints as the web dashboard.
  Widget _schedulesCard() {
    final schedules = _schedules;
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
                  onPressed: _addSchedule,
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
                    onPressed: () => _removeSchedule(s.id),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// RAG medical-document entry — staff-only by construction (this screen
  /// never renders for patients). Pushes the upload screen for the selected
  /// patient; server 403s (clinical-tier/consent) surface there with detail.
  Widget _documentsCard() {
    final patientId = _selectedPatientId;
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
            const Text(
              'Upload prescriptions, discharge summaries, care plans. '
              'They are embedded and searchable in the clinical Q&A flow.',
              style: Monad.monoBodySm,
            ),
            const SizedBox(height: 16),
            MonadPillButton(
              label: 'Upload Document',
              variant: MonadPillVariant.secondary,
              onPressed: patientId == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RagUploadScreen(patientId: patientId),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// DPDP audit view — read-only; admin-only on the server. Other roles
  /// see the honest "admin-only" state rather than an error.
  Widget _auditCard() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _api.auditLogs(limit: 50),
      builder: (context, snap) {
        Widget body;
        if (snap.hasError) {
          final e = snap.error;
          body = Text(
            e is ApiException && e.statusCode == 403
                ? 'Audit trail is admin-only — your role cannot view it.'
                : 'Could not load the audit trail right now.',
            style: Monad.monoBodySm,
          );
        } else if (!snap.hasData) {
          body = const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snap.data!.isEmpty) {
          body = Text('No audit entries yet.', style: Monad.monoBodySm);
        } else {
          body = Column(
            children: [
              for (final l in snap.data!.take(20))
                Builder(
                  builder: (_) {
                    final label =
                        'by ${l['user_id'] ?? 'system'} · ${l['timestamp'] ?? ''}';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${l['action']} · ${l['resource_type']}',
                          style: Monad.monoBodySm
                              .copyWith(color: Monad.offBlack)),
                      subtitle: Text(
                        // Cap at 60 chars without crashing on short labels
                        // (substring end must not exceed the string length).
                        label.length > 60 ? label.substring(0, 60) : label,
                        style: Monad.monoCaption,
                      ),
                    );
                  },
                ),
            ],
          );
        }
        return Card(
          elevation: 0,
          color: Monad.periwinkleMist,
          shape: Monad.softShape,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DPDP audit trail', style: Monad.subheading),
                const SizedBox(height: 12),
                body,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(
      String title, String value, String subtitle, IconData icon, Color tint) {
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(Monad.radiusMin),
              ),
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Monad.offBlack, size: 22),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: Monad.headingSm.copyWith(fontSize: 32),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(title.toUpperCase(),
                style: Monad.monoCaption, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: Monad.monoCaption),
          ],
        ),
      ),
    );
  }
}
