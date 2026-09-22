import 'dart:async';

import 'package:cingula_app/core/background/background_poller.dart';
import 'package:cingula_app/domain/entities/geo_trigger.dart';
import 'package:cingula_app/domain/repositories/audio_playback_gateway.dart';
import 'package:cingula_app/domain/repositories/audio_repository.dart';
import 'package:cingula_app/domain/repositories/geo_path_repository.dart';
import 'package:cingula_app/domain/repositories/geo_trigger_repository.dart';
import 'package:cingula_app/domain/repositories/location_repository.dart';
import 'package:cingula_app/domain/usecases/monitor_user_location_usecase.dart';
import 'package:cingula_app/domain/entities/geo_path.dart';
import 'package:cingula_app/domain/entities/audio_asset.dart';
import 'package:cingula_app/domain/value_objects/coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGeoTriggerRepository implements GeoTriggerRepository {
  final List<GeoTrigger> _list;
  _FakeGeoTriggerRepository(this._list);

  @override
  Future<int> deleteByPathUuid(String pathUuid) async => 0;

  @override
  Future<int> deleteOrphaned() async => 0;

  @override
  Future<List<GeoTrigger>> fetchAll() async => _list;

  @override
  Future<List<GeoTrigger>> fetchByPathUuid(String pathUuid) async =>
      _list.where((t) => t.pathUuid == pathUuid).toList();

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async => null;

  @override
  Future<String> insertTrigger(Map<String, Object?> values) async => 'trigger-generated';
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
  Future<int> deleteByPathUuid(String pathUuid) async => 0;

  @override
  Future<int> deleteOrphaned() async => 0;

  @override
  Future<List<GeoTrigger>> fetchAll() async => [];

  @override
  Future<List<GeoTrigger>> fetchByPathUuid(String pathUuid) async => [];

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async => null;

  @override
  Future<String> insertTrigger(Map<String, Object?> values) async => 'trigger-generated';
}

class _NoopGeoPathRepo implements GeoPathRepository {
  @override
  Future<String> createPath({
    required String name,
    String? audioUuid,
    String? obraUuid,
    String kind = 'route',
    double toleranceMeters = 10.0,
  }) async => 'path-generated';

  @override
  Future<int> deleteByAudioUuid(String audioUuid) async => 0;

  @override
  Future<int> deleteByUuid(String pathUuid) async => 0;

  @override
  Future<List<GeoPath>> fetchAll() async => [];

  @override
  Future<GeoPath?> fetchByUuid(String uuid) async => null;

  @override
  Future<void> saveProgress(String pathUuid, int offsetMs) async {}

  @override
  Future<void> updateAudio({required String pathUuid, required String audioUuid}) async {}
}

class _NoopAudioRepo implements AudioRepository {
  @override
  Future<List<AudioAsset>> fetchAll() async => [];

  @override
  Future<AudioAsset?> findByUuid(String uuid) async => null;

  @override
  Future<String> insertLocalRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) async => 'audio-generated';

  @override
  Future<void> updateDuration({required String uuid, required Duration duration}) async {}
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
      uuid: 'trigger-1',
      pathUuid: 'path-1',
      name: 't',
      description: '',
      latitude: 0.0,
      longitude: 0.0,
      radiusMeters: 10.0,
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
