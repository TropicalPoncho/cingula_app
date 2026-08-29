import 'dart:async';

import '../../domain/usecases/run_sync_usecase.dart';
import 'sync_errors.dart';

enum SyncTriggerStatus { idle, running, ok, transientError, authError }

/// Dispara pushes del outbox de forma automática, coalescida y no reentrante.
///
/// NO hay timer periódico ni loop de polling: los disparos son puramente por evento
/// (escritura local, reconexión, botón manual). Esto es deliberado — todo este milestone
/// existe en parte para eliminar el polling continuo que drena batería.
class SyncTrigger {
  SyncTrigger({
    required RunSyncUseCase runSync,
    Duration debounce = const Duration(seconds: 2),
  })  : _runSync = runSync,
        _debounce = debounce;

  final RunSyncUseCase _runSync;
  final Duration _debounce;
  final _statusController = StreamController<SyncTriggerStatus>.broadcast();

  Timer? _timer;
  Future<void>? _inFlight;
  bool _rerunRequested = false;
  SyncTriggerStatus _lastStatus = SyncTriggerStatus.idle;

  SyncTriggerStatus get lastStatus => _lastStatus;
  Stream<SyncTriggerStatus> get statusStream => _statusController.stream;
  bool get isRunning => _inFlight != null;

  /// Agenda un push. Llamadas repetidas dentro de la ventana de debounce colapsan en una.
  /// Fire-and-forget: nunca lanza, para no romper la escritura local que lo disparó.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_run()));
  }

  /// Corre un push ya mismo y espera a que termine. Para tests y para el botón manual.
  Future<void> flush() {
    _timer?.cancel();
    return _run();
  }

  Future<void> _run() {
    final current = _inFlight;
    if (current != null) {
      // Ya hay uno corriendo: pedir una re-corrida en vez de solapar pushes sobre el mismo outbox.
      _rerunRequested = true;
      return current;
    }
    final future = _execute();
    _inFlight = future;
    return future;
  }

  Future<void> _execute() async {
    _emit(SyncTriggerStatus.running);
    try {
      await _runSync.pushOutboxOnce();
      _emit(SyncTriggerStatus.ok);
    } on SyncAuthException {
      _emit(SyncTriggerStatus.authError);
    } on SyncTransientException {
      _emit(SyncTriggerStatus.transientError);
    } catch (_) {
      _emit(SyncTriggerStatus.transientError);
    } finally {
      _inFlight = null;
    }
    if (_rerunRequested) {
      _rerunRequested = false;
      await _run();
    }
  }

  void _emit(SyncTriggerStatus status) {
    _lastStatus = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void dispose() {
    _timer?.cancel();
    _statusController.close();
  }
}
