import 'background/background_worker.dart';
import 'di/service_locator.dart';

/// Centraliza tareas de arranque: inyeccion de dependencias y trabajos en background.
class AppInitializer {
  Future<void> init() async {
    // Configuramos singletons y repositorios antes de usar la capa de dominio.
    await setupServiceLocator();
    // Registramos la tarea periï¿½dica que consulta la ubicaciï¿½n.
    await BackgroundWorker().ensureInitialized();
  }
}

