import 'package:flutter_test/flutter_test.dart';
import 'package:cingula_app/domain/entities/geo_path.dart';

void main() {
  test('GeoPath is metadata only (id/name/audioAssetId)', () {
    final path = GeoPath(id: 1, name: 'seg', audioAssetId: 1);
    expect(path.id, equals(1));
    expect(path.name, equals('seg'));
    expect(path.audioAssetId, equals(1));
  });
}
