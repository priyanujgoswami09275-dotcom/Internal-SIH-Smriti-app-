/// ElderCare Companion — patient mobile app (plus caregiver dashboard view).
///
/// Entry flow:
///   restore session -> AuthGate -> Login/Register
///                     -> HomeShell (role-aware) -> games / routine /
///                        reminders / voice companion / caregiver dashboard
library;

import 'package:flutter/material.dart';

import 'models/shared_models.dart';
import 'screens/caregiver_dashboard_screen.dart';
import 'screens/odd_one_out_screen.dart';
import 'screens/pack_picker_screen.dart';
import 'screens/recall_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/routine_screen.dart';
import 'screens/voice_companion_screen.dart';
import 'services/api_service.dart';
import 'services/auth_session.dart';
import 'services/offline_sync_service.dart';
import 'theme/monad_theme.dart';
import 'widgets/dev_role_menu.dart';
import 'widgets/monad/monad_pill_button.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AuthSession.instance.restore();
  runApp(const ElderCareApp());
}

class ElderCareApp extends StatelessWidget {
  const ElderCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smriti Companion',
      debugShowCheckedModeBanner: false,
      theme: Monad.theme(),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthSession.instance,
      builder: (context, _) {
        switch (AuthSession.instance.status) {
          case AuthStatus.restoring:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AuthStatus.unauthenticated:
            return const AuthScreen();
          case AuthStatus.authenticated:
            return const HomeShell();
        }
      },
    );
  }
}

// =====================================================================
// Auth (login / register)
// =====================================================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await AuthSession.instance.register(
          phone: _phone.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
        );
      } else {
        await AuthSession.instance.login(
          phone: _phone.text.trim(),
          password: _password.text,
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Connection problem: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: const BoxDecoration(
                    color: Monad.lakeBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  'Smriti',
                  textAlign: TextAlign.center,
                  style: Monad.heading,
                ),
                const SizedBox(height: 4),
                const Text(
                  'স্বাস্থ্য আৰু মনৰ চৰ্চা (Health & Mind Care)',
                  textAlign: TextAlign.center,
                  style: Monad.monoBodySm,
                ),
                const SizedBox(height: 28),
                if (_registering) ...[
                  TextFormField(
                    controller: _name,
                    style: Monad.patientBody,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: Monad.patientBody,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  validator: (v) => (v == null || v.trim().length < 6) ? 'Enter a valid phone number' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  style: Monad.patientBody,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center,
                      style: Monad.monoBodySm.copyWith(color: Monad.crimson)),
                ],
                const SizedBox(height: 22),
                MonadPillButton(
                  label: _registering ? 'Create Account' : 'Sign In',
                  onPressed: _submit,
                  busy: _busy,
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _registering = !_registering),
                  child: Text(
                    _registering
                        ? 'Already have an account? Sign in'
                        : 'New patient? Register here',
                    style: Monad.monoBodySm.copyWith(color: Monad.offBlack),
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Home shell — role-aware feature hub
// =====================================================================

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ApiService _api = ApiService.instance;

  String? _patientId;
  bool _resolvingProfile = true;

  @override
  void initState() {
    super.initState();
    OfflineSyncService.instance.setActiveAccount(AuthSession.instance.user?.id);
    OfflineSyncService.instance.start();
    OfflineSyncService.instance.syncNow();
    _resolveIdentity();
  }

  @override
  void dispose() {
    OfflineSyncService.instance.stop();
    super.dispose();
  }

  Future<void> _resolveIdentity() async {
    final user = AuthSession.instance.user;
    if (user != null && user.role == Role.patient) {
      try {
        final profile = await _api.myPatient();
        if (mounted) setState(() => _patientId = profile?.id);
      } on Exception catch (e) {
        debugPrint('Could not resolve patient profile: $e');
      }
    }
    if (mounted) setState(() => _resolvingProfile = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthSession.instance.user;

    if (_resolvingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Explicit staff-role switch: family caregiver, ASHA worker, clinician,
    // and admin all land on the caregiver dashboard. The basic-vs-clinical
    // tier split is server-driven via summary['view']; admin additionally
    // gets the T7 audit-trail AppBar entry. Patient (or null) falls through
    // to the profile-setup / PatientHome path below.
    final role = user?.role;
    if (role == Role.familyCaregiver ||
        role == Role.ashaWorker ||
        role == Role.clinician ||
        role == Role.admin) {
      return CaregiverDashboardScreen(caregiverId: user!.id);
    }

    // Patient without a profile yet: prompt to create one.
    if (_patientId == null) {
      return _ProfileSetup(onCreated: (id) => setState(() => _patientId = id));
    }

    return PatientHome(patientId: _patientId!);
  }
}

class _ProfileSetup extends StatefulWidget {
  final ValueChanged<String> onCreated;
  const _ProfileSetup({required this.onCreated});

  @override
  State<_ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<_ProfileSetup> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final patient = await ApiService.instance.createMyPatient(name: name);
      await ApiService.instance.grantConsent(patientId: patient.id);
      if (mounted) widget.onCreated(patient.id);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome!'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: const BoxDecoration(
                color: Monad.lakeBlue,
                shape: BoxShape.circle,
              ),
            ),
            Text('Tell us your name to get started', style: Monad.subheading),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              style: Monad.patientBody,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 24),
            MonadPillButton(
              label: 'Continue',
              onPressed: _create,
              busy: _busy,
            ),
          ],
        ),
      ),
    );
  }
}

