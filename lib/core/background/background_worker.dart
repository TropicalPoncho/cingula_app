import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/datasources/local/app_database.dart';
import '../../data/migration/sqlite_header.dart';
import '../../domain/usecases/monitor_user_location_usecase.dart';
import '../di/service_locator.dart';

const String kBackgroundMonitorTask = 'cingula_background_monitor';

/// Configura tareas periódicas que consultan la ubicación en segundo plano.
class BackgroundWorker {
  Future<void> ensureInitialized() async {
    // En iOS el plugin Workmanager no aplica; lo limitamos a Android.
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(
      callbackDispatcher
    );
    await registerPeriodicMonitor();
  }

  Future<void> registerPeriodicMonitor() async {
    if (!Platform.isAndroid) return;
    // Cada 15 minutos revisamos la posición del usuario para disparar audios.
    await Workmanager().registerPeriodicTask(
      kBackgroundMonitorTask,
      kBackgroundMonitorTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }
}

/// Entry point que Workmanager usa fuera del isolate principal.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    // D-34: este isolate y el principal pueden correr casi al mismo tiempo,
    // en el mismo proceso — un lock de archivo no los serializa (POSIX es
    // por proceso, no por isolate). En vez de abrir la base por sqflite acá
    // (y competir con el isolate principal si todavía está migrando), leemos
    // la version cruda del archivo. Si no llegó a v7 todavía, no tocamos
    // nada: nos salteamos este tick, el próximo (15 min) ya la va a
    // encontrar migrada.
    final dbPath = p.join((await getApplicationDocumentsDirectory()).path, 'cingula.db');
    final version = await readSqliteUserVersionRaw(dbPath);
    if (version == null || version < AppDatabase.dbVersion) {
      return Future.value(true);
    }

    // Restauramos el service locator porque este isolate inicia limpio.
    await setupServiceLocator(reinitialize: true);
    final monitorUseCase = getIt<MonitorUserLocationUseCase>();
    await monitorUseCase.executeSingleCheck();
    return Future.value(true);
  });
}

