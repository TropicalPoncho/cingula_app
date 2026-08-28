import 'package:flutter_test/flutter_test.dart';
import 'package:cingula_app/domain/entities/geo_trigger.dart';
import 'package:cingula_app/domain/entities/geo_path.dart';
import 'package:cingula_app/domain/entities/audio_asset.dart';
import 'package:cingula_app/domain/value_objects/coordinate.dart';
import 'package:cingula_app/domain/usecases/monitor_user_location_usecase.dart';
import 'package:cingula_app/domain/repositories/geo_trigger_repository.dart';
import 'package:cingula_app/domain/repositories/geo_path_repository.dart';
import 'package:cingula_app/domain/repositories/audio_repository.dart';
import 'package:cingula_app/domain/repositories/location_repository.dart';
import 'package:cingula_app/domain/repositories/audio_playback_gateway.dart';
import 'package:cingula_app/domain/entities/region.dart';
import 'package:cingula_app/domain/repositories/region_repository.dart';

// Fakes/simple implementations for testing
class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository(this.coord);
  Coordinate coord;

  @override
  Future<void> ensureServiceAndPermissions() async {}

  @override
  Future<Coordinate> currentPosition() async => coord;

  @override
  Stream<Coordinate> positionStream({double? distanceFilter}) => Stream.empty();
}

class FakeGeoTriggerRepository implements GeoTriggerRepository {
  FakeGeoTriggerRepository(this._triggers);
  final List<GeoTrigger> _triggers;

  @override
  Future<List<GeoTrigger>> fetchAll() async => _triggers;

  @override
  Future<List<GeoTrigger>> fetchByPathId(int pathId) async => _triggers.where((t) => t.geoPathId == pathId).toList(growable: false);

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async {
    for (final t in _triggers) {
      if (t.contains(coordinate)) return t;
    }
    return null;
  }

  @override
  Future<int> insertTrigger(Map<String, Object?> values) async {
    final id = (_triggers.isEmpty) ? 1 : (_triggers.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1);
    final trig = GeoTrigger(
      id: id,
      name: values['name'] as String? ?? 'gen',
      description: values['description'] as String? ?? '',
      latitude: (values['latitude'] as double?) ?? 0.0,
      longitude: (values['longitude'] as double?) ?? 0.0,
      radiusMeters: (values['radius_meters'] as double?) ?? 10.0,
      audioAssetId: (values['audio_asset_id'] as int?) ?? 0,
      regionId: values['region_id'] as int?,
      geoPathId: values['geo_path_id'] as int?,
    );
    _triggers.add(trig);
    return id;
  }

  @override
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    final removed = _triggers.where((t) => t.audioAssetId == audioAssetId).toList(growable: false);
    _triggers.removeWhere((t) => t.audioAssetId == audioAssetId);
    return removed.length;
  }

  @override
  Future<int> deleteOrphaned() async => 0;
}

class FakeGeoPathRepository implements GeoPathRepository {
  FakeGeoPathRepository(this._paths);
  final List<GeoPath> _paths;
  @override
  Future<List<GeoPath>> fetchAll() async => _paths;

  @override
  Future<GeoPath?> fetchById(int id) async {
    try {
      return _paths.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProgress(int pathId, int offsetMs) async {
    final idx = _paths.indexWhere((p) => p.id == pathId);
    if (idx == -1) return;
    _paths[idx] = GeoPath(
      id: _paths[idx].id,
      name: _paths[idx].name,
      audioAssetId: _paths[idx].audioAssetId,
      toleranceMeters: _paths[idx].toleranceMeters,
      savedOffsetMs: offsetMs,
      uuid: _paths[idx].uuid,
      updatedAt: _paths[idx].updatedAt,
      deletedAt: _paths[idx].deletedAt,
      logicalVersion: _paths[idx].logicalVersion,
    );
  }

  @override
  Future<int> createPath({required String name, required int audioAssetId, double toleranceMeters = 10.0}) async {
    final id = (_paths.isEmpty) ? 1 : (_paths.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1);
    final newPath = GeoPath(
      id: id,
      name: name,
      audioAssetId: audioAssetId,
      toleranceMeters: toleranceMeters,
    );
    _paths.add(newPath);
    return id;
  }

  @override
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    final removed = _paths.where((p) => p.audioAssetId == audioAssetId).toList(growable: false);
    _paths.removeWhere((p) => p.audioAssetId == audioAssetId);
    return removed.length;
  }

  @override
  Future<int> deleteById(int pathId) async {
    final removed = _paths.where((p) => p.id == pathId).toList(growable: false);
    _paths.removeWhere((p) => p.id == pathId);
    return removed.length;
  }

  @override
  Future<void> updateAudio({required int pathId, required int audioAssetId}) async {
    final idx = _paths.indexWhere((p) => p.id == pathId);
    if (idx == -1) return;
    final existing = _paths[idx];
    _paths[idx] = GeoPath(
      id: existing.id,
      name: existing.name,
      audioAssetId: audioAssetId,
      toleranceMeters: existing.toleranceMeters,
      savedOffsetMs: existing.savedOffsetMs,
      uuid: existing.uuid,
      updatedAt: existing.updatedAt,
      deletedAt: existing.deletedAt,
      logicalVersion: existing.logicalVersion,
    );
  }
}

class FakeAudioRepository implements AudioRepository {
  FakeAudioRepository(this._assets);
  final List<AudioAsset> _assets;

