# Phase 1: Blindaje de Datos y Separación Debug/Usuario - Research

**Researched:** 2026-08-08
**Domain:** Local SQLite (sqflite) failure recovery, SharedPreferences runtime toggle, hidden-gesture UI activation, Flutter Material 3 conditional UI — no backend/network involved.
**Confidence:** HIGH

## Summary

This phase touches three small, well-scoped pieces of existing Flutter code, all of which already have an established in-codebase pattern to reuse — there is no new library to introduce and no architecture to invent. (1) `AppDatabase.init()`'s catch block currently does `deleteDatabase()` + recreate with zero backup on any open failure; it must instead rename the corrupt file with a timestamp and never delete data, then start the app normally with a non-blocking notice. (2) Two destructive debug actions (`recreateForTesting()`, `importDatabase()`) are being deleted outright from the UI per user decision — not confirmation-gated — so no new confirmation dialog code is needed; the existing `showDialog<bool>` + `AlertDialog` pattern (already used 5 times in `data_browser_page.dart`) remains the reference pattern for any *future* destructive action. (3) A runtime debug/user-mode toggle, activated by 5 taps on the AppBar title within 3 seconds (already locked by 01-UI-SPEC.md), persists via `SharedPreferences` following the exact static-class load/save pattern already established in `lib/core/config/location_config.dart`.

The only genuinely new implementation work is: the rename-not-delete recovery logic in `AppDatabase.init()`, a small `AppModeConfig`-style static class (SharedPreferences-backed, mirroring `LocationConfig`), a `GestureDetector`-wrapped AppBar title with tap-counting + timer reset, and conditional rendering in `HomePage` driven by that toggle's value. All four fit comfortably within already-installed dependencies (`sqflite`, `path_provider`, `shared_preferences`, `flutter/material.dart`) — nothing new needs to go in `pubspec.yaml` for production code.

**Primary recommendation:** Modify `AppDatabase.init()`'s catch block to rename (`File.rename`, not copy+delete) the existing file to `cingula.db.corrupto-<yyyyMMdd-HHmmss>` in the same app-documents directory, then call `openDatabase` fresh at the original path; expose the resulting recovery event (timestamp + backup path, or null) as a static/instance field the UI reads once after first frame to show a non-blocking `MaterialBanner`. Delete `recreateForTesting()`/`importDatabase()` call sites from `data_browser_page.dart` (and the dead methods from `AppDatabase` if D-13's discretion favors full removal — no other callers exist per repo grep). Add an `AppModeConfig` static class parallel to `LocationConfig` for the toggle, wire a 5-tap gesture on the `AppBar` title in `HomePage`, and split `HomePage.build()` into a user-mode branch (SwitchListTile + AudioDetails/status card + FAB only) and a debug-mode branch (adds `DiagnosticsPanel` and `_RecordingBanner`).

## User Constraints

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Recuperación ante fallo de apertura de DB (DATA-01)**
- **D-01:** Si `AppDatabase.init()` falla al abrir la base, el archivo corrupto se renombra (no se copia) con timestamp — ej. `cingula.db.corrupto-<timestamp>` — dejándolo intacto y accesible en el mismo directorio, antes de crear una base nueva vacía en la ruta original.
- **D-02:** Después de renombrar y crear la base nueva, la app arranca normalmente (no bloquea al usuario) y muestra un aviso (banner/diálogo) indicando que hubo un problema y dónde quedó el archivo renombrado. Prioridad: que la app siga siendo usable en el campo si esto pasa a mitad de una grabación.

**Acciones destructivas de debug (DATA-02)**
- **D-03:** La acción "recrear DB" (`recreateForTesting()`) se elimina por completo de la UI de debug (`data_browser_page.dart`). No se deja disponible ni siquiera para tests automatizados — no se automatizan funciones destructivas contra datos reales bajo ninguna circunstancia.
- **D-04:** La acción "importar DB" (`importDatabase()`, reemplaza toda la base con un archivo externo) también se elimina por completo de la UI de debug, mismo criterio que recrear.
- **D-05:** No se agrega confirmación escrita (tipo "escribir BORRAR") a ninguna acción — al eliminarse ambas acciones destructivas, esa pregunta queda sin objeto por ahora.
- **D-06:** El patrón de confirmación ya existente en el código (`showDialog<bool>` + `AlertDialog` con Cancelar/Confirmar, usado ya 5 veces en `data_browser_page.dart`) es el patrón a reutilizar si en el futuro se necesita confirmar alguna otra acción — no inventar un componente nuevo.

