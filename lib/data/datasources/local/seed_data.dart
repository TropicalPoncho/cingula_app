import 'package:sqflite/sqflite.dart';

/// Datos iniciales para que la app funcione offline desde el arranque.
class SeedData {
  static Future<void> seed(Database db) async {
    final batch = db.batch();

    for (final asset in _audioAssets) {
      batch.insert('audio_assets', asset, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (final trigger in _geoTriggers) {
      batch.insert('geo_triggers', trigger, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (final path in _geoPaths) {
      batch.insert('geo_paths', path, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
  }

  static const List<Map<String, Object?>> _audioAssets = [
    {
      'id': 1,
      'title': 'Mil Puertas',
      'artist': 'Vel',
      'description': 'Poema de vel: Mil Puertas.',
      'duration_seconds': 89,
      'local_path': 'assets/audio/mil_puertas.wav',
      'remote_url': 'https://example.com/audio/bosque_tropical.mp3',
    },
    {
      'id': 2,
      'title': 'Oleaje marino',
      'artist': 'Equipo Cingula',
      'description': 'Sonido de olas suaves para acompañar paseos costeros.',
      'duration_seconds': 150,
      // Reutilizamos el asset existente hasta que se agregue el mp3 final.
      'local_path': 'assets/audio/mil_puertas.wav',
      'remote_url': 'https://example.com/audio/oleaje_marino.mp3',
    },
  ];

  static const List<Map<String, Object?>> _geoTriggers = [
    {
      'id': 1,
      'name': 'Malecón Guayaquil',
      'description': 'Zona principal del malecón',
      'latitude': -34.786151,
      'longitude': -58.409156,
      'radius_meters': 10.0,
      'audio_asset_id': 1,
      'geo_path_id': 1,
    }
  ];

  static const List<Map<String, Object?>> _geoPaths = [
    {
      'id': 1,
      'name': 'Paseo costero demo',
      'points': '[{"lat": -2.1900, "lon": -79.8860}, {"lat": -2.1895, "lon": -79.8850}]',
      'audio_asset_id': 2,
      'tolerance_meters': 20.0,
      'saved_offset_ms': 0,
    },
  ];
}

