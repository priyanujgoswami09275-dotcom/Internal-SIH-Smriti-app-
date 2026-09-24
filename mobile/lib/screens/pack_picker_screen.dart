/// Pack picker — choose an NER content pack + difficulty, then start Match It.
library;

import 'package:flutter/material.dart';

import '../data/local_content_packs.dart';
import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/offline_sync_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';
import 'match_it_screen.dart';

class PackPickerScreen extends StatefulWidget {
  final String patientId;
  final OfflineSyncService? sync;

  const PackPickerScreen({
    super.key,
    required this.patientId,
    this.sync,
  });

  @override
  State<PackPickerScreen> createState() => _PackPickerScreenState();
}

class _PackPickerScreenState extends State<PackPickerScreen> {
  final ApiService _api = ApiService.instance;

  List<ContentPackSummary>? _packs;
  bool _loading = true;
  String? _error;
  int _difficulty = 1;

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
      final packs = await _api.listContentPacks();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _packs = LocalContentPacks.summaries;
        _loading = false;
      });
    }
  }

  void _start(ContentPackSummary pack) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchItScreen(
          patientId: widget.patientId,
          sync: widget.sync,
          packId: pack.id,
          packName: pack.name,
          difficultyLevel: _difficulty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a Game'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center, style: Monad.patientBody),
                      const SizedBox(height: 16),
                      MonadPillButton(label: 'Retry', onPressed: _load),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('Easy'), icon: Icon(Icons.sentiment_satisfied)),
                          ButtonSegment(value: 2, label: Text('Medium'), icon: Icon(Icons.sentiment_neutral)),
                          ButtonSegment(value: 3, label: Text('Hard'), icon: Icon(Icons.psychology)),
                        ],
                        selected: {_difficulty},
                        onSelectionChanged: (s) => setState(() => _difficulty = s.first),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _packs?.length ?? 0,
                        itemBuilder: (context, index) {
                          final pack = _packs![index];
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 14),
                            shape: Monad.cardShape,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(24),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Monad.parchment,
                                  border: Border.all(color: Monad.ash),
                                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                                ),
                                child: const Icon(Icons.celebration, color: Monad.offBlack, size: 20),
                              ),
                              title: Text(pack.name, style: Monad.subheading),
                              subtitle: Text(
                                '${pack.region} · ${pack.itemCount} items\n${pack.description}',
                                // Patient-facing: 20px floor (region/item-count
                                // line + description).
                                style: Monad.patientBody,
                              ),
                              isThreeLine: true,
                              trailing: Icon(Icons.chevron_right, size: 36, color: Monad.graphite),
                              onTap: () => _start(pack),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
