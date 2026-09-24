import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';
import 'rag_qa_screen.dart';
import 'rag_upload_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.patientId,
    this.onConsentMissing,
  });

  final String patientId;
  final VoidCallback? onConsentMissing;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<Map<String, dynamic>>? _documents;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await ApiService.instance.listDocuments(widget.patientId);
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 403) widget.onConsentMissing?.call();
      if (!mounted) return;
      setState(() {
        _error = e.isNetworkError
            ? "You're offline — try again when connected."
            : (e.statusCode == 403 && e.message.contains('health_data')
                ? "health_data consent required — this patient has not granted consent for health data, so documents can't be viewed until they do."
                : (e.statusCode == 403
                    ? 'Health worker only — family caregiver accounts can\'t add or read health documents. Ask an ASHA worker, clinician, or admin.'
                    : 'Could not load documents: ${e.message}'));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load documents: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openUpload() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RagUploadScreen(
        patientId: widget.patientId,
        onConsentMissing: widget.onConsentMissing,
      ),
    ));
    if (mounted) await _load();
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final locked = _error != null && _error!.startsWith('Health worker only');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Documents'),
        backgroundColor: Monad.parchment,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: locked ? Monad.tintGold : Monad.tintMint,
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                  border: Border.all(color: Monad.ash, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      locked ? Icons.lock_outline : Icons.cloud_off,
                      size: 22,
                      color: Monad.graphite,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!, style: Monad.monoBodySm),
                    ),
                  ],
                ),
              ),
              if (!locked) ...[
                const SizedBox(height: 12),
                MonadPillButton(label: 'Retry', onPressed: _load),
              ],
            ] else if (_documents!.isEmpty)
              const Text(
                'No documents yet. Upload a prescription, discharge summary, or care plan.',
                style: Monad.monoBody,
              )
            else ...[
              for (final doc in _documents!)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Monad.parchment,
                    borderRadius: BorderRadius.circular(Monad.radiusMin),
                    border: Border.all(color: Monad.ash, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc['title']?.toString() ?? 'Medical Document',
                        style: Monad.subheading,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${doc['file_name'] ?? ''} · ${_date(doc['created_at']?.toString())}',
                        style: Monad.monoBodySm,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${doc['doc_type'] ?? ''} · ${doc['embedding_status'] ?? ''}',
                        style: Monad.monoCaption,
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (!locked) ...[
              MonadPillButton(
                label: 'Upload Document',
                variant: MonadPillVariant.secondary,
                onPressed: _openUpload,
              ),
              const SizedBox(height: 8),
              MonadPillButton(
                label: 'Ask About Documents',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RagQaScreen(patientId: widget.patientId),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
