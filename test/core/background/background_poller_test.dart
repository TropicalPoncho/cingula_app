import 'dart:async';

import 'package:cingula_app/core/background/background_poller.dart';
import 'package:cingula_app/domain/entities/geo_trigger.dart';
import 'package:cingula_app/domain/repositories/audio_playback_gateway.dart';
import 'package:cingula_app/domain/repositories/audio_repository.dart';
import 'package:cingula_app/domain/repositories/geo_path_repository.dart';
import 'package:cingula_app/domain/repositories/geo_trigger_repository.dart';
import 'package:cingula_app/domain/repositories/location_repository.dart';
import 'package:cingula_app/domain/repositories/region_repository.dart';
import 'package:cingula_app/domain/usecases/monitor_user_location_usecase.dart';
import 'package:cingula_app/domain/entities/geo_path.dart';
import 'package:cingula_app/domain/entities/region.dart';
import 'package:cingula_app/domain/entities/audio_asset.dart';
import 'package:cingula_app/domain/value_objects/coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGeoTriggerRepository implements GeoTriggerRepository {
  final List<GeoTrigger> _list;
  _FakeGeoTriggerRepository(this._list);

  @override
  Future<int> deleteByAudioAssetId(int audioAssetId) async => 0;

  @override
  Future<int> deleteOrphaned() async => 0;

  @override
  Future<List<GeoTrigger>> fetchAll() async => _list;

  @override
  Future<List<GeoTrigger>> fetchByPathId(int pathId) async => _list.where((t) => t.geoPathId == pathId).toList();

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async => null;

  @override
  Future<int> insertTrigger(Map<String, Object?> values) async => 1;
}

class _FakeLocationRepository implements LocationRepository {
  final Coordinate _pos;
  _FakeLocationRepository(this._pos);

  @override
  Future<void> ensureServiceAndPermissions() async => Future.value();

  @override
  Stream<Coordinate> positionStream({double distanceFilter = 0}) => Stream.empty();

  @override
  Future<Coordinate> currentPosition() async => _pos;
}

// Minimal fakes to satisfy MonitorUserLocationUseCase constructor.


class _SpyMonitor extends MonitorUserLocationUseCase {
  int calls = 0;

  _SpyMonitor()
      : super(
          locationRepository: _NoopLocationRepo(),
          geoTriggerRepository: _NoopGeoTriggerRepo(),
          geoPathRepository: _NoopGeoPathRepo(),
          regionRepository: _NoopRegionRepo(),
          audioRepository: _NoopAudioRepo(),
          playbackGateway: _NoopPlaybackGateway(),
        );

  @override
  Future<void> executeSingleCheck() async {
    calls++;
  }
}

// No-op repos used only to satisfy super constructor; never used in tests.
class _NoopLocationRepo implements LocationRepository {
  @override
  Future<void> ensureServiceAndPermissions() async {}

  @override
  Stream<Coordinate> positionStream({double distanceFilter = 0}) => const Stream.empty();

  @override
  Future<Coordinate> currentPosition() async => const Coordinate(latitude: 0, longitude: 0);
}

class _NoopGeoTriggerRepo implements GeoTriggerRepository {
  @override
  Future<int> deleteByAudioAssetId(int audioAssetId) async => 0;

  @override
  Future<int> deleteOrphaned() async => 0;

  @override
  Future<List<GeoTrigger>> fetchAll() async => [];

  @override
  Future<List<GeoTrigger>> fetchByPathId(int pathId) async => [];

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async => null;

  @override
  Future<int> insertTrigger(Map<String, Object?> values) async => 1;
}

class _NoopGeoPathRepo implements GeoPathRepository {
  @override
  Future<int> createPath({required String name, required int audioAssetId, double toleranceMeters = 10.0}) async => 1;

  @override
  Future<int> deleteByAudioAssetId(int audioAssetId) async => 0;

  @override
  Future<int> deleteById(int pathId) async => 0;

  @override
  Future<List<GeoPath>> fetchAll() async => [];

  @override
  Future<GeoPath?> fetchById(int id) async => null;

  @override
  Future<void> saveProgress(int pathId, int offsetMs) async {}
}

class _NoopRegionRepo implements RegionRepository {
  @override
  Future<List<Region>> fetchAll() async => [];

  @override
  Future<Region?> findContaining(Coordinate coordinate) async => null;

  @override
  Future<int> createRegion({required double latitude, required double longitude, required String name, required double radiusMeters}) async => 1;
}

class _NoopAudioRepo implements AudioRepository {
  @override
  Future<List<AudioAsset>> fetchAll() async => [];

  @override
  Future<AudioAsset?> findById(int id) async => null;

  @override
  Future<int> insertLocalRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) async => 1;

  @override
  Future<void> updateDuration({required int id, required Duration duration}) async {}
}

class _NoopPlaybackGateway implements AudioPlaybackGateway {
  @override
  Future<void> pause() async {}

  @override
  Future<void> play(audioAsset) async {}

  @override
  Future<void> playFrom(audioAsset, Duration offset) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<Duration?> currentPosition() async => null;

  @override
  get currentAsset => null;
}

void main() {
  test('poller calls executeSingleCheck and adapts interval when triggers are near', () async {
    // position at origin
    final pos = Coordinate(latitude: 0.0, longitude: 0.0);
    final locRepo = _FakeLocationRepository(pos);

    // create a trigger exactly at origin -> nearest = 0
    final trigger = GeoTrigger(
      id: 1,
      name: 't',
      description: '',
      latitude: 0.0,
      longitude: 0.0,
      radiusMeters: 10.0,
      audioAssetId: 1,
    );
    final triggerRepo = _FakeGeoTriggerRepository([trigger]);

    final spy = _SpyMonitor();
    final logs = <String>[];
    final poller = BackgroundAdaptivePoller(
      monitorUseCase: spy,
      triggerRepository: triggerRepo,
      locationRepository: locRepo,
      onLog: (m) => logs.add(m),
    );

    await poller.start();

    // After start(), executeSingleCheck should have been called at least once.
    expect(spy.calls, greaterThanOrEqualTo(1));

    // Logs should contain nearest trigger info
    expect(logs.any((l) => l.contains('nearest trigger')), isTrue);

    // Should have adjusted interval away from default (30s) towards a smaller value
    expect(logs.any((l) => l.contains('interval changing')), isTrue);

    await poller.stop();
  });
}
