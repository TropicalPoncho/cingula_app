import 'package:flutter_test/flutter_test.dart';

import 'package:cingula_app/domain/value_objects/coordinate.dart';
import 'package:cingula_app/presentation/notifiers/permission_notifier.dart';
import 'package:cingula_app/domain/repositories/location_repository.dart';

class _FakeLocationRepository implements LocationRepository {
  bool ensureCalled = false;

  @override
  Future<void> ensureServiceAndPermissions() async {
    ensureCalled = true;
  }

  @override
  Future<Coordinate> currentPosition() async =>
      const Coordinate(latitude: 0, longitude: 0);

  @override
  Stream<Coordinate> positionStream({double distanceFilter = 25}) =>
      const Stream.empty();
}

void main() {
  test('PermissionNotifier reports granted when repository succeeds', () async {
    final repository = _FakeLocationRepository();
    final notifier = PermissionNotifier(locationRepository: repository);

    await notifier.requestPermission();

    expect(repository.ensureCalled, isTrue);
    expect(notifier.state, PermissionState.granted);
    expect(notifier.isReady, isTrue);
  });
}
