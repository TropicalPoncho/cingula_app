// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/audio_asset.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/services/recorder_service.dart';
import '../../data/datasources/local/app_database.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/entities/geo_trigger.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/entities/geo_path.dart';
import '../notifiers/playback_notifier.dart';
import '../../core/config/location_config.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'dart:async';
import '../../core/services/log_service.dart';

/// Clean HomePage implementation (separate file). This contains the repaired UI.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaybackNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cingula audio geolocalizado')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Monitorear ubicacion en segundo plano'),
              subtitle: Text(notifier.statusMessage ?? 'Listo para iniciar'),
              value: notifier.isMonitoring,
              onChanged: (v) => v ? notifier.startMonitoring() : notifier.stopMonitoring(),
            ),
            const SizedBox(height: 24),
            if (notifier.currentAsset != null) _AudioDetails(asset: notifier.currentAsset!),
            const SizedBox(height: 16),
            const _DiagnosticsPanel(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: notifier.isMonitoring ? notifier.stopMonitoring : notifier.startMonitoring,
        label: Text(notifier.isMonitoring ? 'Detener' : 'Iniciar'),
        icon: Icon(notifier.isMonitoring ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}

class _AudioDetails extends StatelessWidget {
  final AudioAsset asset;
  const _AudioDetails({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(asset.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(asset.description),
        ]),
      ),
    );
  }
}

class _DiagnosticsPanel extends StatefulWidget {
  const _DiagnosticsPanel();

  @override
  State<_DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<_DiagnosticsPanel> {
  bool _loaded = false;
  List<AudioAsset> _audioAssets = [];
  int? _selectedAudioId;
  double _recSampleDistance = 5.0;
  int _recSecondsPerTrigger = 10;
  bool _isRecording = false;
  List<GeoTrigger> _lastTriggers = [];

  // Map data
  List<GeoTrigger> _mapTriggers = [];
  List<GeoPath> _mapPaths = [];
  List<String> _logs = [];
  StreamSubscription<List<String>>? _logSub;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    // subscribe to log service
    _logSub = getIt<LogService>().stream.listen((list) {
      if (mounted) setState(() => _logs = list.reversed.toList(growable: false));
    });
  }

  Future<void> _loadConfig() async {
    await LocationConfig.loadFromPrefs();
    try {
      _audioAssets = await getIt<AudioRepository>().fetchAll();
      if (_audioAssets.isNotEmpty) {
        _selectedAudioId = _audioAssets.first.id;
      }
    } catch (_) {}
    setState(() => _loaded = true);
    await _refreshMapData();
  }

