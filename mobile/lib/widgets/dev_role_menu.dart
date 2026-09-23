/// Dev-only role switcher for testing/demo.
///
/// Visible only with `--dart-define=DEV_MENU=true`. Lets testers jump
/// between the seeded patient, family caregiver, and ASHA accounts without
/// re-typing credentials — so the patient-vs-caregiver routing never needs
/// re-diagnosing. Never compiled into release builds' UI (flag is false
/// unless explicitly passed).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/auth_session.dart';
import '../theme/monad_theme.dart';

class DevRoleMenu extends StatelessWidget {
  /// Dev-only: never active in release (kDebugMode) and only when explicitly
  /// enabled with --dart-define=DEV_MENU=true.
  static bool get enabled =>
      kDebugMode && const bool.fromEnvironment('DEV_MENU');

  const DevRoleMenu({super.key});

  static const _accounts = [
    ('Patient', '919876543001'),
    ('Family caregiver', '919876543002'),
    ('ASHA worker', '9100000001'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return const Drawer(
      backgroundColor: Monad.parchment,
      child: SafeArea(
        child: _DevRoleList(),
      ),
    );
  }
}

class _DevRoleList extends StatelessWidget {
  const _DevRoleList();

  @override
  Widget build(BuildContext context) {
    return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('DEV — VIEW AS', style: Monad.monoBodySm),
            const SizedBox(height: 8),
            for (final (label, phone) in DevRoleMenu._accounts)
              ListTile(
                title: Text(label, style: Monad.monoBody),
                subtitle: Text(phone, style: Monad.monoCaption),
                onTap: () async {
                  Navigator.of(context).pop();
                  await AuthSession.instance.logout();
                  await AuthSession.instance.login(
                      phone: phone, password: 'DemoPass123');
                },
              ),
          ],
        );
  }
}
