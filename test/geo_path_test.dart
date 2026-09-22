import 'package:flutter_test/flutter_test.dart';
import 'package:cingula_app/domain/entities/geo_path.dart';

void main() {
  test('GeoPath es metadata sobre uuid (obraUuid/name/audioUuid/kind)', () {
    final path = GeoPath(uuid: 'p1', obraUuid: 'o1', name: 'seg', audioUuid: 'a1');
    expect(path.uuid, equals('p1'));
    expect(path.obraUuid, equals('o1'));
    expect(path.name, equals('seg'));
    expect(path.audioUuid, equals('a1'));
    expect(path.kind, equals('route'));
  });
}
