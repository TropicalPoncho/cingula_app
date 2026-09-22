import 'package:flutter/material.dart';

import '../../data/migration/db_backup.dart';
import '../../data/migration/v7_migration.dart';

/// Pantalla bloqueante que reemplaza a `CingulaApp` cuando la migración
/// v6→v7 falla (D-25). Los datos quedan intactos: el código nuevo no puede
/// operar sobre una base v6, así que no ofrece "continuar igual", y no tiene
/// ninguna acción destructiva (ni reintentar, ni borrar, ni recrear).
class MigrationFailureApp extends StatelessWidget {
  const MigrationFailureApp({required this.error, this.backupPath, super.key});

  final Object error;
  final String? backupPath;

  String get _message {
    final e = error;
    if (e is MigrationException) {
      final cause = e.cause;
      return cause == null ? e.message : '${e.message}\n\nCausa: $cause';
    }
    if (e is BackupFailedException) {
      return e.message;
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cingula',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'La migración de datos falló.',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tus datos están intactos.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(_message, style: const TextStyle(fontSize: 14)),
                  if (backupPath != null) ...[
                    const SizedBox(height: 16),
                    Text('Respaldo: $backupPath', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
