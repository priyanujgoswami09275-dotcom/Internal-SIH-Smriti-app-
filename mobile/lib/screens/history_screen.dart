import 'package:flutter/material.dart';

import '../models/shared_models.dart';
import '../patient_localizations.dart';
import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class HistoryScreen extends StatefulWidget {
  final String patientId;
  final ApiService? api;

  const HistoryScreen({super.key, required this.patientId, this.api});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ApiService _api = widget.api ?? ApiService.instance;
  List<PatientGameHistoryItem>? _items;
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
      final items = await _api.patientGameHistory();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = context.tr('history.error');
        _loading = false;
      });
    }
  }

  String _gameName(String gameType) {
    switch (gameType) {
      case 'routine_sequencing':
        return context.tr('history.routine');
      case 'number_recall':
        return context.tr('history.recall');
      case 'odd_one_out':
        return context.tr('history.odd');
      default:
        return context.tr('history.matchIt');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('history.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _message(_error!, _load)
              : _items == null || _items!.isEmpty
                  ? _message(context.tr('history.empty'), _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _items!.length,
                        itemBuilder: (context, index) => _card(_items![index]),
                      ),
                    ),
    );
  }

  Widget _message(String message, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center, style: Monad.patientBody),
            const SizedBox(height: 20),
            MonadPillButton(
                label: context.tr('history.retry'), onPressed: retry),
          ],
        ),
      ),
    );
  }

  Widget _card(PatientGameHistoryItem item) {
    final date = item.completedAt == null
        ? '—'
        : MaterialLocalizations.of(context)
            .formatMediumDate(item.completedAt!.toLocal());
    final accuracy = item.accuracyPct == null
        ? '—'
        : '${item.accuracyPct!.toStringAsFixed(1)}%';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_gameName(item.gameType), style: Monad.subheading),
            const SizedBox(height: 8),
            Text(date, style: Monad.monoBody),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text(
                  '${context.tr('history.score')}: ${item.score} / ${item.totalAttempts}',
                  style: Monad.patientBody,
                ),
                Text(
                  '${context.tr('history.accuracy')}: $accuracy',
                  style: Monad.patientBody,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
