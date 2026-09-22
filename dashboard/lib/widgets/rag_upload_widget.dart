/// RAG document upload — POST /api/v1/reports/documents/upload
/// Web file picker (HTML input element) → authed multipart upload →
/// snackbar feedback with server detail. No new dependency.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../theme/monad_theme.dart';
import 'rag_upload_picker_stub.dart'
    if (dart.library.html) 'rag_upload_picker_web.dart';

typedef RagUploadFn = Future<dynamic> Function({
  required String patientId,
  required Uint8List bytes,
  required String filename,
  String docType,
  String? title,
});

typedef RagPickFn = Future<({Uint8List bytes, String filename})?> Function();

class RagUploadWidget extends StatefulWidget {
  final String patientId;
  final RagUploadFn? uploadFn;
  final RagPickFn? pickFn;
  const RagUploadWidget(
      {super.key, required this.patientId, this.uploadFn, this.pickFn});

  @override
  State<RagUploadWidget> createState() => _RagUploadWidgetState();
}

class _RagUploadWidgetState extends State<RagUploadWidget> {
  bool _uploading = false;
  String? _lastResult;

  Future<void> _pickAndUpload() async {
    // Tests force the web path via [pickFn]; production uses kIsWeb.
    if (widget.pickFn != null || kIsWeb) {
      await _pickOnWeb();
    } else {
      setState(() => _lastResult = 'File picker available on web dashboard only.');
    }
  }

  Future<void> _pickOnWeb() async {
    setState(() {
      _uploading = true;
      _lastResult = null;
    });
    try {
      final picked = widget.pickFn != null
          ? await widget.pickFn!()
          : await pickDocumentFile();
      if (!mounted) return;
      if (picked == null) {
        setState(() {
          _uploading = false;
          _lastResult = 'No file selected.';
        });
        return;
      }
      await _uploadBytes(picked.bytes, picked.filename);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _lastResult = 'Upload failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _uploadBytes(Uint8List bytes, String filename) async {
    try {
      final uploader = widget.uploadFn ?? Api.uploadDocument;
      await uploader(
        patientId: widget.patientId,
        bytes: bytes,
        filename: filename,
        docType: 'prescription',
        title: 'Care Plan',
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _lastResult = 'Uploaded $filename successfully.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded $filename successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _lastResult = 'Upload failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Monad.radiusCard),
          color: Monad.parchment,
          boxShadow: Monad.cardShadow,
        ),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.upload_file, color: Monad.indigo, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Medical Documents (RAG)', style: Monad.monoLabel),
                  const SizedBox(height: 4),
                  Text(
                    'Upload prescriptions, discharge summaries, care plans. '
                    'They are embedded and searchable in the clinical Q&A flow.',
                    style: Monad.monoBodySm.copyWith(color: Monad.graphite),
                  ),
                  if (_lastResult != null) ...[
                    const SizedBox(height: 6),
                    Text(_lastResult!,
                        style:
                            Monad.monoCaption.copyWith(color: Monad.terracotta)),
                  ],
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }
}
