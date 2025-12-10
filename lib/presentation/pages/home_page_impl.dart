// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../domain/entities/audio_asset.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/services/recorder_service.dart';
import '../../data/datasources/local/app_database.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/entities/geo_trigger.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/entities/geo_path.dart';
import '../../domain/entities/region.dart';
import '../../domain/repositories/region_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../notifiers/playback_notifier.dart';
import '../../core/config/location_config.dart';
import '../widgets/trigger_map.dart';
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
  final double _recSampleDistance = 5.0;
  bool _isRecording = false;
  List<GeoTrigger> _lastTriggers = [];
  final TextEditingController _pathNameController = TextEditingController(text: 'Mi ruta');
  final TextEditingController _triggerRadiusController = TextEditingController(text: '12');

  // Map data
  List<GeoTrigger> _mapTriggers = [];
  List<GeoPath> _mapPaths = [];
  List<Region> _mapRegions = [];
  List<String> _logs = [];
  StreamSubscription<List<String>>? _logSub;

  // Crear región
  final TextEditingController _regionNameController = TextEditingController(text: 'Mi región');
  final TextEditingController _regionRadiusController = TextEditingController(text: '500');
  int? _selectedRegionId;
  
  // Radio de activación para debug
  final TextEditingController _activationRadiusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activationRadiusController.text = LocationConfig.activationRadiusMeters.toStringAsFixed(1);
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
      final regions = await getIt<RegionRepository>().fetchAll();
      if (mounted) {
        setState(() {
          _mapTriggers = triggers;
          _mapPaths = paths;
          _mapRegions = regions;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _pathNameController.dispose();
    _triggerRadiusController.dispose();
    _regionNameController.dispose();
    _regionRadiusController.dispose();
    _activationRadiusController.dispose();
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
                  // Selector de región
                  const Text('Región (opcional):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  _mapRegions.isEmpty
                      ? const Text('No hay regiones. Crea una abajo.', style: TextStyle(fontSize: 12, color: Colors.grey))
                      : DropdownButton<int?>(
                          value: _selectedRegionId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Sin región')),
                            ..._mapRegions.map((r) => DropdownMenuItem(value: r.id, child: Text('${r.name} (${r.radiusMeters.toStringAsFixed(0)}m)'))),
                          ],
                          onChanged: (v) => setState(() => _selectedRegionId = v),
                        ),
                  const SizedBox(height: 12),
                  const Text('Audio:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  _audioAssets.isEmpty
                      ? const Text('No hay audios disponibles')
                      : DropdownButton<int>(
                          value: _selectedAudioId,
                          items: _audioAssets.map((a) => DropdownMenuItem(value: a.id, child: Text(a.title))).toList(growable: false),
                          onChanged: (v) => setState(() => _selectedAudioId = v),
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
                  const SizedBox(height: 16),
                  const Divider(),
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
                        setState(() {}); // Refresh map
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Radio de activación guardado: ${radius.toStringAsFixed(1)}m')));
                      },
                      child: const Text('Guardar'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('Círculo morado en mapa muestra el área de activación actual', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Crear Región:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _regionNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la región',
                      hintText: 'Ej: Centro ciudad',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _regionRadiusController,
                    decoration: const InputDecoration(
                      labelText: 'Radio de región (m)',
                      hintText: 'Ej: 500',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final name = _regionNameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresa un nombre para la región')),
                          );
                          return;
                        }
                        final radius = double.tryParse(_regionRadiusController.text) ?? 500;
                        if (radius < 10) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('El radio debe ser al menos 10m')),
                          );
                          return;
                        }
                        // Obtener posición actual
                        final location = getIt<LocationRepository>();
                        await location.ensureServiceAndPermissions();
                        final pos = await location.currentPosition();
                        
                        final regionId = await getIt<RegionRepository>().createRegion(
                          name: name,
                          latitude: pos.latitude,
                          longitude: pos.longitude,
                          radiusMeters: radius,
                        );
                        
                        await _refreshMapData();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Región "$name" creada (ID: $regionId)')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al crear región: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.add_location),
                    label: const Text('Crear región en posición actual'),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
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
                                await getIt<RecorderService>().startRecordingWithMic(
                                  name: pathName,
                                  sampleDistanceMeters: _recSampleDistance,
                                  spacingMeters: spacing,
                                  triggerRadiusMeters: radius,
                                );
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
                              final radius = double.tryParse(_triggerRadiusController.text) ?? 12.0;
                              final spacing = math.max(1.0, radius - 2.0);
                              final created = await getIt<RecorderService>().stopRecording(
                                spacingMeters: spacing,
                                triggerRadiusMeters: radius,
                              );
                              setState(() {
                                _lastTriggers = created;
                                _isRecording = false;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording stopped and triggers created')));
                              }
                              await _refreshMapData();
                            },
                      child: const Text('Frenar grabación'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('⚠️ Advertencia'),
                            content: const Text('Esto BORRARÁ TODOS los datos grabados incluyendo tus rutas de prueba. ¿Continuar?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar todo')),
                            ],
                          ),
                        );
                        if (confirm != true || !mounted) return;
                        final db = getIt<AppDatabase>();
                        await db.recreateForTesting();
                        await _refreshMapData();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database recreated (debug)')));
                      },
                      child: const Text('Recreate DB (debug)'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final db = getIt<AppDatabase>();
                          final exportPath = await db.exportDatabase();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('BD exportada a:\n$exportPath'),
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al exportar: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Exportar BD'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['db'],
                          );
                          if (result == null || result.files.isEmpty) return;
                          final filePath = result.files.first.path;
                          if (filePath == null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Error: no se pudo obtener la ruta del archivo')),
                              );
                            }
                            return;
                          }
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Importar BD'),
                              content: const Text('Esto reemplazará la base de datos actual. ¿Continuar?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importar')),
                              ],
                            ),
                          );
                          if (confirm != true || !mounted) return;
                          final db = getIt<AppDatabase>();
                          await db.importDatabase(filePath);
                          await _refreshMapData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('BD importada exitosamente')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al importar: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Importar BD'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final db = getIt<AppDatabase>();
                        final stats = await db.getDatabaseStats();
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Contenido de la BD'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🎵 Audio assets: ${stats['audio_assets']}'),
                                const SizedBox(height: 8),
                                Text('📍 Triggers: ${stats['geo_triggers']}'),
                                const SizedBox(height: 8),
                                Text('🛤️  Paths: ${stats['geo_paths']}'),
                                const SizedBox(height: 8),
                                Text('🗺️  Regions: ${stats['regions']}'),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Ver contenido BD'),
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
                  SizedBox(height: 180, child: TriggerMapWidget(
                    paths: _mapPaths, 
                    triggers: _mapTriggers, 
                    regions: _mapRegions,
                    activationRadius: LocationConfig.activationRadiusMeters,
                  )),
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
                      child: const Text('Refresh table & logs'),
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

// _MiniMapWidget replaced by reusable TriggerMapWidget in lib/presentation/widgets/trigger_map.dart
