import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../domain/entities/geo_path.dart';
import '../../domain/entities/geo_trigger.dart';
import '../../domain/entities/audio_asset.dart';
import '../../domain/entities/obra.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../domain/repositories/obra_repository.dart';
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
  List<AudioAsset> _audios = [];
  List<Obra> _obras = [];
  bool _loading = true;
  bool _dirty = false;
  final _getIt = GetIt.instance;
  final TextEditingController _newAudioTitle = TextEditingController(text: 'Nuevo audio');
  final TextEditingController _newAudioPath = TextEditingController(text: 'assets/audio/');

  String _fmt(DateTime? dt) => dt == null ? '-' : dt.toIso8601String();

  /// Loguea a consola (debugPrint) y al panel de diagnóstico (LogService) antes de mostrar el
  /// SnackBar transitorio -- sin esto, un error que el usuario no llega a leer a tiempo se pierde
  /// para siempre (mismo bug que tenía SyncTrigger antes de agregarle onError).
  void _reportError(String label, Object e) {
    debugPrint('CINGULA APP ERROR ($label): $e');
    _getIt<LogService>().log('$label: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newAudioTitle.dispose();
    _newAudioPath.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pathRepo = _getIt<GeoPathRepository>();
      final triggerRepo = _getIt<GeoTriggerRepository>();
      final audioRepo = _getIt<AudioRepository>();
      final obraRepo = _getIt<ObraRepository>();

      final paths = await pathRepo.fetchAll();
      final triggers = await triggerRepo.fetchAll();
      final audios = await audioRepo.fetchAll();
      final obras = await obraRepo.fetchAll();
      if (mounted) {
        setState(() {
          _paths = paths;
          _triggers = triggers;
          _audios = audios;
          _obras = obras;
        });
      }
    } catch (e) {
      _reportError('Error cargando datos', e);
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
      final deleted = await _getIt<GeoPathRepository>().deleteByUuid(path.uuid);
      _dirty = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Path eliminado (filas afectadas: $deleted)')),
        );
      }
    } catch (e) {
      _reportError('No se pudo eliminar', e);
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
      _reportError('Error al exportar', e);
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
      _reportError('No se pudo limpiar triggers huérfanos', e);
    }
  }

  Future<void> _addAudioAsset() async {
    final title = _newAudioTitle.text.trim();
    final path = _newAudioPath.text.trim();
    if (title.isEmpty || path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Título y path son obligatorios')),
        );
      }
      return;
    }

    try {
      final uuid = await _getIt<AudioRepository>().insertLocalRecording(
        title: title,
        description: 'Asset manual',
        localPath: path,
        duration: Duration.zero,
      );
      _dirty = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio agregado (uuid: $uuid)')),
        );
      }
    } catch (e) {
      _reportError('No se pudo agregar audio', e);
    }
  }

  Future<void> _resetPathProgress(GeoPath path) async {
    try {
      await _getIt<GeoPathRepository>().saveProgress(path.uuid, 0);
      _dirty = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Progreso reiniciado para "${path.name}"')),
        );
      }
    } catch (e) {
      _reportError('No se pudo reiniciar', e);
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
            Text('🎵 Audios: ${stats['audios']}'),
            const SizedBox(height: 8),
            Text('🎭 Obras: ${stats['obras']}'),
            const SizedBox(height: 8),
            Text('📍 Triggers: ${stats['triggers']}'),
            const SizedBox(height: 8),
            Text('🛤️  Paths: ${stats['paths']}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  String _audioNameForPath(GeoPath path) {
    final audioUuid = path.audioUuid;
    if (audioUuid == null) return 'Sin audio asignado';
    // Evitar orElse de firstWhere por diferencias de tipo en fakes/modelos.
    for (final a in _audios) {
      if (a.uuid == audioUuid) {
        return a.title;
      }
    }
    return 'Audio no encontrado';
  }

  Future<void> _playPathAudio(GeoPath path) async {
    final audioRepo = _getIt<AudioRepository>();
    final gateway = _getIt<AudioPlaybackGateway>();
    final audioUuid = path.audioUuid;
    final audio = audioUuid == null ? null : await audioRepo.findByUuid(audioUuid);
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
      _reportError('No se pudo reproducir', e);
    }
  }

  Future<void> _changePathAudio(GeoPath path) async {
    if (_audios.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay audios disponibles para asignar')),
        );
      }
      return;
    }

    String? selectedAudioUuid = path.audioUuid ?? _audios.first.uuid;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Cambiar audio del path'),
            content: DropdownButton<String>(
              value: selectedAudioUuid,
              items: _audios
                  .map((a) => DropdownMenuItem<String>(value: a.uuid, child: Text(a.title)))
                  .toList(growable: false),
              onChanged: (v) {
                if (v != null) {
                  setStateDialog(() => selectedAudioUuid = v);
                }
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
            ],
          ),
        );
      },
    );

    if (confirmed != true || selectedAudioUuid == path.audioUuid) return;

    try {
      await _getIt<GeoPathRepository>().updateAudio(pathUuid: path.uuid, audioUuid: selectedAudioUuid!);
      _dirty = true;
      await _load();
      if (mounted) {
        // Evitar orElse de firstWhere por diferencias de tipo en fakes/modelos (ver _audioNameForPath).
        var newAudioTitle = 'audio';
        for (final a in _audios) {
          if (a.uuid == selectedAudioUuid) {
            newAudioTitle = a.title;
            break;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio actualizado a "$newAudioTitle"')),
        );
      }
    } catch (e) {
      _reportError('No se pudo actualizar', e);
    }
  }

  String _short(String uuid) => uuid.length <= 8 ? uuid : uuid.substring(0, 8);

  /// Nombre de la obra por uuid; si no aparece (referencia colgante), el uuid recortado.
  String _obraNameFor(String obraUuid) {
    for (final o in _obras) {
      if (o.uuid == obraUuid) return o.name;
    }
    return _short(obraUuid);
  }

  @override
  Widget build(BuildContext context) {
    final pathByUuid = {for (final p in _paths) p.uuid: p};

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
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(onPressed: _exportDb, icon: const Icon(Icons.upload_file), label: const Text('Exportar BD')),
                      OutlinedButton.icon(onPressed: _showStats, icon: const Icon(Icons.info_outline), label: const Text('Ver contenido BD')),
                      OutlinedButton.icon(onPressed: _cleanupOrphanTriggers, icon: const Icon(Icons.cleaning_services_outlined), label: const Text('Limpiar triggers huérfanos')),
                      Text('Obras: ${_obras.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Agregar audio manual a la tabla', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _newAudioTitle,
                          decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder(), isDense: true),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _newAudioPath,
                          decoration: const InputDecoration(labelText: 'Asset o path local', hintText: 'assets/audio/tu_audio.wav', border: OutlineInputBorder(), isDense: true),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: _addAudioAsset,
                            icon: const Icon(Icons.add),
                            label: const Text('Guardar en audio_assets'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Paths', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('uuid')),
                        DataColumn(label: Text('obra')),
                        DataColumn(label: Text('name')),
                        DataColumn(label: Text('audio')),
                        DataColumn(label: Text('tolerance')),
                        DataColumn(label: Text('offset_ms')),
                        DataColumn(label: Text('updated_at')),
                        DataColumn(label: Text('vlog')),
                        DataColumn(label: Text('acciones')),
                      ],
                      rows: _paths
                          .map(
                            (p) => DataRow(cells: [
                              DataCell(Text(_short(p.uuid))),
                              DataCell(Text(_obraNameFor(p.obraUuid))),
                              DataCell(Text(p.name)),
                              DataCell(Text(_audioNameForPath(p))),
                              DataCell(Text(p.toleranceMeters.toStringAsFixed(1))),
                              DataCell(Text('${p.savedOffsetMs}')),
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
                                      icon: const Icon(Icons.replay, color: Colors.orange),
                                      tooltip: 'Reiniciar progreso (offset=0)',
                                      onPressed: () => _resetPathProgress(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.library_music, color: Colors.indigo),
                                      tooltip: 'Cambiar audio',
                                      onPressed: () => _changePathAudio(p),
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
                        DataColumn(label: Text('uuid')),
                        DataColumn(label: Text('lat')),
                        DataColumn(label: Text('lon')),
                        DataColumn(label: Text('radius')),
                        DataColumn(label: Text('offset_ms')),
                        DataColumn(label: Text('path name')),
                        DataColumn(label: Text('path_uuid')),
                        DataColumn(label: Text('updated_at')),
                        DataColumn(label: Text('vlog')),
                      ],
                      rows: _triggers
                          .map(
                            (t) => DataRow(cells: [
                              DataCell(Text(_short(t.uuid))),
                              DataCell(Text(t.latitude.toStringAsFixed(6))),
                              DataCell(Text(t.longitude.toStringAsFixed(6))),
                              DataCell(Text(t.radiusMeters.toStringAsFixed(1))),
                              DataCell(Text('${t.offsetMs}')),
                              DataCell(Text(pathByUuid[t.pathUuid]?.name ?? '-')),
                              DataCell(Text(_short(t.pathUuid))),
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
