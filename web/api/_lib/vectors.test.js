import test from 'node:test';
import assert from 'node:assert/strict';
import { obraUuidForPath, portalUuidForTrigger } from './ids.js';
import { computeCover, r6 } from './cover.js';

// Vectores verificados tambien con Python `uuid.uuid5` como tercer testigo independiente.
// Los mismos valores literales estan en test/data/migration/vectors_test.dart.
test('uuid v5 vectors', () => {
  assert.equal(obraUuidForPath('11111111-2222-4333-8444-555555555555'), 'b2d73103-b352-5e06-a226-a632610b0402');
  assert.equal(portalUuidForTrigger('99999999-8888-4777-8666-555555555555'), 'ea2a8c25-293f-5628-aa9a-c5774364a50f');
  assert.equal(obraUuidForPath('ea2a8c25-293f-5628-aa9a-c5774364a50f'), 'e311c70f-0969-5112-9ca9-4d4ea909dbaa');
});

test('cover vector', () => {
  assert.deepEqual(
    computeCover([{ lat: -42.1234567, lon: -71.654321 }, { lat: -42.12, lon: -71.66 }, { lat: -42.13, lon: -71.65 }]),
    { centerLat: -42.124486, centerLon: -71.654774, minLat: -42.13, maxLat: -42.12, minLon: -71.66, maxLon: -71.65 },
  );
  assert.equal(r6(-42.1234565), -42.123457);
  assert.equal(computeCover([]).centerLat, null);
});
