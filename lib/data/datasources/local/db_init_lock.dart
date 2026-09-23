import 'dart:io';

/// Serializa `AppDatabase.init()` entre isolates (D-34).
///
/// El isolate principal (arranque de la app) y el isolate de `WorkManager`
/// (background_worker.dart) pueden llamar a `AppDatabase.init()` casi al
/// mismo tiempo — cada uno con su propio `AppDatabase` (`reinitialize: true`
/// en el service locator), apuntando al mismo archivo. `sqflite` no tolera
/// esa carrera: tira `DatabaseException(database_closed ...)`, una excepción
/// cruda que ni D-25 ni el guard de respaldo reconocen, y que sin este lock
/// cae en el camino generico de "base corrupta" aunque no haya nada corrupto.
///
/// Lock a nivel de sistema operativo (`dart:io`, sin dependencia nueva):
/// funciona entre isolates/engines separados, a diferencia de un lock en
/// memoria Dart (esos son por isolate, no sirven acá).
Future<T> withDbInitLock<T>(String dbPath, Future<T> Function() body) async {
  // append, no write: write trunca el archivo, y truncar mientras otro handle
  // lo tiene lockeado se comporta de forma inconsistente en Windows.
  final raf = await File('$dbPath.initlock').open(mode: FileMode.append);
  // blockingExclusive, NO exclusive: en Windows, FileLock.exclusive NO espera
  // — falla al toque si el lock esta tomado (PathAccessException), a
  // diferencia de flock() en Linux/Android que si espera. blockingExclusive
  // es el que realmente bloquea en las dos plataformas.
  var locked = false;
  try {
    await raf.lock(FileLock.blockingExclusive);
    locked = true;
    return await body();
  } finally {
    if (locked) await raf.unlock();
    await raf.close();
  }
}