  Future<void> _refreshMapData() async {
    try {
      final triggers = await getIt<GeoTriggerRepository>().fetchAll();
      final paths = await getIt<GeoPathRepository>().fetchAll();
      if (mounted) {
        setState(() {
          _mapTriggers = triggers;
          _mapPaths = paths;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _logSub?.cancel();
    super.dispose();
  }

  // Removed unused _saveAll helper to clean analyzer warnings.

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Diagnóstico y Recorder (debug)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _loaded
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _audioAssets.isEmpty
                      ? const Text('No hay audios disponibles')
                      : DropdownButton<int>(
                          value: _selectedAudioId,
                          items: _audioAssets.map((a) => DropdownMenuItem(value: a.id, child: Text(a.title))).toList(growable: false),
                          onChanged: (v) => setState(() => _selectedAudioId = v),
                        ),
                  const SizedBox(height: 8),
                  Text('Sampling distance (m): ${_recSampleDistance.toStringAsFixed(1)}'),
                  Slider(min: 1, max: 50, divisions: 49, value: _recSampleDistance, onChanged: (v) => setState(() => _recSampleDistance = v)),
                  Text('Seconds per trigger: $_recSecondsPerTrigger'),
                  Slider(min: 5, max: 60, divisions: 11, value: _recSecondsPerTrigger.toDouble(), onChanged: (v) => setState(() => _recSecondsPerTrigger = v.round())),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    ElevatedButton(
                      onPressed: (_selectedAudioId == null || _isRecording)
                          ? null
                          : () async {
                              final aid = _selectedAudioId!;
                              await getIt<GeoTriggerRepository>().deleteByAudioAssetId(aid);
                              await getIt<GeoPathRepository>().deleteByAudioAssetId(aid);
                              setState(() {
                                _lastTriggers = [];
                              });
                              await _refreshMapData();
                              setState(() => _isRecording = true);
                              await getIt<RecorderService>().startRecording(
                                audioAssetId: aid,
                                name: 'Recorded ${DateTime.now().toIso8601String()}',
                                sampleDistanceMeters: _recSampleDistance,
                                secondsPerTrigger: _recSecondsPerTrigger,
                              );
                            },
                      child: const Text('Start recording (overwrite)'),
                    ),
                    ElevatedButton(
                      onPressed: !_isRecording
                          ? null
                          : () async {
                              final created = await getIt<RecorderService>().stopRecording(secondsPerTrigger: _recSecondsPerTrigger);
                              setState(() {
                                _lastTriggers = created;
                                _isRecording = false;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording stopped and triggers created')));
                              }
                              await _refreshMapData();
                            },
                      child: const Text('Stop'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final db = getIt<AppDatabase>();
                        await db.recreateForTesting();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database recreated (debug)')));
                      },
                      child: const Text('Recreate DB (debug)'),
                    ),
                    TextButton.icon(
                      onPressed: (_selectedAudioId == null)
                          ? null
                          : () async {
                              final aid = _selectedAudioId!;
                              final tdel = await getIt<GeoTriggerRepository>().deleteByAudioAssetId(aid);
                              final pdel = await getIt<GeoPathRepository>().deleteByAudioAssetId(aid);
                              setState(() => _lastTriggers = []);
                              await _refreshMapData();
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $tdel triggers and $pdel paths for audio $aid')));
                            },
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete triggers for audio'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  SizedBox(height: 180, child: _MiniMapWidget(paths: _mapPaths, triggers: _mapTriggers)),
                  const SizedBox(height: 8),
                  Text('Last triggers: ${_lastTriggers.length}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await _refreshMapData();
                      final recent = getIt<LogService>().recent.reversed.toList(growable: false);
                      if (mounted) setState(() => _logs = recent);
                    },
                    child: const Text('Refresh table & logs'),
                  ),
                  const SizedBox(height: 8),
                  // Triggers table
                  SizedBox(
                    height: 160,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('id')),
                          DataColumn(label: Text('lat')),
                          DataColumn(label: Text('lon')),
                          DataColumn(label: Text('radius')),
                          DataColumn(label: Text('offset_ms')),
                          DataColumn(label: Text('audio')),
                          DataColumn(label: Text('path')),
                        ],
                        rows: _mapTriggers.map((t) {
                          return DataRow(cells: [
                            DataCell(Text('${t.id}')),
                            DataCell(Text(t.latitude.toStringAsFixed(6))),
                            DataCell(Text(t.longitude.toStringAsFixed(6))),
                            DataCell(Text('${t.radiusMeters}')),
                            DataCell(Text('${t.offsetMs}')),
                            DataCell(Text('${t.audioAssetId}')),
                            DataCell(Text('${t.geoPathId ?? '-'}')),
                          ]);
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Logs viewer (reverse chronological)
                  Container(
                    height: 160,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                    child: _logs.isEmpty
                        ? const Text('No logs yet')
                        : ListView.builder(
                            itemCount: _logs.length,
                            itemBuilder: (ctx, idx) => Text(_logs[idx], style: const TextStyle(fontSize: 12)),
                          ),
                  ),
                ])
              : const Text('Cargando...'),
        ]),
      ),
    );
  }
}

class _MiniMapWidget extends StatefulWidget {
  final List<GeoPath> paths;
  final List<GeoTrigger> triggers;
  const _MiniMapWidget({required this.paths, required this.triggers});

  @override
  State<_MiniMapWidget> createState() => _MiniMapWidgetState();
}

class _MiniMapWidgetState extends State<_MiniMapWidget> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    // Build polylines by grouping triggers that share the same geoPathId
    final Map<int, List<ll.LatLng>> pathPolylines = {};
    for (final t in widget.triggers) {
      final pid = t.geoPathId;
      if (pid == null) continue;
      pathPolylines.putIfAbsent(pid, () => []).add(ll.LatLng(t.latitude, t.longitude));
    }

    // markers for triggers (flutter_map 8.x uses 'child' instead of 'builder')
    final markers = widget.triggers.map((t) {
      return Marker(
        width: 36,
        height: 36,
        point: ll.LatLng(t.latitude, t.longitude),
        child: const Icon(Icons.location_on, color: Colors.red, size: 28),
      );
    }).toList(growable: false);

    // initial center: average of triggers or fallback
    ll.LatLng center;
    if (widget.triggers.isNotEmpty) {
      final avgLat = widget.triggers.map((t) => t.latitude).reduce((a, b) => a + b) / widget.triggers.length;
      final avgLon = widget.triggers.map((t) => t.longitude).reduce((a, b) => a + b) / widget.triggers.length;
      center = ll.LatLng(avgLat, avgLon);
    } else {
      // fallback to 0,0
        center = ll.LatLng(0.0, 0.0);
    }

    final polylines = pathPolylines.values.map((pts) {
      return Polyline(
        points: pts,
        strokeWidth: 3.0,
        color: Colors.blueAccent.withOpacity(0.8),
      );
    }).toList(growable: false);

    // ensure map center is moved after build when triggers exist
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (widget.triggers.isNotEmpty) _mapController.move(center, 13.0);
      } catch (_) {}
    });

    return Card(
      child: SizedBox(
        height: 180,
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.tropicalponcho.cingula_app',
            ),
            if (polylines.isNotEmpty)
              PolylineLayer(polylines: polylines),
            if (markers.isNotEmpty)
              MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }
}
