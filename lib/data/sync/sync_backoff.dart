import 'dart:math';

/// Base de la curva de backoff: primer reintento cae en [0, 2s].
const Duration kBackoffBase = Duration(seconds: 2);

/// Techo de la curva: nunca se espera más de 5 minutos entre intentos.
const Duration kBackoffCap = Duration(minutes: 5);

/// Full Jitter (AWS Architecture Blog): delay = random(0, min(cap, base * 2^attempt)).
/// Se elige Full Jitter y no "exponencial puro" porque un solo dispositivo reintentando
/// no necesita evitar thundering herd, pero sí evitar sincronizarse con ciclos de red
/// periódicos (p. ej. reconexiones de red móvil) que producirían fallos correlacionados.
Duration fullJitterBackoff(int attemptCount, {Random? random}) {
  final exponent = attemptCount.clamp(0, 20);
  final ceilingMs = min(kBackoffCap.inMilliseconds, kBackoffBase.inMilliseconds * (1 << exponent));
  return Duration(milliseconds: (random ?? Random()).nextInt(ceilingMs + 1));
}

/// Una fila de outbox es elegible si nunca falló (`next_attempt_at` null/ausente)
/// o si ya pasó el instante agendado. [nowSeconds] son epoch seconds, misma unidad
/// que `created_at` / `sync_state.last_sync_at`.
bool isOutboxRowEligible(Map<String, Object?> row, {required int nowSeconds}) {
  final next = row['next_attempt_at'] as int?;
  return next == null || next <= nowSeconds;
}