  @override
  Future<List<AudioAsset>> fetchAll() async => _assets;

  @override
  Future<AudioAsset?> findById(int id) async {
    try {
      return _assets.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> insertLocalRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) async {
    final id = (_assets.isEmpty) ? 1 : (_assets.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1);
    final asset = AudioAsset(
      id: id,
      title: title,
      artist: 'Field Recording',
      description: description,
      duration: duration,
      localPath: localPath,
    );
    _assets.add(asset);
    return id;
  }

  @override
  Future<void> updateDuration({required int id, required Duration duration}) async {
    final idx = _assets.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final existing = _assets[idx];
    _assets[idx] = AudioAsset(
      id: existing.id,
      title: existing.title,
      artist: existing.artist,
      description: existing.description,
      duration: duration,
      localPath: existing.localPath,
      remoteUrl: existing.remoteUrl,
    );
  }
}

class FakeRegionRepository implements RegionRepository {
  @override
  Future<List<Region>> fetchAll() async => [];

  @override
  Future<Region?> findContaining(Coordinate coordinate) async => null;

  @override
  Future<int> createRegion({required double latitude, required double longitude, required String name, required double radiusMeters}) async => 1;
}

class RecordingPlaybackGateway implements AudioPlaybackGateway {
  AudioAsset? playedAsset;
  Duration? playedOffset;
  bool playFromCalled = false;
  bool playCalled = false;
  bool pauseCalled = false;
  Duration currentPositionValue = Duration.zero;

  @override
  AudioAsset? get currentAsset => playedAsset;

  @override
  Future<void> pause() async {
    pauseCalled = true;
  }

  @override
  Future<void> play(AudioAsset asset) async {
    playCalled = true;
    playedAsset = asset;
  }

  @override
  Future<void> playFrom(AudioAsset asset, Duration offset) async {
    playFromCalled = true;
    playedAsset = asset;
    playedOffset = offset;
  }

  @override
  Future<Duration?> currentPosition() async => currentPositionValue;