**Toggle debug/usuario (UI-01)**
- **D-07:** El toggle se activa por gesto oculto (ej. tocar varias veces el título del AppBar) — no un ícono/switch visible, no ocupa espacio en la UI de usuario final.
- **D-08:** El estado por defecto (incluyendo la primera vez que se instala este cambio) es modo debug — no cambia el flujo de trabajo actual del usuario. El usuario decide activamente cuándo pasar a modo usuario para probarlo.
- **D-09:** El estado del toggle persiste entre reinicios de la app (reutilizar el patrón de `SharedPreferences` ya usado en `LocationConfig` para esto).

**Alcance del modo usuario**
- **D-10:** En modo usuario se ocultan: `DiagnosticsPanel` completo (incluye el acceso a `DataBrowserPage`) y el banner de grabación de micrófono (`_RecordingBanner`).
- **D-11:** Quedan visibles en modo usuario: el switch de monitoreo de ubicación en background, la card de audio activo/reproduciéndose, y el botón flotante Iniciar/Detener.
- **D-12:** El modo usuario no es solo "ocultar widgets de debug" — necesita una estética final propia (ver 01-UI-SPEC.md, ya generado).
- **D-13:** UI-SPEC.md ya fue generado vía `/gsd:ui-phase 1` antes de este research/planning.

### Claude's Discretion
- Mecanismo exacto del gesto oculto — **ya resuelto por 01-UI-SPEC.md**: 5 taps sobre el título del AppBar en 3 segundos (no queda a discreción, el UI-SPEC ya lo fijó).
- Texto exacto del aviso de recuperación de DB (D-02) y formato del timestamp — **ya resuelto por 01-UI-SPEC.md** copywriting contract (ver abajo), no queda a discreción tampoco.
- Si `recreateForTesting()`/`importDatabase()` como métodos en `AppDatabase` quedan como código muerto sin caller o se eliminan del todo — priorizar eliminarlos si no hay ningún otro caller real (ver Feedback: nunca dejar funciones destructivas alcanzables "por las dudas"). **Confirmed via grep (this research): no other callers exist in `lib/` besides `data_browser_page.dart:128` and `:259`** — safe to delete the methods entirely, not just the call sites.

### Deferred Ideas (OUT OF SCOPE)
- Diseño visual completo del modo usuario más allá de esta pantalla — ya resuelto vía UI-SPEC para esta fase; extender a otras pantallas es trabajo futuro.
- Reintroducir funciones destructivas de administración de DB (con la fricción que corresponda) — explícitamente pospuesto hasta que sync/backup esté sólido (Fases 2-3).
</user_constraints>

## Project Constraints (from CLAUDE.md)

