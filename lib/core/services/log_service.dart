import 'dart:async';

/// Servicio simple en memoria para recolectar mensajes de log
/// y exponerlos a la UI.
class LogService {
  LogService({this.maxEntries = 500});

  final int maxEntries;
  final List<String> _entries = [];
  final StreamController<List<String>> _controller = StreamController.broadcast();

  /// Añade una línea de log y notifica a los listeners.
  void log(String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message';
    _entries.add(line);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _controller.add(List.unmodifiable(_entries));
  }

  /// Lista inmutable con las entradas actuales (últimas N).
  List<String> get recent => List.unmodifiable(_entries);

  /// Stream que emite la lista completa de entradas cada vez que cambia.
  Stream<List<String>> get stream => _controller.stream;

  /// Limpia los logs.
  void clear() {
    _entries.clear();
    _controller.add(List.unmodifiable(_entries));
  }

  void dispose() {
    _controller.close();
  }
}
