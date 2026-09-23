import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cingula_app/data/datasources/local/db_init_lock.dart';

void main() {
  test('D-34: dos secciones criticas sobre el mismo path se serializan, no se pisan', () async {
    final dir = Directory.systemTemp.createTempSync('db_init_lock');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = '${dir.path}/cingula.db';

    final events = <String>[];

    // Simula el isolate principal y el de WorkManager llamando a init() casi
    // al mismo tiempo: los dos entran a withDbInitLock sobre el mismo path.
    final first = withDbInitLock(dbPath, () async {
      events.add('a-start');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      events.add('a-end');
    });
    // Arranca DESPUES de 'first' pero mientras 'first' sigue corriendo, para
    // que el lock tenga que hacerlo esperar de verdad.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = withDbInitLock(dbPath, () async {
      events.add('b-start');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      events.add('b-end');
    });

    await Future.wait([first, second]);

    // Si el lock funciona, 'a' termina ANTES de que 'b' arranque: nunca
    // quedan intercaladas (a-start, b-start, a-end, b-end seria la carrera).
    expect(events, ['a-start', 'a-end', 'b-start', 'b-end']);
  });

  test('el lock no deja el archivo .initlock trabado para la proxima corrida', () async {
    final dir = Directory.systemTemp.createTempSync('db_init_lock2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = '${dir.path}/cingula.db';

    await withDbInitLock(dbPath, () async => 1);
    // Si el unlock/close de la primera corrida no liberó bien, esta segunda
    // llamada se quedaria colgada esperando el lock para siempre.
    final result = await withDbInitLock(dbPath, () async => 2).timeout(
      const Duration(seconds: 5),
    );
    expect(result, 2);
  });
}
