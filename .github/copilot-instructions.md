## Resumen breve

Repositorio: app Flutter estructurada con capa de `core/`, `domain/`, `data/`, `presentation/` (patrón similar a Clean Architecture). Objetivo de este archivo: dar al agente contexto práctico para ser productivo rápidamente.

## Puntos clave (leer antes de editar)

- `pubspec.yaml` — dependencias, assets y fonts; ejecutar `flutter pub get` tras cualquier cambio.
- `lib/main.dart` — punto de entrada y wiring global (providers, inicializadores).
- Capas:
  - `lib/domain/` — contratos (entidades, repositorios, use-cases).
  - `lib/data/` — implementaciones, adaptadores a plugins y mappers.
  - `lib/presentation/` — widgets, screens, viewmodels/controllers.

## Flujo de trabajo y comandos relevantes

- Obtener dependencias: `flutter pub get`.
- Limpiar build antes de cambios nativos: `flutter clean`.
- Ejecutar en Windows (PowerShell): `flutter run -d windows` o `flutter run -d <device-id>`.
- Build Android desde Windows: `android/gradlew.bat assembleDebug` dentro de `android/`.
- Tests: `flutter test`.

## Convenciones específicas observables

- Mantener la separación de capas: mover lógica desde `presentation/` a `domain/` al refactorizar.
- No editar archivos en `build/`, `generated/` ni `*/generated/` (se regeneran automáticamente).
- Recursos multimedia en `audio/` y otros assets deben estar registrados en `pubspec.yaml`.

## Integraciones y puntos sensibles

- Plugins nativos (ej.: `just_audio`, `geolocator_android`, `sqflite_android`) requieren recompilar la app tras cambios y, a veces, pruebas en dispositivo físico.
- Si modificas código nativo en `android/` o `ios/`, documenta en el PR los pasos para reproducir la build y cualquier SDK/credential requerido.
- Localizaciones: hay stamps de generación (`gen_localizations.stamp`) — respeta el flujo de i18n si se cambia l10n.

## Ejemplos concretos para agentes

- Añadir un nuevo caso de uso:
  1. Crear interfaz en `lib/domain/`.
  2. Añadir implementación en `lib/data/` y mapear entidades.
  3. Conectar a UI en `lib/presentation/` y agregar tests unitarios.

- Corregir un bug de audio: revisar `audio/` para assets, localizar uso de `just_audio` en `lib/` y probar en dispositivo real.

## Archivos para revisar primero

- `pubspec.yaml`, `lib/main.dart`, `lib/presentation/`, `lib/domain/`, `lib/data/`, `android/app/build.gradle.kts`.

## Suposiciones y preguntas abiertas

- Asumo Clean-like structure por las carpetas; si hay codegen (p. ej. `build_runner`) revisa `pubspec.yaml` para scripts.
- Si quieres, puedo fusionar contenido con un `.github/copilot-instructions.md` existente (indícame la ruta). ¿Deseas cambios o ampliaciones concretas?
