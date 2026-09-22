import 'package:sqflite/sqflite.dart';

/// Datos iniciales para que la app funcione offline desde el arranque.
///
/// Corre dentro de `_onCreate` (instalación limpia): sin `enqueueOutbox`, igual
/// que antes. Los uuid son literales fijos (no generados) para que una
/// instalación limpia y un celular migrado nunca puedan chocar (D-32).
class SeedData {
  static const _audioMilPuertasUuid = '00000000-0000-4000-8000-000000000001';
  static const _audioOleajeUuid = '00000000-0000-4000-8000-000000000002';
  static const _obraUuid = '00000000-0000-4000-8000-000000000010';
  static const _pathUuid = '00000000-0000-4000-8000-000000000020';
  static const _triggerUuid = '00000000-0000-4000-8000-000000000030';

  static Future<void> seed(Database db) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final batch = db.batch();

    batch.insert('audios', {
      'uuid': _audioMilPuertasUuid,
      'kind': 'grabacion',
      'title': 'Mil Puertas',
      'description': 'Poema de vel: Mil Puertas.',
      'duration_seconds': 89,
      'updated_at': nowSec,
      'logical_version': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    batch.insert('audio_local', {
      'audio_uuid': _audioMilPuertasUuid,
      'local_path': 'assets/audio/mil_puertas.wav',
      'remote_url': 'https://example.com/audio/bosque_tropical.mp3',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    batch.insert('audios', {
      'uuid': _audioOleajeUuid,
      'kind': 'grabacion',
      'title': 'Oleaje marino',
      'description': 'Sonido de olas suaves para acompañar paseos costeros.',
      'duration_seconds': 150,
      'updated_at': nowSec,
      'logical_version': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    batch.insert('audio_local', {
      'audio_uuid': _audioOleajeUuid,
      // Reutilizamos el asset existente hasta que se agregue el mp3 final.
      'local_path': 'assets/audio/mil_puertas.wav',
      'remote_url': 'https://example.com/audio/oleaje_marino.mp3',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    batch.insert('obras', {
      'uuid': _obraUuid,
      'name': 'Paseo costero demo',
      'visibility': 'draft',
      'updated_at': nowSec,
      'logical_version': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    batch.insert('paths', {
      'uuid': _pathUuid,
      'obra_uuid': _obraUuid,
      'kind': 'route',
      'name': 'Paseo costero demo',
      'audio_uuid': _audioOleajeUuid,
      'tolerance_meters': 20.0,
      'updated_at': nowSec,
      'logical_version': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    batch.insert('triggers', {
      'uuid': _triggerUuid,
      'path_uuid': _pathUuid,
      'position': 0,
      'name': 'Malecón Guayaquil',
      'description': 'Zona principal del malecón',
      'latitude': -34.786151,
      'longitude': -58.409156,
      'radius_meters': 10.0,
      'updated_at': nowSec,
      'logical_version': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await batch.commit(noResult: true);
  }
}