  void resetFlags() {
    playCalled = false;
    playFromCalled = false;
    playedOffset = null;
    playedAsset = null;
    pauseCalled = false;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  test('executeSingleCheck: trigger with geoPathId plays associated path via playFrom', () async {
  final coord = Coordinate(latitude: -34.786151, longitude: -58.409156, accuracyMeters: 5.0);

    final trigger = GeoTrigger(
      id: 1,
      name: 'T1',
      description: 'd',
      latitude: coord.latitude,
      longitude: coord.longitude,
      radiusMeters: 10.0,
      audioAssetId: 1,
      regionId: 1,
      geoPathId: 1,
    );

    final path = GeoPath(
      id: 1,
      name: 'P1',
      audioAssetId: 2,
      toleranceMeters: 20.0,
      savedOffsetMs: 0,
    );

    final audioAsset = AudioAsset(
      id: 2,
      title: 'path-audio',
      artist: 'artist',
      description: 'desc',
      duration: Duration(seconds: 30),
      localPath: 'assets/audio/x.mp3',
    );

    final locationRepo = FakeLocationRepository(coord);
    final triggerRepo = FakeGeoTriggerRepository([trigger]);
    final pathRepo = FakeGeoPathRepository([path]);
    final audioRepo = FakeAudioRepository([audioAsset]);
    final playback = RecordingPlaybackGateway();

    final usecase = MonitorUserLocationUseCase(
      locationRepository: locationRepo,
      geoTriggerRepository: triggerRepo,
      geoPathRepository: pathRepo,
      regionRepository: FakeRegionRepository(),
      audioRepository: audioRepo,
      playbackGateway: playback,
    );

    await usecase.executeSingleCheck();

    expect(playback.playFromCalled, isTrue);
    expect(playback.playedAsset?.id, equals(audioAsset.id));
  });

  test('executeSingleCheck: trigger without geoPathId plays trigger audio via play', () async {
  final coord = Coordinate(latitude: -34.786151, longitude: -58.409156, accuracyMeters: 5.0);

    final trigger = GeoTrigger(
      id: 2,
      name: 'T2',
      description: 'd',
      latitude: coord.latitude,
      longitude: coord.longitude,
      radiusMeters: 10.0,
      audioAssetId: 3,
      regionId: 1,
      geoPathId: null,
    );

    final audioAsset = AudioAsset(
      id: 3,
      title: 'trigger-audio',
      artist: 'artist',
      description: 'desc',
      duration: Duration(seconds: 20),
      localPath: 'assets/audio/t.mp3',
    );

    final locationRepo = FakeLocationRepository(coord);
    final triggerRepo = FakeGeoTriggerRepository([trigger]);
    final pathRepo = FakeGeoPathRepository([]);
    final audioRepo = FakeAudioRepository([audioAsset]);
    final playback = RecordingPlaybackGateway();

    final usecase = MonitorUserLocationUseCase(
      locationRepository: locationRepo,
      geoTriggerRepository: triggerRepo,
      geoPathRepository: pathRepo,
      regionRepository: FakeRegionRepository(),
      audioRepository: audioRepo,
      playbackGateway: playback,
    );

    await usecase.executeSingleCheck();

    expect(playback.playCalled, isTrue);
    expect(playback.playedAsset?.id, equals(audioAsset.id));
  });

  test('resume from saved offset when re-entering path', () async {
    final inside = Coordinate(latitude: -34.786151, longitude: -58.409156, accuracyMeters: 5.0);
    final outside = Coordinate(latitude: -34.700000, longitude: -58.300000, accuracyMeters: 5.0);

    final trigger = GeoTrigger(
      id: 3,
      name: 'T-path',
      description: 'path trigger',
      latitude: inside.latitude,
      longitude: inside.longitude,
      radiusMeters: 10.0,
      audioAssetId: 4,
      regionId: 1,
      geoPathId: 10,
    );

    final path = GeoPath(
      id: 10,
      name: 'P-resume',
      audioAssetId: 4,
      toleranceMeters: 20.0,
      savedOffsetMs: 0,
    );

    final audioAsset = AudioAsset(
      id: 4,
      title: 'path-audio-resume',
      artist: 'artist',
      description: 'desc',
      duration: Duration(seconds: 60),
      localPath: 'assets/audio/resume.mp3',
    );

    final locationRepo = FakeLocationRepository(inside);
    final triggerRepo = FakeGeoTriggerRepository([trigger]);
    final pathRepo = FakeGeoPathRepository([path]);
    final audioRepo = FakeAudioRepository([audioAsset]);
    final playback = RecordingPlaybackGateway();

    final usecase = MonitorUserLocationUseCase(
      locationRepository: locationRepo,
      geoTriggerRepository: triggerRepo,
      geoPathRepository: pathRepo,
      regionRepository: FakeRegionRepository(),
      audioRepository: audioRepo,
      playbackGateway: playback,
    );

    // First entry should start from offset 0.
    await usecase.executeSingleCheck();
    expect(playback.playFromCalled, isTrue);
    expect(playback.playedOffset, equals(Duration.zero));

    // Simulate progress and exiting the path (three checks outside to trigger pause/save).
    playback.currentPositionValue = const Duration(seconds: 12);
    playback.resetFlags();
    locationRepo.coord = outside;
    await usecase.executeSingleCheck();
    await usecase.executeSingleCheck();
    await usecase.executeSingleCheck();
    expect(playback.pauseCalled, isTrue);
    final savedPath = await pathRepo.fetchById(path.id);
    expect(savedPath?.savedOffsetMs, equals(12000));

    // Re-enter: should resume from saved offset.
    playback.resetFlags();
    locationRepo.coord = inside;
    await usecase.executeSingleCheck();
    expect(playback.playFromCalled, isTrue);
    expect(playback.playedOffset, equals(const Duration(seconds: 12)));
  });
}
