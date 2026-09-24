/// Medical document upload for RAG pipeline — staff uploads a prescription,
/// discharge summary, or doctor's note for the selected patient.
/// Uses `http` (multipart) for upload + `file_picker` for selection.
/// Backend endpoint: POST /api/v1/reports/documents/upload (staff roles +
/// clinical access + `health_data` consent enforced server-side).
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

/// Testable request builder: authed multipart POST with the backend field
/// contract (`patient_id` + `doc_type` + `title` fields, `file` part).
/// `patient_id` is also sent as a query param (FastAPI signature declares it
/// as a query param) so the contract holds either way.
@visibleForTesting
http.MultipartRequest buildRagUploadRequest({
  required String patientId,
  required Uint8List bytes,
  required String filename,
  String? authToken,
  String docType = 'prescription',
  String title = 'Medical Document',
  required String baseUrl,
}) {
  final uri = Uri.parse('$baseUrl/api/v1/reports/documents/upload')
      .replace(queryParameters: {'patient_id': patientId});
  final request = http.MultipartRequest('POST', uri);
  if (authToken != null && authToken.isNotEmpty) {
    request.headers['Authorization'] = 'Bearer $authToken';
  }
  request.fields['patient_id'] = patientId;
  request.fields['doc_type'] = docType;
  request.fields['title'] = title;
  request.files
      .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  return request;
}

/// Formats an upload failure with the server `detail` (never a bare code).
/// 403s get the clinical-tier/consent hint so staff know what to check.
@visibleForTesting
String formatRagUploadFailure(int statusCode, String body) {
  var detail = body;
  try {
    final data = jsonDecode(body);
    if (data is Map && data['detail'] != null) {
      detail = data['detail'].toString();
    }
  } catch (_) {
    // Keep the raw body when it is not JSON.
  }
  if (detail.trim().isEmpty) detail = 'HTTP $statusCode';
  var msg = 'Upload failed: $detail';
  if (statusCode == 403) {
    msg +=
        ' — clinical tier / health-data consent required. Ask linked clinical staff to check access and consent.';
  }
  return msg;
}

class RagUploadScreen extends StatefulWidget {
  final String patientId;
  final Uint8List? testBytes;
  final String? testFilename;
  final Future<http.Response> Function(http.MultipartRequest)? sendForTest;
  final VoidCallback? onConsentMissing;

  /// Test seam mirroring `sendForTest`: when set, `_pickFile` uses this
  /// instead of the platform `FilePicker` call (no MethodChannel in tests).
  @visibleForTesting
  final Future<({Uint8List bytes, String filename})?> Function()? pickForTest;
  const RagUploadScreen({
    super.key,
    required this.patientId,
    this.testBytes,
    this.testFilename,
    this.sendForTest,
    this.onConsentMissing,
    this.pickForTest,
  });

  @override
  State<RagUploadScreen> createState() => _RagUploadScreenState();
}

class _RagUploadScreenState extends State<RagUploadScreen> {
  bool _uploading = false;
  String? _result;
  String? _filePath;
  Uint8List? _pickedBytes;
  String? _pickedFilename;
  bool _consentMissing = false;

  /// Structural consent marker for the orchestrator's documents card
  /// (Amendment 1: explicit state alongside the inline failure message).
  @visibleForTesting
  String? get lastOutcome => _consentMissing ? 'consent_missing' : null;

  Future<void> _pickFile() async {
    final picked = widget.pickForTest != null
        ? await widget.pickForTest!()
        : await _pickWithFilePicker();
    if (picked == null || !mounted) return;
    setState(() {
      _pickedBytes = picked.bytes;
      _pickedFilename = picked.filename;
      _filePath = picked.filename; // display line unchanged
      _result = null;
    });
  }

