import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:file_picker/file_picker.dart';

import '../../domain/entities/geo_path.dart';
import '../../domain/entities/geo_trigger.dart';
import '../../domain/entities/region.dart';
import '../../domain/entities/audio_asset.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/repositories/region_repository.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../domain/repositories/audio_playback_gateway.dart';
import '../../core/services/log_service.dart';
import '../../data/datasources/local/app_database.dart';

class DataBrowserPage extends StatefulWidget {
  const DataBrowserPage({super.key});

  @override
  State<DataBrowserPage> createState() => _DataBrowserPageState();
}

class _DataBrowserPageState extends State<DataBrowserPage> {
  List<GeoPath> _paths = [];
  List<GeoTrigger> _triggers = [];
  List<Region> _regions = [];
  List<AudioAsset> _audios = [];
  bool _loading = true;
  bool _dirty = false;
  final _getIt = GetIt.instance;

  String _fmt(DateTime? dt) => dt == null ? '-' : dt.toIso8601String();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pathRepo = _getIt<GeoPathRepository>();
      final triggerRepo = _getIt<GeoTriggerRepository>();
      final regionRepo = _getIt<RegionRepository>();
      final audioRepo = _getIt<AudioRepository>();

      final paths = await pathRepo.fetchAll();
      final triggers = await triggerRepo.fetchAll();
      final regions = await regionRepo.fetchAll();
      final audios = await audioRepo.fetchAll();
      if (mounted) {
        setState(() {
          _paths = paths;
          _triggers = triggers;
          _regions = regions;
          _audios = audios;
        });
      }
    } catch (e) {
      _getIt<LogService>().log('DataBrowser load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePath(GeoPath path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar path'),
        content: Text('Se eliminará el path "${path.name}" y sus triggers asociados. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final deleted = await _getIt<GeoPathRepository>().deleteById(path.id);
      _dirty = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Path eliminado (filas afectadas: $deleted)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      }
    }
  }

  Future<void> _recreateDb() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Advertencia'),
        content: const Text('Esto BORRARÁ TODOS los datos grabados incluyendo rutas de prueba. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar todo')),
        ],
      ),
    );
    if (confirm != true) return;
    final db = _getIt<AppDatabase>();
    await db.recreateForTesting();
    _dirty = true;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Database recreada (debug)')),
      );
    }
  }

  Future<void> _exportDb() async {
    try {
      final db = _getIt<AppDatabase>();
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
  }

  Future<void> _cleanupOrphanTriggers() async {
    try {
      final triggerRepo = _getIt<GeoTriggerRepository>();
      final deleted = await triggerRepo.deleteOrphaned();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Triggers huérfanos eliminados: $deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo limpiar triggers huérfanos: $e')),
      );
    }
  }

  Future<void> _importDb() async {
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
      if (confirm != true) return;
      final db = _getIt<AppDatabase>();
      await db.importDatabase(filePath);
      _dirty = true;
      await _load();
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
  }

  Future<void> _showStats() async {
    final db = _getIt<AppDatabase>();
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
  }

  String _regionNameForPath(GeoPath path) {
    // Busca la primera región asociada a cualquier trigger del path; si no hay, devuelve '-'.
    int? regionId;
    for (final t in _triggers) {
      if (t.geoPathId == path.id && t.regionId != null) {
        regionId = t.regionId;
        break;
      }
    }
    if (regionId == null) return '-';
    for (final r in _regions) {
      if (r.id == regionId) return r.name;
    }
    return '-';
  }

  String _audioNameForPath(GeoPath path) {
    // Evitar orElse de firstWhere por diferencias de tipo en fakes/modelos.
    for (final a in _audios) {
      if (a.id == path.audioAssetId) {
        return a.title;
      }
    }
    return 'Audio no encontrado';
  }

  Future<void> _playPathAudio(GeoPath path) async {
    final audioRepo = _getIt<AudioRepository>();
    final gateway = _getIt<AudioPlaybackGateway>();
    final audio = await audioRepo.findById(path.audioAssetId);
    if (audio == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio no encontrado para este path')),
        );
      }
      return;
    }
    try {
      if (path.savedOffsetMs > 0) {
        await gateway.playFrom(audio, Duration(milliseconds: path.savedOffsetMs));
      } else {
        await gateway.play(audio);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reproduciendo: ${audio.title}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reproducir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pathById = {for (final p in _paths) p.id: p};

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_dirty);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Datos de la BD (debug)'),
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(onPressed: _recreateDb, child: const Text('Recreate DB (debug)')),
                      ElevatedButton.icon(onPressed: _exportDb, icon: const Icon(Icons.upload_file), label: const Text('Exportar BD')),
                      ElevatedButton.icon(onPressed: _importDb, icon: const Icon(Icons.download), label: const Text('Importar BD')),
                      OutlinedButton.icon(onPressed: _showStats, icon: const Icon(Icons.info_outline), label: const Text('Ver contenido BD')),
                      OutlinedButton.icon(onPressed: _cleanupOrphanTriggers, icon: const Icon(Icons.cleaning_services_outlined), label: const Text('Limpiar triggers huérfanos')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Paths', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('id')),
                        DataColumn(label: Text('name')),
                        DataColumn(label: Text('region')),
                        DataColumn(label: Text('audio')),
                        DataColumn(label: Text('tolerance')),
                        DataColumn(label: Text('offset_ms')),
                        DataColumn(label: Text('uuid')),
                        DataColumn(label: Text('updated_at')),
                        DataColumn(label: Text('vlog')),
                        DataColumn(label: Text('acciones')),
                      ],
                      rows: _paths
                          .map(
                            (p) => DataRow(cells: [
                              DataCell(Text('${p.id}')),
                              DataCell(Text(p.name)),
                              DataCell(Text(_regionNameForPath(p))),
                              DataCell(Text(_audioNameForPath(p))),
                              DataCell(Text(p.toleranceMeters.toStringAsFixed(1))),
                              DataCell(Text('${p.savedOffsetMs}')),
                              DataCell(Text(p.uuid ?? '-')),
                              DataCell(Text(_fmt(p.updatedAt))),
                              DataCell(Text('${p.logicalVersion ?? '-'}')),
                              DataCell(
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow, color: Colors.teal),
                                      onPressed: () => _playPathAudio(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                                      onPressed: () => _deletePath(p),
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Triggers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('id')),
                        DataColumn(label: Text('lat')),
                        DataColumn(label: Text('lon')),
                        DataColumn(label: Text('radius')),
                        DataColumn(label: Text('offset_ms')),
                        DataColumn(label: Text('audio')),
                        DataColumn(label: Text('path name')),
                        DataColumn(label: Text('uuid')),
                        DataColumn(label: Text('updated_at')),
                        DataColumn(label: Text('vlog')),
                      ],
                      rows: _triggers
                          .map(
                            (t) => DataRow(cells: [
                              DataCell(Text('${t.id}')),
                              DataCell(Text(t.latitude.toStringAsFixed(6))),
                              DataCell(Text(t.longitude.toStringAsFixed(6))),
                              DataCell(Text(t.radiusMeters.toStringAsFixed(1))),
                              DataCell(Text('${t.offsetMs}')),
                              DataCell(Text('${t.audioAssetId}')),
                              DataCell(Text(pathById[t.geoPathId]?.name ?? '-')),
                              DataCell(Text(t.uuid ?? '-')),
                              DataCell(Text(_fmt(t.updatedAt))),
                              DataCell(Text('${t.logicalVersion ?? '-'}')),
                            ]),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
