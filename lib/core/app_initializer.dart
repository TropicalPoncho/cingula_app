import 'background/background_worker.dart';
import 'config/app_mode_config.dart';
import 'config/location_config.dart';
import 'di/service_locator.dart';

/// Centraliza tareas de arranque: inyeccion de dependencias y trabajos en background.
class AppInitializer {
  Future<void> init() async {
    // Configuramos singletons y repositorios antes de usar la capa de dominio.
    await setupServiceLocator();
    // Cargar parámetros persistidos (incluye radio de activación).
    await LocationConfig.loadFromPrefs();
    // Modo de UI persistido (debug vs. usuario final).
    await AppModeConfig.loadFromPrefs();
    // Registramos la tarea periï¿½dica que consulta la ubicaciï¿½n.
    await BackgroundWorker().ensureInitialized();
  }
}