/// Patient home — games, routine, reminders, voice. No clinical upload
/// entry here: RAG document upload requires staff roles + clinical tier
/// (patients 403 even authenticated), so it lives on the staff
/// [CaregiverDashboardScreen] surface only.
class PatientHome extends StatelessWidget {
  final String patientId;
  const PatientHome({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smriti Companion'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => AuthSession.instance.logout(),
          ),
        ],
      ),
      drawer: DevRoleMenu.enabled ? const DevRoleMenu() : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Monad.spacing16),
            child: Text(
              'Your health worker can add your health documents.',
              style: Monad.monoBodySm.copyWith(color: Monad.smoke),
            ),
          ),
          _homeButton(
            context,
            icon: Icons.extension,
            title: 'Play Memory Match',
            subtitle: 'Train your memory with NER themes',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PackPickerScreen()),
            ),
          ),
          _homeButton(
            context,
            icon: Icons.event_note,
            title: 'Daily Routine Game',
            subtitle: 'Sequence your daily activities',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RoutineScreen(
                  patientId: patientId,
                  difficultyLevel: 1,
                  languageCode: AuthSession.instance.user?.preferredLanguage ?? 'english',
                ),
              ),
            ),
          ),
          _homeButton(
            context,
            icon: Icons.pin,
            title: 'Number Recall',
            subtitle: 'Remember numbers in order',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RecallScreen(patientId: patientId),
              ),
            ),
          ),
          _homeButton(
            context,
            icon: Icons.quiz,
            title: 'Odd One Out',
            subtitle: 'Spot the item that does not belong',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OddOneOutScreen(patientId: patientId),
              ),
            ),
          ),
          _homeButton(
            context,
            icon: Icons.alarm,
            title: 'Reminders',
            subtitle: 'Medicine, water, food & exercise',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RemindersScreen(patientId: patientId),
              ),
            ),
          ),
          _homeButton(
            context,
            icon: Icons.record_voice_over,
            title: 'Talk to Aai Companion',
            subtitle: 'A warm voice to talk with',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VoiceCompanionScreen(patientId: patientId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Feature-card pattern (DESIGN.md): 1px ash border, 40px radius,
  // 40px padding, mono icon, serif 24px title, mono 16px graphite body.
  Widget _homeButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    // Warm parchment → periwinkle gradient wash — ground the feature card
    // in the region's light without adding decorative clutter.
    // MonadFeatureCard: parchment, 1px ash, 40px radius, 40px padding,
    // serif 24 title, patient-facing body at 20px floor. No shadow/gradient.
    return Container(
      margin: const EdgeInsets.only(bottom: Monad.spacing16),
      decoration: BoxDecoration(
        color: Monad.parchment,
        border: Border.all(color: Monad.ash, width: 1),
        borderRadius: BorderRadius.circular(Monad.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Monad.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(Monad.cardPadding),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Monad.parchment,
                  border: Border.all(color: Monad.ash, width: 1),
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                ),
                child: Icon(icon, color: Monad.offBlack, size: 20),
              ),
              const SizedBox(width: Monad.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Monad.subheading),
                    const SizedBox(height: 8),
                    Text(subtitle, style: Monad.patientBody),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Monad.graphite, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
