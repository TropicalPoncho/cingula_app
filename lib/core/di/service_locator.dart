import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';

import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/audio_local_data_source.dart';
import '../../data/datasources/local/geo_trigger_local_data_source.dart';
import '../../data/datasources/local/geo_path_local_data_source.dart';
import '../../data/datasources/local/region_local_data_source.dart';
import '../../data/datasources/local/sync_local_data_source.dart';
import '../../data/sync/sync_api.dart';
import '../../data/sync/sync_client.dart';
import '../../data/sync/sync_api_http.dart';
import '../../data/repositories/region_repository_impl.dart';
import '../../domain/repositories/region_repository.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../services/log_service.dart';
import '../services/geofence_background_service.dart';
import '../../data/repositories/audio_playback_gateway_impl.dart';
import '../../data/repositories/audio_repository_impl.dart';
import '../../data/repositories/geo_trigger_repository_impl.dart';
import '../../data/repositories/geo_path_repository_impl.dart';
import '../../data/repositories/location_repository_impl.dart';
import '../../domain/repositories/audio_playback_gateway.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../../domain/usecases/monitor_user_location_usecase.dart';
import '../../domain/usecases/run_sync_usecase.dart';
import '../../data/sync/sync_trigger.dart';
import '../services/audio_player_service.dart';
import '../services/recorder_service.dart';
import '../services/notification_service.dart';

final getIt = GetIt.instance;
StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

