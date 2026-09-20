// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/config/location_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/log_service.dart';
import '../../../../core/services/recorder_service.dart';
import '../../../../domain/entities/audio_asset.dart';
import '../../../../domain/entities/geo_path.dart';
import '../../../../domain/entities/geo_trigger.dart';
import '../../../../domain/repositories/audio_repository.dart';
import '../../../../domain/repositories/geo_path_repository.dart';
import '../../../../domain/repositories/geo_trigger_repository.dart';
import '../../../../data/datasources/local/sync_local_data_source.dart';
import '../../../../data/sync/sync_client.dart';
import '../../../../data/sync/sync_trigger.dart';
import '../../../../domain/usecases/run_sync_usecase.dart';
import '../../../notifiers/playback_notifier.dart';
import '../../../widgets/trigger_map.dart';
import '../../data_browser_page.dart';

class DiagnosticsPanel extends StatefulWidget {
  const DiagnosticsPanel({super.key});

  @override
  State<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<DiagnosticsPanel> {
  bool _loaded = false;
  List<AudioAsset> _audioAssets = [];
  int? _selectedAudioId;
  bool _recordNewAudio = false;
  final double _recSampleDistance = 5.0;
  bool _isRecording = false;
  List<GeoTrigger> _lastTriggers = [];
  final TextEditingController _pathNameController = TextEditingController(text: 'Mi ruta');
  final TextEditingController _triggerRadiusController = TextEditingController(text: '12');

  // Map data
  List<GeoTrigger> _mapTriggers = [];
  List<GeoPath> _mapPaths = [];
  List<String> _logs = [];
  StreamSubscription<List<String>>? _logSub;
  String? _serverCursor;
  DateTime? _lastSync;
  int _outboxCount = 0;
  SyncTriggerStatus _syncStatus = SyncTriggerStatus.idle;
  StreamSubscription<SyncTriggerStatus>? _syncStatusSub;

  // Crear región

  // Radio de activación para debug
  final TextEditingController _activationRadiusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activationRadiusController.text = LocationConfig.activationRadiusMeters.toStringAsFixed(1);
    _loadConfig();
    _refreshSyncStatus();
    _syncStatus = getIt<SyncTrigger>().lastStatus;
    _syncStatusSub = getIt<SyncTrigger>().statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _syncStatus = status);
      // El contador de pendientes cambia con cada push: refrescarlo para que nunca quede viejo.
      _refreshSyncStatus();
    });
    _logSub = getIt<LogService>().stream.listen((list) {
      if (mounted) setState(() => _logs = list.reversed.toList(growable: false));
    });
  }

  String get _syncStatusLabel {
    switch (_syncStatus) {
      case SyncTriggerStatus.idle:
        return 'sin intentos todavía';
      case SyncTriggerStatus.running:
        return 'enviando...';
      case SyncTriggerStatus.ok:
        return _outboxCount > 0
            ? 'último push OK, quedan $_outboxCount pendientes'
            : 'último push OK, outbox vacío';
      case SyncTriggerStatus.transientError:
        return 'ERROR de red/servidor — reintenta con backoff';
      case SyncTriggerStatus.authError:
        return 'ERROR DE AUTH (401) — revisar --dart-define=CINGULA_SYNC_API_KEY. No se reintenta.';
    }
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

  Future<void> _refreshSyncStatus() async {
    try {
      final syncClient = getIt<SyncClient>();
      final state = await syncClient.getState();
      final outbox = await syncClient.pendingOutbox(limit: 200);
      if (!mounted) return;
      final lastSyncSec = state['last_sync_at'] as int?;
      setState(() {
        _serverCursor = state['server_cursor'] as String?;
        _lastSync = lastSyncSec != null ? DateTime.fromMillisecondsSinceEpoch(lastSyncSec * 1000) : null;
        _outboxCount = outbox.length;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _syncStatusSub?.cancel();
    _pathNameController.dispose();
    _triggerRadiusController.dispose();
    _activationRadiusController.dispose();
    super.dispose();
  }

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
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Panel: Path + audio'),
                    children: [
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Grabar nuevo audio con micrófono'),
                        dense: true,
                        value: _recordNewAudio,
                        onChanged: _isRecording
                            ? null
                            : (v) {
                                setState(() {
                                  _recordNewAudio = v;
                                });
                              },
                      ),
                      const SizedBox(height: 4),
                      const Text('Audio existente:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      IgnorePointer(
                        ignoring: _recordNewAudio,
                        child: Opacity(
                          opacity: _recordNewAudio ? 0.45 : 1.0,
                          child: _audioAssets.isEmpty
                              ? const Text('No hay audios disponibles')
                              : DropdownButton<int>(
                                  value: _selectedAudioId,
                                  items: _audioAssets.map((a) => DropdownMenuItem(value: a.id, child: Text(a.title))).toList(growable: false),
                                  onChanged: (v) => setState(() => _selectedAudioId = v),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pathNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del path',
                          hintText: 'Ej: Ruta por el parque',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        enabled: !_isRecording,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _triggerRadiusController,
                        decoration: const InputDecoration(
                          labelText: 'Trigger radius (m)',
                          hintText: 'Ej: 12',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        enabled: !_isRecording,
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final radius = double.tryParse(_triggerRadiusController.text) ?? 12.0;
                          final spacing = math.max(1.0, radius - 2.0);
                          return Text(
                            'Trigger spacing (calculado): ${spacing.toStringAsFixed(1)} m',
                            style: TextStyle(color: Colors.grey[700], fontSize: 13),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        ElevatedButton(
                          onPressed: _isRecording
                              ? null
                              : () async {
                                  try {
                                    setState(() => _isRecording = true);
                                    final pathName = _pathNameController.text.trim().isEmpty
                                        ? 'Path ${DateTime.now().toIso8601String()}'
                                        : _pathNameController.text.trim();
                                    final radius = double.tryParse(_triggerRadiusController.text) ?? 12.0;
                                    final spacing = math.max(1.0, radius - 2.0);
                                    if (_recordNewAudio) {
                                      await getIt<RecorderService>().startRecordingWithMic(
                                        name: pathName,
                                        sampleDistanceMeters: _recSampleDistance,
                                        spacingMeters: spacing,
                                        triggerRadiusMeters: radius,
                                      );
                                    } else {
                                      if (_selectedAudioId == null) {
                                        setState(() => _isRecording = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Selecciona un audio existente o activa "Grabar nuevo audio"')),
                                          );
                                        }
                                        return;
                                      }
                                      await getIt<RecorderService>().startRecording(
                                        audioAssetId: _selectedAudioId!,
                                        name: pathName,
                                        sampleDistanceMeters: _recSampleDistance,
                                        spacingMeters: spacing,
                                        triggerRadiusMeters: radius,
                                      );
                                    }
                                  } catch (e) {
                                    setState(() => _isRecording = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('No se pudo iniciar la grabación: $e')),
                                      );
                                    }
                                  }
                                },
                          child: const Text('Grabar micrófono + path'),
                        ),
                        ElevatedButton(
                          onPressed: !_isRecording
                              ? null
                              : () async {
                                  try {
                                    final radius = double.tryParse(_triggerRadiusController.text) ?? 12.0;
                                    final spacing = math.max(1.0, radius - 2.0);
                                    final created = await getIt<RecorderService>().stopRecording(
                                      spacingMeters: spacing,
                                      triggerRadiusMeters: radius,
                                    );
                                    if (!mounted) return;
                                    setState(() {
                                      _lastTriggers = created;
                                      _isRecording = false;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Recording stopped and triggers created')),
                                    );
                                    await _refreshMapData();
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() => _isRecording = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('No se pudo frenar la grabación: $e')),
                                    );
                                  }
                                },
                          child: const Text('Frenar grabación'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                    ],
                  ),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Panel: Diagnóstico'),
                    children: [
                      const SizedBox(height: 8),
                      const Text('Radio de activación (debug):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _activationRadiusController,
                            decoration: const InputDecoration(
                              labelText: 'Radio (m)',
                              hintText: 'Ej: 15',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final radius = double.tryParse(_activationRadiusController.text) ?? 15.0;
                            await LocationConfig.saveActivationRadius(radius);
                            setState(() {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Radio de activación guardado: ${radius.toStringAsFixed(1)}m')),
                              );
                            }
                          },
                          child: const Text('Guardar'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text('Círculo morado en mapa muestra el área de activación actual', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: TriggerMapWidget(
                          paths: _mapPaths,
                          triggers: _mapTriggers,
                          triggerRadius: LocationConfig.activationRadiusMeters,
                          activationRadius: LocationConfig.activationRadiusMeters,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Last triggers: ${_lastTriggers.length}'),
                      const SizedBox(height: 8),
                      Row(children: [
                        ElevatedButton(
                          onPressed: () async {
                            await _refreshMapData();
                            final recent = getIt<LogService>().recent.reversed.toList(growable: false);
                            if (mounted) setState(() => _logs = recent);
                          },
                          child: const Text('Refresh mapa & logs'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            context.read<PlaybackNotifier>().clearLogs();
                            getIt<LogService>().clear();
                            setState(() => _logs = []);
                          },
                          child: const Text('Clear logs'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
                              MaterialPageRoute(builder: (_) => const DataBrowserPage()),
                            );
                            if (changed == true) {
                              await _refreshMapData();
                            }
                          },
                          icon: const Icon(Icons.table_chart),
                          label: const Text('Ver tablas de BD'),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 8),
                    ],
                  ),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Panel: Sincronización'),
                    children: [
                      const SizedBox(height: 8),
                      Text('Cursor servidor: ${_serverCursor ?? '-'}'),
                      Text('Última sync: ${_lastSync?.toIso8601String() ?? '-'}'),
                      Text('Outbox pendiente: $_outboxCount'),
                      Text('Estado: $_syncStatusLabel'),
                      Text('Backend: ${ApiConfig.baseUrl}'),
                      Text('API key: ${ApiConfig.apiKey.isEmpty ? 'NO CONFIGURADA' : 'configurada (${ApiConfig.apiKey.length} chars)'}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await _refreshSyncStatus();
                            },
                            child: const Text('Refrescar estado'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              try {
                                final result = await getIt<RunSyncUseCase>().pushOutboxOnce(limit: 100);
                                await _refreshSyncStatus();
                                if (!mounted) return;
                                final message = result.hadWork
                                    ? 'Push outbox: ${result.acked}/${result.totalOutbox} acked (cursor ${result.serverCursor ?? '-'})'
                                    : 'No hay outbox pendiente';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              } catch (e) {
                                debugPrint('CINGULA SYNC ERROR (manual push): $e');
                                getIt<LogService>().log('Error en sync: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error en sync: $e')),
                                  );
                                }
                              }
                            },
                            child: const Text('Forzar push ahora'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                final repaired = await getIt<SyncLocalDataSource>().repairDeleteOutboxPayloads();
                                getIt<LogService>().log('Reparación outbox: $repaired filas de delete corregidas');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Reparadas $repaired filas de delete en outbox')),
                                  );
                                }
                              } catch (e) {
                                debugPrint('CINGULA SYNC ERROR (repair): $e');
                                getIt<LogService>().log('Error al reparar outbox: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error al reparar: $e')),
                                  );
                                }
                              }
                            },
                            child: const Text('Reparar deletes viejos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  // Padding para evitar que la barra de navegación tape los últimos elementos.
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ])
              : const Text('Cargando...'),
        ]),
      ),
    );
  }
}