- **Integridad de datos es la restricción más alta de este milestone** — ningún cambio de esta fase puede arriesgar datos existentes en el celular. Directly governs the DB-recovery implementation: rename-only, never delete-then-recreate without a preserved copy.
- **Usuario único (v0)** — no se diseña para resolución de conflictos ni multi-dispositivo. Not directly relevant to Phase 1 (no sync work here), but confirms no extra complexity should be added for hypothetical multi-user scenarios.
- **Plataformas: Android e iOS (Flutter)** — any background/geofencing mechanism must work on both. Phase 1 has no geofencing work, but the DB-recovery file I/O (rename) must work correctly on Android, iOS, *and* macOS (this repo has a `macos/` directory and is run on Windows dev machine via `flutter run -d macos` or similar — `path_provider`'s `getApplicationDocumentsDirectory()` is supported on all three, confirmed by its own platform table).
- **Proceso de ejecución: auditoría `ponytail` obligatoria en cada fase de ejecución** — this phase's execution plan must include an explicit ponytail audit step in its checklist (already noted in ROADMAP.md per STATE.md).
- **GSD Workflow Enforcement** — file changes for this phase must happen via `/gsd:execute-phase`, not ad-hoc edits.
- **No destructive automation (user memory)** — never keep DB-wipe/import-overwrite reachable in UI or tests; delete instead of harden. This directly confirms D-03/D-04/D-13's discretion resolution: delete the dead methods, don't leave them "just in case."

## Phase Requirements

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DATA-01 | La app nunca borra/recrea la base de datos local sin respaldo previo, ni siquiera ante fallo de apertura | See "AppDatabase Recovery Pattern" below — rename-not-delete implementation, `File.rename` semantics, non-blocking banner surfacing via a static recovery-event field. |
| DATA-02 | Las acciones destructivas de la UI de debug (recrear DB, importar DB) piden confirmación explícita antes de ejecutarse | Resolved as deletion per D-03/D-04, not confirmation — see "Don't Hand-Roll" and code-removal guidance below. Existing `showDialog<bool>`/`AlertDialog` pattern documented for any future destructive action per D-06. |
| UI-01 | Un toggle en runtime (no flavors de Flutter) alterna entre el dashboard de usuario final y el panel de debug | See "AppModeConfig Toggle Pattern" and "Hidden-Gesture Activation Pattern" below — SharedPreferences persistence mirroring `LocationConfig`, 5-tap AppBar gesture, conditional `HomePage` rendering. |
</phase_requirements>

## Standard Stack

### Core (all already installed — no `pubspec.yaml` changes needed for production code)

| Library | Version (resolved, `pubspec.lock`) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `sqflite` | 2.4.2 | Local DB, already governs `AppDatabase` | Already the project's DB layer; this phase only changes the `init()` failure-handling branch, not the DB engine. |
| `path` | 1.9.1 (installed range `^1.9.0`) | Path joining for the renamed backup filename | Already used throughout `app_database.dart` (`p.join`). |
| `path_provider` | 2.1.5 | Resolves `getApplicationDocumentsDirectory()` for both the DB file and its renamed backup | Already used; supports Android/iOS/macOS/Windows/Linux — confirmed multi-platform, matches this project's `macos/` target. |
| `shared_preferences` | 2.5.3 | Persist the debug/user toggle state | Already used by `LocationConfig` — reuse the exact same static-class pattern, per D-09. |
| `flutter/material.dart` (SDK) | Flutter SDK-bundled | `MaterialBanner`, `GestureDetector`, `SwitchListTile`, `AlertDialog` | Confirmed by 01-UI-SPEC.md as the only component library needed this phase — no new UI package. |

### Supporting (dev-only, for testing — new dev dependency, optional)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `sqflite_common_ffi` | 2.4.2 (pub.dev, verified live 2026-08-08) | Runs real sqflite code (including a genuinely corrupted file triggering an `openDatabase` failure) inside `flutter test` on the host machine, without an emulator/simulator | Only needed if the plan wants an **automated** test that exercises the real `openDatabase` failure→rename→reopen path end-to-end. The existing test suite (`test/*.dart`) never touches real sqflite today (all repository tests use hand-written fakes) — this would be the first. If skipped, a manual "corrupt the file, cold-start the app, verify rename + banner" QA step is the fallback verification (see Validation Architecture below). |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Rename-in-place recovery (D-01) | SQLite `PRAGMA integrity_check` + `.recover`-style dump/reimport (suggested generically in `.planning/research/PITFALLS.md` Pitfall 1) | The user's locked decision (D-01) is simpler and already sufficient for the stated goal ("never lose data without a recoverable copy") — a full corruption-repair attempt is meaningfully more code (parsing `.recover` output, handling partial recovery, unclear payoff for a single-editor app where reading a renamed file for potential offline forensic recovery is enough). Don't build the repair attempt; rename + non-blocking notice is the locked spec. |
| Static `AppModeConfig` class mirroring `LocationConfig` | `ChangeNotifier`/`Provider`-based mode state | `LocationConfig` (the explicit pattern to reuse per D-09) is a static class with static load/save, not a `ChangeNotifier`. `HomePage` is a `StatelessWidget` reading `context.watch<PlaybackNotifier>()` for reactive state; the toggle needs a rebuild trigger too. Recommend a **thin** `ChangeNotifier` wrapper (or converting `HomePage` to `StatefulWidget` with local `setState`) *around* the static `AppModeConfig` persistence class — keep persistence static (matches D-09's instruction to reuse the pattern) but don't try to force reactivity into a static field; see Architecture Patterns below for the concrete shape. |
| 5-tap gesture via manual `GestureDetector` + `Timer` | A tap-counting package (e.g. a "secret menu" library) | None needed — this is roughly 15 lines of stdlib Dart (`Timer`, counter, `DateTime` window check) wrapped around the existing `Text('Cingula')` AppBar title. No package exists on pub.dev that's worth the dependency for this. |

**Installation:** None required for production code. If the optional test-infra package is adopted:
```bash
flutter pub add --dev sqflite_common_ffi
```

**Version verification:** `sqflite` 2.4.2, `path_provider` 2.1.5, `shared_preferences` 2.5.3 confirmed directly from this repo's `pubspec.lock` (already resolved, not hypothetical). `sqflite_common_ffi` 2.4.2 confirmed live on pub.dev (fetched 2026-08-08, "released 58 days ago" at fetch time).

## Architecture Patterns

### Recommended Project Structure (no new files needed beyond one new config class)

```
lib/
├── core/
│   └── config/
│       ├── location_config.dart      # existing — pattern to mirror
│       └── app_mode_config.dart      # NEW — static SharedPreferences-backed toggle (mirrors LocationConfig)
├── data/datasources/local/
│   └── app_database.dart             # MODIFY — init() catch block: rename-not-delete
├── presentation/pages/
│   ├── data_browser_page.dart        # MODIFY — remove _recreateDb/_importDb call sites + buttons
│   └── home_page_impl.dart           # MODIFY — hidden-gesture AppBar title, conditional debug/user rendering, DB-recovery banner
```

### Pattern 1: Rename-not-delete DB recovery (DATA-01)

**What:** On `openDatabase` failure in `AppDatabase.init()`, rename the existing (possibly corrupt) file to a timestamped path in the same directory using `File.rename()`, then attempt `openDatabase` fresh at the original path. Never call `deleteDatabase()` in this path. Record the event so the UI can show it once, non-blocking, after normal startup.

**When to use:** Exactly the current `catch (e)` block in `AppDatabase.init()` (lines ~38-53 today).

**Example:**
```dart
// Source: existing project pattern (path/path_provider already used identically
// in exportDatabase()) + File.rename semantics (dart:io, stdlib — same filesystem,
// same app-sandbox directory on Android/iOS/macOS, so no cross-device rename risk).
Future<void> init() async {
  if (_database != null) return;

  final directory = await getApplicationDocumentsDirectory();
  final path = p.join(directory.path, _dbName);

  try {
    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  } catch (e) {
    stderr.writeln('Database init failed: $e. Renaming corrupt file and starting fresh...');
    final timestamp = _formatTimestamp(DateTime.now()); // e.g. 20260808-131003
    final backupPath = p.join(directory.path, '$_dbName.corrupto-$timestamp');
    try {
      final corruptFile = File(path);
      if (await corruptFile.exists()) {
        await corruptFile.rename(backupPath);
      }
    } catch (renameError) {
      // If rename itself fails (e.g. file locked), do NOT fall through to delete.
      // Surface the failure and rethrow — never silently destroy data.
      stderr.writeln('Failed to rename corrupt database: $renameError');
      rethrow;
    }

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    lastRecoveryEvent = DatabaseRecoveryEvent(backupPath: backupPath, occurredAt: DateTime.now());
  }
}
```

Key details verified from `dart:io` semantics: `File.rename()` is an atomic move within the same filesystem/volume — the app-documents directory is a single directory on all three target platforms, so no partial-write or cross-volume risk exists here (unlike a copy+delete, which briefly has two copies and a window where a crash could still lose the original — rename avoids that window entirely, which is precisely why D-01 specifies rename over copy). No new dependency needed; `dart:io`'s `File` class already provides this.

**Non-blocking surfacing (D-02):** Store the recovery event as a field the UI can read once. Since `AppDatabase` is already a `getIt` singleton read from `HomePage`'s widget tree indirectly, the simplest option (matches "app must stay usable mid-recording") is a static nullable field on `AppDatabase` (or a tiny value class), checked once via `addPostFrameCallback` in `HomePage`'s `initState`/`build`, then shown via `ScaffoldMessenger.of(context).showMaterialBanner(...)` (the widget UI-SPEC.md explicitly calls out) with the exact copy already locked in UI-SPEC.md's Copywriting Contract. Never make this a blocking `showDialog` — that would violate D-02's "no bloquea al usuario" requirement.

### Pattern 2: Static SharedPreferences-backed toggle (UI-01, mirrors `LocationConfig`)

**What:** A static class exposing a boolean (`isDebugMode`), with `loadFromPrefs()` and a setter that persists immediately — same shape as `LocationConfig.saveActivationRadius()`.

**Example:**
```dart
// Source: lib/core/config/location_config.dart (existing pattern in this repo, reused verbatim)
import 'package:shared_preferences/shared_preferences.dart';

class AppModeConfig {
  static const _kIsDebugMode = 'app_isDebugMode';

  /// Debug mode is the default per D-08 — existing workflow unaffected until
  /// the user explicitly activates user mode via the hidden gesture.
  static bool isDebugMode = true;

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isDebugMode = prefs.getBool(_kIsDebugMode) ?? true;
    } catch (_) {
      // Silenciar errores de preferencias; usar el valor por defecto (debug).
    }
  }

  static Future<void> setDebugMode(bool value) async {
    isDebugMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsDebugMode, value);
  }
}
```

**Reactivity note:** `LocationConfig` is read by widgets that already rebuild for other reasons (e.g. `DiagnosticsPanel`'s own `setState` calls after saving). `HomePage` today is a `StatelessWidget`. Since toggling needs an immediate visible rebuild of `HomePage` itself (switching between debug/user layout), the plan should either (a) convert `HomePage` to a `StatefulWidget` that calls `setState` after `AppModeConfig.setDebugMode()` resolves, or (b) keep it a `StatelessWidget` and drive the toggle through the already-present `PlaybackNotifier` (`ChangeNotifier`) or a new minimal notifier. Given only one widget needs to react, (a) — plain `StatefulWidget` + local `setState` — is the smaller diff and stays fully aligned with the "static persistence class, local reactive wrapper" split already implicit in how `LocationConfig` values get displayed in `DiagnosticsPanel` (a `StatefulWidget`).

### Pattern 3: Hidden N-tap gesture on AppBar title (UI-01, gesture mechanics locked by UI-SPEC)

**What:** 5 taps within 3 seconds on the AppBar title text triggers the toggle + a 2-second `SnackBar` confirmation ("Modo debug activado" / "Modo usuario activado") — exact copy and timing already locked in `01-UI-SPEC.md`.

**Example:**
```dart
// Standard Flutter "secret menu" tap-counter pattern — stdlib only (Timer + counter).
class _HiddenModeGesture extends StatefulWidget {
  const _HiddenModeGesture({required this.onActivated});
  final VoidCallback onActivated;

  @override
  State<_HiddenModeGesture> createState() => _HiddenModeGestureState();
}

class _HiddenModeGestureState extends State<_HiddenModeGesture> {
  int _tapCount = 0;
  Timer? _resetTimer;

  void _handleTap() {
    _tapCount++;
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () => _tapCount = 0);
    if (_tapCount >= 5) {
      _tapCount = 0;
      _resetTimer?.cancel();
      widget.onActivated();
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: const Text('Cingula'),
    );
  }
}
```

### Pattern 4: Conditional debug/user rendering in `HomePage`

**What:** Branch the widget tree on `AppModeConfig.isDebugMode` — user mode keeps `SwitchListTile` + audio card + FAB (per D-11); debug mode adds `DiagnosticsPanel` and `_RecordingBanner` (per D-10). AppBar title, spacing, and color roles for user mode come directly from `01-UI-SPEC.md` — this research does not re-derive visual design, it defers to that already-approved contract.

**Example (structural sketch, not final code):**
```dart
Column(
  children: [
    SwitchListTile(/* unchanged, D-11 */),
    const SizedBox(height: 24),
    if (showAudioCard) /* unchanged, D-11 */,
    if (isDebugMode) ...[
      const SizedBox(height: 16),
      const DiagnosticsPanel(),
    ],
  ],
),
if (isDebugMode) _RecordingBanner(recorder: recorder), // D-10
```

### Anti-Patterns to Avoid

- **Copy-then-delete instead of rename for DB recovery:** Leaves a window where both files could be lost on a crash between copy and delete; also does unnecessary I/O (a full file copy) when a rename is atomic and instant. D-01 explicitly specifies rename — don't substitute copy+delete "to be safe," it's actually less safe.
- **Blocking dialog for the DB-recovery notice:** D-02 explicitly requires the app to stay usable (e.g., mid-recording) — a blocking `showDialog` would violate this even though it "looks" like a stronger warning. Use `MaterialBanner`/`SnackBar` per UI-SPEC, dismissible, shown after normal startup completes.
- **Keeping `recreateForTesting()`/`importDatabase()` "for future use" or gated behind a debug flag:** D-03/D-04/D-13 and the project's own stored user feedback (`feedback_no_destructive_automation.md`) are explicit — delete the methods entirely, don't leave them reachable "just in case," don't wire them into any test.
- **Adding a typed confirmation ("escribir BORRAR") anywhere in this phase:** D-05 explicitly defers this; there is no destructive action left in scope to gate.
- **Introducing a new confirmation-dialog widget/component:** D-06 explicitly says reuse `showDialog<bool>` + `AlertDialog` if any future confirmation is needed — don't build a new one even if this phase doesn't end up needing it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detecting a genuinely corrupt/unopenable SQLite file for a manual test | A synthetic "corrupt bytes" fixture generator | Truncate/overwrite a copy of a real `.db` file with garbage bytes, or use `sqflite_common_ffi` in a `flutter test` to open a deliberately truncated file — both are minimal, no framework needed | Standard, well-documented way to trigger `openDatabase` failure deterministically (see Validation Architecture) |
| Toggle state persistence | A new `SharedPreferences` wrapper/service class, a `Riverpod`/`Bloc` state container | Static class mirroring `LocationConfig` (Pattern 2 above) | `LocationConfig` is the explicit reuse target per D-09; introducing a different state-management primitive for one boolean is unjustified complexity for a single-editor app |
| Confirming a destructive action (if one is ever reintroduced later) | A custom confirmation widget/component | `showDialog<bool>` + `AlertDialog` (Cancelar/Confirmar) — already used 5× in `data_browser_page.dart` | D-06 locks this explicitly |

**Key insight:** Every piece of this phase has a same-file or same-repo precedent already established (`LocationConfig` for persistence, `showDialog`/`AlertDialog` for confirmation, `path`/`path_provider` for file paths). The only genuinely new code is the rename-based recovery branch and the tap-counter gesture, both of which are stdlib-only (`dart:io`, `dart:async`) — no new production dependency is justified.

## Common Pitfalls

### Pitfall 1: Silent DB delete-and-recreate on open failure — the exact bug this phase fixes
**What goes wrong:** Today's `catch` block calls `deleteDatabase(path)` before recreating — any transient open failure (disk full, OS kill mid-open, bad migration, file lock) destroys all local data permanently.
**Why it happens:** Common early-development shortcut that never gets revisited once real user data exists.
**How to avoid:** Rename-not-delete (Pattern 1 above) — this is DATA-01's entire purpose.
**Warning signs:** Any `deleteDatabase(` call in a failure/catch path with no preceding backup. Verified during this research: after the fix, the only remaining `deleteDatabase(` call site would be inside `recreateForTesting()` — which this phase deletes entirely, so post-phase there should be **zero** `deleteDatabase(` calls left in non-test code. Grep for `deleteDatabase(` at review time as a completion check.

### Pitfall 2: Destructive debug UI reachable without confirmation — resolved by deletion, not gating, in this phase
**What goes wrong:** `recreateForTesting()`/`importDatabase()` wired directly to buttons with a confirmation dialog that's still one accidental double-tap away from wiping data.
**Why it happens:** Debug tooling built for solo-developer convenience, never removed once real user data exists.
**How to avoid:** D-03/D-04 already resolved this — delete both UI entry points and (recommended, confirmed safe by this research's grep) both `AppDatabase` methods. Do not implement a confirmation dialog for them — that would contradict the locked decision.
**Warning signs:** Any `ElevatedButton`/`OutlinedButton` in `data_browser_page.dart` still calling `_recreateDb`/`_importDb`, or FilePicker import wiring left dangling after the button is removed (remove the now-unused `file_picker` import/usage in `data_browser_page.dart` if `_importDb` is the only caller — verify before removing the `file_picker` pubspec dependency itself, since it may be used elsewhere; a repo-wide grep for `file_picker` shows only `data_browser_page.dart` imports it as of this research, so the dependency itself can likely be removed from `pubspec.yaml` too — confirm at implementation time).

### Pitfall 3: Toggle default regression — accidentally defaulting to user mode
**What goes wrong:** If `AppModeConfig.isDebugMode`'s static default (before `loadFromPrefs()` resolves) or the `prefs.getBool(...) ?? default` fallback is set to `false`, a fresh install or a `SharedPreferences` read failure would silently drop the developer into user mode, hiding `DiagnosticsPanel`/`DataBrowserPage` — exactly the primary workflow the user still depends on (D-08 is explicit: default must be debug, always).
**Why it happens:** Easy to typo `?? false` instead of `?? true`, especially when copying the `LocationConfig` pattern (which defaults to specific numeric values, not booleans) as a template.
**How to avoid:** Both the static field's initializer (`static bool isDebugMode = true;`) and the `loadFromPrefs()` fallback (`?? true`) must independently default to debug mode — verify both, not just one, since either alone being wrong causes the regression on the code path where the other doesn't save it.
**Warning signs:** A test or manual check: fresh install (no `SharedPreferences` key set) → app opens in debug mode, `DiagnosticsPanel` visible.

### Pitfall 4: `MaterialBanner` shown before `Scaffold`/`ScaffoldMessenger` exists in the widget tree
**What goes wrong:** If the DB-recovery banner is triggered too early (e.g. in `main()` before `runApp` builds a `Scaffold`), `ScaffoldMessenger.of(context)` throws or silently no-ops.
**Why it happens:** The recovery event happens during `AppDatabase.init()` in `AppInitializer`, which runs before `runApp()` — there's no `BuildContext`/`Scaffold` at that point yet.
**How to avoid:** Store the recovery event as plain data (backup path + timestamp, no widget/context reference) on `AppDatabase` init, and only call `ScaffoldMessenger.of(context).showMaterialBanner(...)` from inside `HomePage` (which does have a `Scaffold` and a valid `BuildContext`) via a post-frame callback, reading the stored event once.
**Warning signs:** Any attempt to show a `MaterialBanner`/`SnackBar` directly from `AppDatabase` or `AppInitializer` — those classes have no `BuildContext` and shouldn't import `flutter/material.dart` at all (checked: `app_database.dart` currently has zero Flutter UI imports; keep it that way, pure `dart:io`/`sqflite`).

## Code Examples

See Architecture Patterns section above — all four code examples are drawn directly from this repository's existing conventions (`LocationConfig`, `data_browser_page.dart`'s dialog pattern, `AppDatabase`'s existing `p.join`/`getApplicationDocumentsDirectory()` usage) plus stdlib `dart:io`/`dart:async` primitives. No external framework code needed.

## State of the Art

| Old Approach (current code) | Current Approach (this phase) | When Changed | Impact |
|--------------------------|------------------|---------------|--------|
| `deleteDatabase()` on any open failure, no backup | `File.rename()` to timestamped backup, then fresh `openDatabase()` | This phase (DATA-01) | Zero silent data loss on DB open failure; recoverable file left on disk |
| `recreateForTesting()`/`importDatabase()` reachable from debug UI with a weak confirmation dialog | Both entry points (and, recommended, the methods themselves) deleted | This phase (DATA-02, per D-03/D-04) | Eliminates the accidental-data-wipe risk entirely rather than reducing it |
| Single `HomePage` UI for everyone (debug tooling always visible) | Runtime-toggled debug/user mode, default debug, hidden-gesture activation | This phase (UI-01) | Separates end-user experience from developer tooling without a Flutter flavor/build-variant split |

**Deprecated/outdated:** N/A — no external library version changes involved in this phase; all changes are internal application logic.

## Open Questions

1. **Should `AppDatabase`'s recovery-event field be a static field on the class, or routed through `getIt`/a dedicated small value-holder?**
   - What we know: `AppDatabase` is already a `getIt` singleton (`getIt<AppDatabase>()` used throughout `DataBrowserPage`/`DiagnosticsPanel`), so an instance field (e.g. `AppDatabase.lastRecoveryEvent` as an instance getter, not static) is retrievable anywhere `getIt<AppDatabase>()` is already called, including from `HomePage`.
   - What's unclear: Whether the planner prefers a plain nullable field on `AppDatabase` vs. a tiny separate `DatabaseRecoveryEvent`/`DbRecoveryNotifier` class for cleaner separation of concerns (DB logic vs. UI-facing state).
   - Recommendation: A plain nullable instance field (`DatabaseRecoveryEvent? lastRecoveryEvent`) on `AppDatabase`, checked once in `HomePage.initState`'s post-frame callback, is the smallest correct option — avoid introducing a new notifier/class for a single one-shot event unless the planner has a reason to want it reusable elsewhere.

2. **Does removing `_importDb`/`file_picker` usage from `data_browser_page.dart` also justify removing the `file_picker` package from `pubspec.yaml`?**
   - What we know: This research's grep found `file_picker` imported only in `data_browser_page.dart`.
   - What's unclear: Whether some other in-progress/untracked work (git status shows several modified/new files, e.g. `lib/data/sync/sync_api.dart`, not read in this research) might need it later.
   - Recommendation: Leave the `pubspec.yaml` dependency line in place for this phase (low cost to leave an unused dependency vs. risk of removing something another in-flight change needs); flag it as a follow-up cleanup once Phase 2/3 sync work solidifies. This is a discretion call for the planner, not a blocker.

## Environment Availability

Skipped — this phase has no external service/tool dependencies. All required packages (`sqflite`, `path_provider`, `shared_preferences`) are already installed and resolved in `pubspec.lock`; the optional `sqflite_common_ffi` test dependency runs entirely on the host machine with no external service.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (bundled with Flutter SDK, already in `dev_dependencies`) |
| Config file | none — no `dart_test.yaml` in repo; tests run via default `flutter test` discovery of `test/**/*_test.dart` |
| Quick run command | `flutter test test/core/app_database_test.dart` (new file, see Wave 0 Gaps) — or targeted: `flutter test -n "recovery"` once tests are named |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DATA-01 | On `openDatabase` failure, corrupt file is renamed (not deleted) with a timestamp; new DB opens successfully; recovery event is recorded | unit (requires `sqflite_common_ffi`) | `flutter test test/core/app_database_test.dart` | ❌ Wave 0 — new file, new dev dependency |
| DATA-01 | App starts normally (no blocking UI) after a recovery event; banner text matches UI-SPEC copy | manual QA (widget-level automation optional, low value for a one-shot startup banner) | Manual: corrupt `cingula.db` on a device/emulator, cold-start app, confirm banner text + dismiss works, confirm renamed file present in app documents dir | N/A — manual-only, justified: requires real filesystem state manipulation on-device, low ROI to automate for a one-time startup event |
| DATA-02 | `recreateForTesting()`/`importDatabase()` buttons no longer exist in `data_browser_page.dart`; methods removed from `AppDatabase` if discretion favors full removal | unit / static check | `flutter test` (existing suite must still pass with no references) + `grep -rn "recreateForTesting\|importDatabase" lib/` returns no matches outside intentionally-kept code (should be zero matches if fully removed) | ✅ existing test suite; grep is a manual completion check |
| UI-01 | Toggle persists across app restarts via `SharedPreferences`; defaults to debug mode on fresh install | unit | `flutter test test/core/config/app_mode_config_test.dart` (new file, mirrors how `LocationConfig` *could* be tested — note: no existing test file for `LocationConfig` itself, so this would be the first for this pattern; use `SharedPreferences.setMockInitialValues({})` per the official `shared_preferences` testing guidance) | ❌ Wave 0 — new file |
| UI-01 | 5 taps within 3 seconds on AppBar title toggles mode; taps spaced beyond 3s do not accumulate | widget test | `flutter test test/presentation/pages/home_page_gesture_test.dart` | ❌ Wave 0 — new file |
| UI-01 | User mode hides `DiagnosticsPanel` and `_RecordingBanner`; debug mode shows both; user mode keeps `SwitchListTile`/audio card/FAB | widget test | `flutter test test/presentation/pages/home_page_mode_test.dart` | ❌ Wave 0 — new file |

### Sampling Rate
- **Per task commit:** `flutter test` (fast — this repo's suite is currently small; a full run is cheap, no need to scope to individual files during iteration)
- **Per wave merge:** `flutter test` (same command — no separate "full suite" distinct from quick run at this repo's current test-suite size)
- **Phase gate:** `flutter test` green + the manual QA step for the DB-recovery banner (Pitfall/behavior that can't be cheaply automated) before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `flutter pub add --dev sqflite_common_ffi` — needed only if the plan chooses to automate the DB open-failure/rename test; otherwise this becomes a manual QA step and can be skipped (YAGNI-consistent with ponytail: don't add the dependency if the plan is comfortable with one documented manual verification step for a startup-only, hard-to-trigger-safely-in-CI failure path).
- [ ] `test/core/app_database_test.dart` — covers DATA-01 rename-recovery behavior (only if `sqflite_common_ffi` is adopted)
- [ ] `test/core/config/app_mode_config_test.dart` — covers UI-01 persistence/default behavior, using `SharedPreferences.setMockInitialValues({})` (official `shared_preferences` package testing pattern, no new dependency needed — `shared_preferences`'s own test-mock support ships in the package)
- [ ] `test/presentation/pages/home_page_gesture_test.dart` — covers UI-01 tap-count/timeout gesture behavior
- [ ] `test/presentation/pages/home_page_mode_test.dart` — covers UI-01 conditional widget visibility (debug vs. user mode)

*(No shared fixtures/conftest-equivalent needed — Flutter/Dart tests don't use a conftest pattern; each new test file is self-contained per the existing repo convention, e.g. `test/core/background/background_poller_test.dart`'s inline fakes.)*

## Sources

### Primary (HIGH confidence)
- Direct repository read: `lib/data/datasources/local/app_database.dart`, `lib/core/config/location_config.dart`, `lib/presentation/pages/home_page_impl.dart`, `lib/presentation/pages/data_browser_page.dart`, `lib/presentation/pages/home/widgets/diagnostics_panel.dart`, `lib/main.dart`, `lib/presentation/pages/intro_page.dart`, `lib/core/di/service_locator.dart`, `pubspec.yaml`, `pubspec.lock`, `test/*.dart` — all fetched directly, HIGH confidence (ground truth, not inference)
- `.planning/phases/01-.../01-CONTEXT.md` and `.planning/phases/01-.../01-UI-SPEC.md` — locked project decisions, HIGH confidence (authoritative for this phase)
- `.planning/research/PITFALLS.md` (Pitfall 1, Pitfall 2) — prior project research, HIGH confidence, directly informed the rename-vs-delete and confirmation-vs-deletion framing
- pub.dev `sqflite_common_ffi` page (fetched 2026-08-08) — HIGH confidence, official package page, version 2.4.2 confirmed live

### Secondary (MEDIUM confidence)
- WebSearch "sqflite_common_ffi flutter test unit test database corruption 2026" — cross-referenced against pub.dev/GitHub official sqflite repo docs (`tekartik/sqflite/sqflite_common_ffi/doc/testing.md`), MEDIUM confidence for the specific testing-pattern claims (mocking sqflite for `flutter test` without an emulator), consistent with the official package description

### Tertiary (LOW confidence)
- None used as load-bearing claims — everything in this document is either read directly from the repo, from locked project decisions, or from an official package source.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every library is already installed and resolved in this exact repo's `pubspec.lock`; no external stack decision was needed.
- Architecture: HIGH — every pattern is a direct extension of an existing, already-reviewed pattern in this codebase (`LocationConfig`, `data_browser_page.dart` dialogs, `AppDatabase`'s existing path/provider usage), not a novel design.
- Pitfalls: HIGH — pitfalls are grounded in direct code reading of the current failure path plus this project's own prior `PITFALLS.md` research, not speculative.

**Research date:** 2026-08-08
**Valid until:** Effectively indefinite for the architectural guidance (internal-only code, no external API surface to go stale) — the one date-sensitive fact (`sqflite_common_ffi` version) should be re-checked if implementation happens more than ~90 days after this research.
