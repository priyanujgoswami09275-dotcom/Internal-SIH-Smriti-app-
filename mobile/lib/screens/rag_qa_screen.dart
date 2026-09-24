import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class RagQaScreen extends StatefulWidget {
  const RagQaScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<RagQaScreen> createState() => _RagQaScreenState();
}

class _RagQaScreenState extends State<RagQaScreen> {
  final _controller = TextEditingController();
  Map<String, dynamic>? _result;
  String? _error;
  bool _asking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Type a question first.');
      return;
    }
    setState(() {
      _asking = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ApiService.instance
          .askDocumentQuestion(patientId: widget.patientId, question: question);
      if (!mounted) return;
      setState(() {
        _result = result;
        _asking = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _asking = false;
        _error = e.isNetworkError
            ? "You're offline — try again when connected."
            : (e.statusCode == 403
                ? (e.message.contains('health_data')
                    ? e.message
                    : "You can't ask about these documents — a health worker with clinical access can.")
                : 'Could not get an answer: ${e.message}');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _asking = false;
        _error = 'Could not get an answer: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final citations = (result?['citations'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask About Documents'),
        backgroundColor: Monad.parchment,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Answers come only from this patient's uploaded documents.",
              style: Monad.monoBody,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 2,
              style: Monad.monoBody,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. What medication was prescribed?',
              ),
            ),
            const SizedBox(height: 12),
            MonadPillButton(
              label: _asking ? 'Asking…' : 'Ask',
              onPressed: _asking ? null : _ask,
              busy: _asking,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Monad.tintGold,
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                  border: Border.all(color: Monad.ash, width: 1),
                ),
                child: Text(_error!, style: Monad.monoBodySm),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              const Text('Answer', style: Monad.subheading),
              const SizedBox(height: 6),
              Text(result['answer']?.toString() ?? '', style: Monad.monoBody),
              if (citations.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Sources', style: Monad.monoLabel),
                const SizedBox(height: 6),
                for (var i = 0; i < citations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '[${i + 1}] ${citations[i]['title'] ?? citations[i]['file_ref'] ?? 'document'}'
                      '${citations[i]['similarity'] != null ? ' · similarity ${citations[i]['similarity']}' : ''}',
                      style: Monad.monoBodySm,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                result['disclaimer']?.toString() ?? '',
                style: Monad.monoCaption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
