import 'package:cingula_app/data/migration/cover.dart';
import 'package:cingula_app/data/migration/ids.dart';
import 'package:flutter_test/flutter_test.dart';

// Vectores verificados tambien con Python `uuid.uuid5` como tercer testigo independiente.
// Los mismos valores literales estan en backend/api/_lib/vectors.test.js.
void main() {
  test('uuid v5 vectors', () {
    expect(obraUuidForPath('11111111-2222-4333-8444-555555555555'),
        'b2d73103-b352-5e06-a226-a632610b0402');
    expect(portalUuidForTrigger('99999999-8888-4777-8666-555555555555'),
        'ea2a8c25-293f-5628-aa9a-c5774364a50f');
    expect(obraUuidForPath('ea2a8c25-293f-5628-aa9a-c5774364a50f'),
        'e311c70f-0969-5112-9ca9-4d4ea909dbaa');
  });

  test('cover vector', () {
    final c = computeCover([
      (lat: -42.1234567, lon: -71.654321),
      (lat: -42.12, lon: -71.66),
      (lat: -42.13, lon: -71.65),
    ]);
    expect(c.centerLat, -42.124486);
    expect(c.centerLon, -71.654774);
    expect(c.minLat, -42.13);
    expect(c.maxLat, -42.12);
    expect(c.minLon, -71.66);
    expect(c.maxLon, -71.65);
    expect(computeCover([]).centerLat, isNull);
  });
}
