import 'package:flutter_test/flutter_test.dart';
import 'package:cingula_app/data/models/region_model.dart';
import 'package:cingula_app/data/models/geo_trigger_model.dart';
import 'package:cingula_app/domain/value_objects/coordinate.dart';

void main() {
  test('RegionModel.fromMap and contains', () {
    final map = {
      'id': 1,
      'name': 'TestRegion',
      'center_lat': -34.60,
      'center_lon': -58.38,
      'radius_meters': 1000.0,
      'sample_coarse_seconds': 30,
      'sample_fine_seconds': 2,
      'coarse_distance_filter_meters': 500,
      'fine_distance_filter_meters': 5,
    };

    final region = RegionModel.fromMap(map);
    expect(region.id, equals(1));
    expect(region.name, equals('TestRegion'));

    final inside = Coordinate(latitude: -34.601, longitude: -58.381);
    final outside = Coordinate(latitude: -35.0, longitude: -58.0);

    expect(region.contains(inside), isTrue);
    expect(region.contains(outside), isFalse);
  });

  test('GeoTriggerModel mapping and contains', () {
    final map = {
      'id': 2,
      'name': 'TriggerTest',
      'description': 'desc',
      'latitude': -34.786151,
      'longitude': -58.409156,
      'radius_meters': 10.0,
      'audio_asset_id': 1,
      'region_id': 1,
    };

    final trigger = GeoTriggerModel.fromMap(map);
    expect(trigger.id, equals(2));
    expect(trigger.regionId, equals(1));

    final close = Coordinate(latitude: -34.786151, longitude: -58.409156);
    final far = Coordinate(latitude: -34.800, longitude: -58.420);

    expect(trigger.contains(close), isTrue);
    expect(trigger.contains(far), isFalse);
  });
}
