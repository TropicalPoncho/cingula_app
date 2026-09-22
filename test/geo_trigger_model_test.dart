import 'package:flutter_test/flutter_test.dart';
import 'package:cingula_app/data/models/geo_trigger_model.dart';
import 'package:cingula_app/domain/value_objects/coordinate.dart';

void main() {
  test('GeoTriggerModel mapping and contains', () {
    final map = {
      'uuid': 'trigger-2',
      'path_uuid': 'path-1',
      'name': 'TriggerTest',
      'description': 'desc',
      'latitude': -34.786151,
      'longitude': -58.409156,
      'radius_meters': 10.0,
    };

    final trigger = GeoTriggerModel.fromMap(map);
    expect(trigger.uuid, equals('trigger-2'));
    expect(trigger.pathUuid, equals('path-1'));

    final close = Coordinate(latitude: -34.786151, longitude: -58.409156);
    final far = Coordinate(latitude: -34.800, longitude: -58.420);

    expect(trigger.contains(close), isTrue);
    expect(trigger.contains(far), isFalse);
  });
}