  Future<({Uint8List bytes, String filename})?> _pickWithFilePicker() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'md', 'doc', 'docx'],
    );
    if (f == null) return null;
    return (bytes: await f.readAsBytes(), filename: f.name);
  }

  bool get _canUpload {
    if (_uploading) return false;
    if (widget.testBytes != null && widget.testBytes!.isNotEmpty) return true;
    return _pickedBytes != null && _pickedBytes!.isNotEmpty;
  }

  Future<void> _upload() async {
    final hasTestBytes =
        widget.testBytes != null && widget.testBytes!.isNotEmpty;
    final hasPickedBytes = _pickedBytes != null && _pickedBytes!.isNotEmpty;
    if (!hasTestBytes && !hasPickedBytes) {
      setState(() => _result = 'Please select a file first.');
      return;
    }
    setState(() {
      _uploading = true;
      _result = null;
    });
    try {
      final Uint8List bytes;
      final String filename;
      if (hasTestBytes) {
        bytes = widget.testBytes!;
        filename = widget.testFilename ?? 'document.pdf';
      } else {
        bytes = _pickedBytes!;
        filename = _pickedFilename ?? 'document.pdf';
      }
      if (widget.sendForTest != null) {
        final request = buildRagUploadRequest(
          patientId: widget.patientId,
          bytes: bytes,
          filename: filename,
          authToken: ApiService.instance.authToken,
          baseUrl: AppConfig.apiBaseUrl,
        );
        final res = await widget.sendForTest!(request);
        if (!mounted) return;
        final consentMissing =
            res.statusCode == 403 && res.body.contains('health_data');
        setState(() {
          _uploading = false;
          if (consentMissing) _consentMissing = true;
          _result = res.statusCode >= 200 && res.statusCode < 300
              ? 'Uploaded successfully (HTTP ${res.statusCode}).'
              : formatRagUploadFailure(res.statusCode, res.body);
        });
        // Structural consent state fires alongside the inline message
        // (no silent failures: both the message AND the callback fire).
        if (consentMissing) widget.onConsentMissing?.call();
      } else {
        await ApiService.instance.uploadDocument(
          patientId: widget.patientId,
          bytes: bytes,
          filename: filename,
          title: 'Medical Document',
        );
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _result = 'Uploaded successfully (HTTP 200).';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final consentMissing =
          e.statusCode == 403 && e.message.contains('health_data');
      setState(() {
        _uploading = false;
        if (consentMissing) _consentMissing = true;
        _result = e.statusCode != null
            ? formatRagUploadFailure(e.statusCode!, e.message)
            : 'Upload failed: ${e.message}';
      });
      // Structural consent state fires alongside the inline message
      // (no silent failures: both the message AND the callback fire).
      if (consentMissing) widget.onConsentMissing?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _result = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Documents'),
        backgroundColor: Monad.parchment,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          color: Monad.parchment,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('Upload prescriptions, discharge summaries, or care plans.',
                style: Monad.subheading),
            const SizedBox(height: 8),
            Text('They become searchable in the clinical Q&A flow.',
                style: Monad.patientBody),
            const SizedBox(height: 24),
            // Feature card: parchment, 1px ash, 40px radius, no shadow.
            Container(
              padding: const EdgeInsets.all(Monad.cardPadding),
              decoration: BoxDecoration(
                color: Monad.parchment,
                borderRadius: BorderRadius.circular(Monad.radiusCard),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.upload_file,
                        color: Monad.offBlack, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Document File', style: Monad.monoLabel)),
                  ]),
                  const SizedBox(height: 12),
                  Text(_filePath ?? 'No file selected.', style: Monad.monoBody),
                  const SizedBox(height: 8),
                  // Secondary (offBlack) — the screen's lakeBlue primary
                  // is reserved for Upload below.
                  MonadPillButton(
                    label: 'Select File',
                    variant: MonadPillVariant.secondary,
                    onPressed: _uploading ? null : _pickFile,
                  ),
                  const SizedBox(height: 8),
                  MonadPillButton(
                    label: _uploading ? 'Uploading…' : 'Upload',
                    onPressed: _canUpload ? _upload : null,
                    busy: _uploading,
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _result!.contains('successfully')
                            ? Monad.tintMint
                            : Monad.tintGold,
                        borderRadius: BorderRadius.circular(Monad.radiusMin),
                        border: Border.all(color: Monad.ash, width: 1),
                      ),
                      child: Text(_result!,
                          style: Monad.monoBodySm.copyWith(
                            color: Monad.offBlack,
                          )),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Elevated (periwinkle) card — the one colored surface.
            Container(
              padding: const EdgeInsets.all(Monad.cardPadding),
              decoration: BoxDecoration(
                color: Monad.periwinkleMist,
                borderRadius: BorderRadius.circular(Monad.radiusCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How it works', style: Monad.monoLabel),
                  const SizedBox(height: 6),
                  Text(
                      'Uploaded PDFs/text files are extracted, chunked, embedded, and made searchable through clinical questions in this app.',
                      style: Monad.monoBody.copyWith(color: Monad.offBlack)),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