/// Registra cada dependencia de la app siguiendo el patrón service locator.
Future<void> setupServiceLocator({bool reinitialize = false}) async {
  if (reinitialize) {
    // Durante ejecuciones en segundo plano reseteamos el contenedor para evitar duplicados.
    await getIt.reset();
  } else if (getIt.isRegistered<AppDatabase>()) {
    return;
  }

  // Inicializamos la base de datos local y la exponemos como singleton.
  // No recreamos la base automáticamente para preservar datos creados en el campo.
  // No existe ninguna acción de recreado/reemplazo de BD: se eliminaron en la fase 01 (DATA-02).
  final database = AppDatabase();
  await database.init();
  getIt.registerSingleton<AppDatabase>(database);

  // Utilidades de sincronización (uuid, timestamps, outbox).
  getIt.registerLazySingleton<SyncLocalDataSource>(
    () => SyncLocalDataSource(database.database),
  );
  getIt.registerLazySingleton<SyncClient>(
    () => SyncClient(sync: getIt<SyncLocalDataSource>()),
  );
  // Backend real (Vercel Functions + Neon). Base URL y API key vienen por --dart-define:
  //   --dart-define=CINGULA_API_BASE_URL=https://<proyecto>.vercel.app
  //   --dart-define=CINGULA_SYNC_API_KEY=<token>
  getIt.registerLazySingleton<SyncApi>(
    () => SyncApiHttp(),
  );

  getIt.registerLazySingleton<RunSyncUseCase>(
    () => RunSyncUseCase(
      client: getIt<SyncClient>(),
      api: getIt<SyncApi>(),
    ),
  );

  // Disparo automático de push: tras cada escritura local (D-04) y al recuperar red (D-05).
  // onError vuelca el mensaje completo de la excepción al LogService: el status stream por sí
  // solo (idle/running/ok/transientError/authError) no alcanza para debuggear qué falló.
  getIt.registerLazySingleton<SyncTrigger>(
    () => SyncTrigger(
      runSync: getIt<RunSyncUseCase>(),
      onError: (message) => getIt<LogService>().log('Sync error: $message'),
    ),
  );

  // D-04: toda escritura local pasa por enqueueOutbox, así que un solo cable alcanza.
  getIt<SyncLocalDataSource>().onOutboxEnqueued = () => getIt<SyncTrigger>().schedule();

  // D-05: al aparecer una interfaz de red, reintentar lo pendiente.
  // connectivity_plus reporta TIPO de interfaz, no alcanzabilidad real (puede decir
  // "conectado" en un portal cautivo sin internet). Por eso se usa sólo como pre-check
  // barato para decidir CUÁNDO intentar; la verdad sobre si el push funcionó sigue siendo
  // la respuesta HTTP.
  _connectivitySubscription?.cancel();
  _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) getIt<SyncTrigger>().schedule();
  });

  // Data sources encapsulan el acceso crudo a SQLite.
  getIt.registerLazySingleton<AudioLocalDataSource>(
    () => AudioLocalDataSource(database.database, getIt<SyncLocalDataSource>()),
  );
  getIt.registerLazySingleton<GeoTriggerLocalDataSource>(
    () => GeoTriggerLocalDataSource(database.database, getIt<SyncLocalDataSource>()),
  );
  getIt.registerLazySingleton<GeoPathLocalDataSource>(
    () => GeoPathLocalDataSource(database.database, getIt<SyncLocalDataSource>()),
  );
  getIt.registerLazySingleton<RegionLocalDataSource>(
    () => RegionLocalDataSource(database.database, getIt<SyncLocalDataSource>()),
  );

  // Repositorios de lectura apoyados en los data sources preparados.
  getIt.registerLazySingleton<AudioRepository>(
    () => AudioRepositoryImpl(
      localDataSource: getIt<AudioLocalDataSource>(),
    ),
  );
  getIt.registerLazySingleton<GeoTriggerRepository>(
    () => GeoTriggerRepositoryImpl(
      localDataSource: getIt<GeoTriggerLocalDataSource>(),
    ),
  );
  getIt.registerLazySingleton<GeoPathRepository>(
    () => GeoPathRepositoryImpl(
      localDataSource: getIt<GeoPathLocalDataSource>(),
    ),
  );
  getIt.registerLazySingleton<RegionRepository>(
    () => RegionRepositoryImpl(
      localDataSource: getIt<RegionLocalDataSource>(),
    ),
  );
  getIt.registerLazySingleton<LocationRepository>(
    () => LocationRepositoryImpl(),
  );

  // Servicio de geocercas para mantener tracking en background.
  getIt.registerLazySingleton<GeofenceBackgroundService>(
    () => GeofenceBackgroundService(),
  );

  // Simple in-memory log service for debug UI
  getIt.registerLazySingleton(() => LogService());

  // Notificaciones locales para mostrar estado de grabación.
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(),
  );
  await getIt<NotificationService>().init();

  // Gateway de reproducción con un servicio compartido de audio.
  getIt.registerLazySingleton<AudioPlayerService>(
    () => AudioPlayerService(),
  );
  getIt.registerLazySingleton<AudioPlaybackGateway>(
    () => AudioPlaybackGatewayImpl(
      playerService: getIt<AudioPlayerService>(),
      logService: getIt<LogService>(),
    ),
  );

  // Caso de uso que coordina ubicación + repositorios + reproducción.
  getIt.registerLazySingleton<MonitorUserLocationUseCase>(
    () => MonitorUserLocationUseCase(
      locationRepository: getIt<LocationRepository>(),
      geoTriggerRepository: getIt<GeoTriggerRepository>(),
      geoPathRepository: getIt<GeoPathRepository>(),
      audioRepository: getIt<AudioRepository>(),
      playbackGateway: getIt<AudioPlaybackGateway>(),
      geofenceBackgroundService: getIt<GeofenceBackgroundService>(),
    ),
  );

  // Recorder service (debug) to record paths and auto-generate triggers.
  getIt.registerLazySingleton<RecorderService>(
    () => RecorderService(
      locationRepository: getIt<LocationRepository>(),
      geoPathRepository: getIt<GeoPathRepository>(),
      geoTriggerRepository: getIt<GeoTriggerRepository>(),
      audioRepository: getIt<AudioRepository>(),
      notificationService: getIt<NotificationService>(),
    ),
  );
}

