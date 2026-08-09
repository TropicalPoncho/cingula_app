import 'dart:io';

/// Evento one-shot: la base no abría y se recuperó renombrando el archivo.
class DatabaseRecoveryEvent {
  const DatabaseRecoveryEvent({required this.backupPath});

  final String backupPath;

  /// Nombre del archivo de respaldo, sin directorio (para mostrar en la UI).
  String get backupFileName =>
      backupPath.split(RegExp(r'[/\\]')).last;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Formato de timestamp fijado por 01-UI-SPEC.md: yyyyMMdd-HHmmss.
String formatRecoveryTimestamp(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}${_two(now.month)}${_two(now.day)}'
    '-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

/// Renombra el archivo de base de datos que no pudo abrirse a
/// `dbPath` + `.corrupto-yyyyMMdd-HHmmss`, dejándolo intacto y accesible.
///
/// NUNCA borra: si el rename falla, la excepción se propaga para que el
/// llamador aborte en vez de destruir datos (DATA-01).
/// Devuelve la ruta del respaldo, o null si no había archivo que respaldar.
Future<String?> renameCorruptDatabase(String dbPath, DateTime now) async {
  final file = File(dbPath);
  if (!await file.exists()) return null;

  final backupPath = '$dbPath.corrupto-${formatRecoveryTimestamp(now)}';
  await file.rename(backupPath);

  // Los sidecars de SQLite pertenecen al archivo viejo: si quedan junto a la
  // ruta limpia, SQLite los aplicaría sobre la base nueva y la corrompería.
  for (final suffix in const ['-journal', '-wal', '-shm']) {
    final sidecar = File('$dbPath$suffix');
    if (await sidecar.exists()) {
      await sidecar.rename('$backupPath$suffix');
    }
  }

  return backupPath;
}
