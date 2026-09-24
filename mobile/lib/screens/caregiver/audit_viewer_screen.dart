import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/monad_theme.dart';

/// DPDP audit view — read-only; admin-only on the server. Other roles
/// see the honest "admin-only" state rather than an error.
class AuditViewerScreen extends StatefulWidget {
  const AuditViewerScreen({super.key});

  @override
  State<AuditViewerScreen> createState() => _AuditViewerScreenState();
}

class _AuditViewerScreenState extends State<AuditViewerScreen> {
  late final Future<List<Map<String, dynamic>>> _logs =
      ApiService.instance.auditLogs(limit: 50);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DPDP audit trail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _logs,
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
          ),
        ],
      ),
    );
  }
}
