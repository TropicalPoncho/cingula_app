import 'package:get_it/get_it.dart';

import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/audio_local_data_source.dart';
import '../../data/datasources/local/geo_trigger_local_data_source.dart';
import '../../data/datasources/local/geo_path_local_data_source.dart';
import '../../data/datasources/local/region_local_data_source.dart';
import '../../data/repositories/region_repository_impl.dart';
import '../../domain/repositories/region_repository.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../services/log_service.dart';
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
import '../services/audio_player_service.dart';
import '../services/recorder_service.dart';

final getIt = GetIt.instance;

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
  // Use AppDatabase.recreateForTesting() manualmente desde la UI/debug.
  final database = AppDatabase();
  await database.init();
  getIt.registerSingleton<AppDatabase>(database);

  // Data sources encapsulan el acceso crudo a SQLite.
  getIt.registerLazySingleton<AudioLocalDataSource>(
    () => AudioLocalDataSource(database.database),
  );
  getIt.registerLazySingleton<GeoTriggerLocalDataSource>(
    () => GeoTriggerLocalDataSource(database.database),
  );
  getIt.registerLazySingleton<GeoPathLocalDataSource>(
    () => GeoPathLocalDataSource(database.database),
  );
  getIt.registerLazySingleton<RegionLocalDataSource>(
    () => RegionLocalDataSource(database.database),
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

  // Simple in-memory log service for debug UI
  getIt.registerLazySingleton(() => LogService());

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
      regionRepository: getIt<RegionRepository>(),
      audioRepository: getIt<AudioRepository>(),
      playbackGateway: getIt<AudioPlaybackGateway>(),
    ),
  );

  // Recorder service (debug) to record paths and auto-generate triggers.
  getIt.registerLazySingleton<RecorderService>(
    () => RecorderService(
      locationRepository: getIt<LocationRepository>(),
      geoPathRepository: getIt<GeoPathRepository>(),
      geoTriggerRepository: getIt<GeoTriggerRepository>(),
      audioRepository: getIt<AudioRepository>(),
    ),
  );
}

