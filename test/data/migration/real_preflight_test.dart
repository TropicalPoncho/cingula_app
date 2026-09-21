import 'dart:io';

import 'package:cingula_app/data/migration/preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final real = Platform.environment['CINGULA_REAL_DB'];
  final out = Platform.environment['CINGULA_PREFLIGHT_OUT'];
  test('pre-flight sobre una copia de la base real', () async {
    // MODEL-08: esto NUNCA corre contra el celular. Recibe la ruta de una copia
    // ya extraida a la PC y, aun asi, trabaja sobre una segunda copia temporal.
    final tmp = Directory.systemTemp.createTempSync('cgpf');
    final work = File(p.join(tmp.path, 'copy.db'));
    File(real!).copySync(work.path);
    sqfliteFfiInit();
    // Sin version/onUpgrade: no migra nada.
    final db = await databaseFactoryFfi.openDatabase(work.path);
    final report = await preflight(db);
    await db.close();
    tmp.deleteSync(recursive: true);
    final text = formatPreflight(report);
    if (out != null) File(out).writeAsStringSync(text);
    // ignore: avoid_print
    print(text);
  }, skip: real == null ? 'requiere CINGULA_REAL_DB (ruta a una COPIA de la base)' : false);
}
