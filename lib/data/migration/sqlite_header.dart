import 'dart:io';
import 'dart:typed_data';

/// Lee `PRAGMA user_version` directo de los bytes del header SQLite, SIN pasar
/// por `sqflite` (D-34).
///
/// Por qué: el isolate de `WorkManager` (background_worker.dart) y el isolate
/// principal pueden intentar abrir la misma base casi al mismo tiempo. Un lock
/// de archivo no ayuda acá — ambos corren en el mismo proceso del SO (dos
/// engines Flutter, un solo PID), y los locks POSIX (`fcntl`, lo que usa
/// Android) son por proceso: un proceso no se bloquea a si mismo. La solucion
/// real es que el isolate de background NUNCA abra la base por `sqflite`
/// mientras la migracion podria seguir en curso — y para decidir eso no hace
/// falta abrir nada: el numero de version vive en un lugar fijo y documentado
/// del formato del archivo (https://www.sqlite.org/fileformat.html — offset
/// 60, 4 bytes big-endian), el mismo valor que `PRAGMA user_version` expone.
/// Leerlo con `dart:io` puro no compite con ninguna conexion sqflite.
///
/// Devuelve null si el archivo no existe, es demasiado corto, o no tiene la
/// firma SQLite esperada — en cualquiera de esos casos, tratarlo como "no
/// tocar todavia" es lo seguro.
Future<int?> readSqliteUserVersionRaw(String dbPath) async {
  final file = File(dbPath);
  if (!file.existsSync()) return null;

  RandomAccessFile? raf;
  try {
    raf = await file.open();
    if (await raf.length() < 64) return null;

    final header = await raf.read(16);
    const magic = 'SQLite format 3\x00';
    if (header.length != 16 || String.fromCharCodes(header) != magic) return null;

    await raf.setPosition(60);
    final versionBytes = await raf.read(4);
    if (versionBytes.length != 4) return null;
    return ByteData.sublistView(Uint8List.fromList(versionBytes)).getUint32(0, Endian.big);
  } catch (_) {
    return null;
  } finally {
    await raf?.close();
  }
}
