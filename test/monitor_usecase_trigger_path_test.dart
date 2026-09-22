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
  Future<List<GeoTrigger>> fetchByPathUuid(String pathUuid) async =>
      _triggers.where((t) => t.pathUuid == pathUuid).toList(growable: false);

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async {
    for (final t in _triggers) {
      if (t.contains(coordinate)) return t;
    }
    return null;
  }

  @override
  Future<String> insertTrigger(Map<String, Object?> values) async {
    final uuid = 'trigger-${_triggers.length + 1}';
    final trig = GeoTrigger(
      uuid: uuid,
      pathUuid: values['path_uuid'] as String,
      name: values['name'] as String? ?? 'gen',
      description: values['description'] as String? ?? '',
      latitude: (values['latitude'] as double?) ?? 0.0,
      longitude: (values['longitude'] as double?) ?? 0.0,
      radiusMeters: (values['radius_meters'] as double?) ?? 10.0,
      offsetMs: (values['offset_ms'] as int?) ?? 0,
    );
    _triggers.add(trig);
    return uuid;
  }

  @override
  Future<int> deleteByPathUuid(String pathUuid) async {
    final removed = _triggers.where((t) => t.pathUuid == pathUuid).toList(growable: false);
    _triggers.removeWhere((t) => t.pathUuid == pathUuid);
    return removed.length;
  }

  @override
  Future<int> deleteOrphaned() async => 0;
}

class FakeGeoPathRepository implements GeoPathRepository {
  FakeGeoPathRepository(this._paths);
  final List<GeoPath> _paths;
  int saveProgressCalls = 0;

  @override
  Future<List<GeoPath>> fetchAll() async => _paths;

  @override
  Future<GeoPath?> fetchByUuid(String uuid) async {
    try {
      return _paths.firstWhere((p) => p.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProgress(String pathUuid, int offsetMs) async {
    saveProgressCalls++;
    final idx = _paths.indexWhere((p) => p.uuid == pathUuid);
    if (idx == -1) return;
    _paths[idx].savedOffsetMs = offsetMs;
  }

  @override
  Future<String> createPath({
    required String name,
    String? audioUuid,
    String? obraUuid,
    String kind = 'route',
    double toleranceMeters = 10.0,
  }) async {
    final uuid = 'path-${_paths.length + 1}';
    _paths.add(GeoPath(
      uuid: uuid,
      obraUuid: obraUuid ?? 'obra-auto',
      name: name,
      kind: kind,
      audioUuid: audioUuid,
      toleranceMeters: toleranceMeters,
    ));
    return uuid;
  }

  @override
  Future<int> deleteByAudioUuid(String audioUuid) async {
    final removed = _paths.where((p) => p.audioUuid == audioUuid).toList(growable: false);
    _paths.removeWhere((p) => p.audioUuid == audioUuid);
    return removed.length;
  }

  @override
  Future<int> deleteByUuid(String pathUuid) async {
    final removed = _paths.where((p) => p.uuid == pathUuid).toList(growable: false);
    _paths.removeWhere((p) => p.uuid == pathUuid);
    return removed.length;
  }

  @override
  Future<void> updateAudio({required String pathUuid, required String audioUuid}) async {
    final idx = _paths.indexWhere((p) => p.uuid == pathUuid);
    if (idx == -1) return;
    _paths[idx] = GeoPath(
      uuid: _paths[idx].uuid,
      obraUuid: _paths[idx].obraUuid,
      name: _paths[idx].name,
      kind: _paths[idx].kind,
      audioUuid: audioUuid,
      toleranceMeters: _paths[idx].toleranceMeters,
      savedOffsetMs: _paths[idx].savedOffsetMs,
    );
  }
}

class FakeAudioRepository implements AudioRepository {
  FakeAudioRepository(this._assets);
  final List<AudioAsset> _assets;

  @override
  Future<List<AudioAsset>> fetchAll() async => _assets;

  @override
  Future<AudioAsset?> findByUuid(String uuid) async {
    try {
      return _assets.firstWhere((a) => a.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> insertLocalRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) async {
    final uuid = 'audio-${_assets.length + 1}';
    _assets.add(AudioAsset(uuid: uuid, title: title, description: description, duration: duration, localPath: localPath));
    return uuid;
  }

  @override
  Future<void> updateDuration({required String uuid, required Duration duration}) async {
    final idx = _assets.indexWhere((a) => a.uuid == uuid);
    if (idx == -1) return;
    final existing = _assets[idx];
    _assets[idx] = AudioAsset(
      uuid: existing.uuid,
      title: existing.title,
      description: existing.description,
      duration: duration,
      localPath: existing.localPath,
      kind: existing.kind,
      remoteUrl: existing.remoteUrl,
    );
  }
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
  test('executeSingleCheck: trigger de un path route reproduce via playFrom', () async {
    final coord = Coordinate(latitude: -34.786151, longitude: -58.409156, accuracyMeters: 5.0);

    final path = GeoPath(
      uuid: 'path-1',
      obraUuid: 'obra-1',
      name: 'P1',
      kind: 'route',
      audioUuid: 'audio-2',
      toleranceMeters: 20.0,
      savedOffsetMs: 0,
    );

    final trigger = GeoTrigger(
      uuid: 'trigger-1',
      pathUuid: 'path-1',
      name: 'T1',
      description: 'd',
      latitude: coord.latitude,
      longitude: coord.longitude,
      radiusMeters: 10.0,
    );

    final audioAsset = AudioAsset(
      uuid: 'audio-2',
      title: 'path-audio',
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
      audioRepository: audioRepo,
      playbackGateway: playback,
    );

    await usecase.executeSingleCheck();

    expect(playback.playFromCalled, isTrue);
    expect(playback.playedAsset?.uuid, equals(audioAsset.uuid));
  });

  test('un path kind=portal arranca en 0 y no guarda progreso al salir', () async {
    final inside = Coordinate(latitude: -34.786151, longitude: -58.409156, accuracyMeters: 5.0);
    final outside = Coordinate(latitude: -34.700000, longitude: -58.300000, accuracyMeters: 5.0);

    final path = GeoPath(
      uuid: 'path-portal',
      obraUuid: 'obra-portal',
      name: 'Portal 1',
      kind: 'portal',
      audioUuid: 'audio-3',
      toleranceMeters: 20.0,
      savedOffsetMs: 0,
    );

    // offsetMs != 0 a propósito: un portal debe ignorarlo y arrancar en 0.
    final trigger = GeoTrigger(
      uuid: 'trigger-portal',
      pathUuid: 'path-portal',
      name: 'T-portal',
      description: 'd',
      latitude: inside.latitude,
      longitude: inside.longitude,
      radiusMeters: 10.0,
      offsetMs: 5000,
    );

    final audioAsset = AudioAsset(
      uuid: 'audio-3',
      title: 'portal-audio',
      description: 'desc',
      duration: Duration(seconds: 20),
      localPath: 'assets/audio/portal.mp3',
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
      audioRepository: audioRepo,
      playbackGateway: playback,
    );

    await usecase.executeSingleCheck();
    expect(playback.playFromCalled, isTrue);
    expect(playback.playedOffset, equals(Duration.zero));

    // Salir de la zona (tres checks fuera) no debe guardar progreso: el
    // portal siempre vuelve a arrancar en 0.
    playback.currentPositionValue = const Duration(seconds: 5);
    playback.resetFlags();
    locationRepo.coord = outside;
    await usecase.executeSingleCheck();
    await usecase.executeSingleCheck();
    await usecase.executeSingleCheck();

    expect(playback.pauseCalled, isTrue);
    expect(pathRepo.saveProgressCalls, equals(0));

    // Re-entrar: vuelve a arrancar en 0, no en el offset del trigger ni en
    // ningún progreso guardado.
    playback.resetFlags();
    locationRepo.coord = inside;
    await usecase.executeSingleCheck();
    expect(playback.playFromCalled, isTrue);
    expect(playback.playedOffset, equals(Duration.zero));
  });

  test('resume from saved offset when re-entering a route path', () async {
    final inside = Coordinate(latitude: -34.786151, longitude: -58.409156, accuracyMeters: 5.0);
    final outside = Coordinate(latitude: -34.700000, longitude: -58.300000, accuracyMeters: 5.0);

    final path = GeoPath(
      uuid: 'path-resume',
      obraUuid: 'obra-resume',
      name: 'P-resume',
      kind: 'route',
      audioUuid: 'audio-4',
      toleranceMeters: 20.0,
      savedOffsetMs: 0,
    );

    final trigger = GeoTrigger(
      uuid: 'trigger-resume',
      pathUuid: 'path-resume',
      name: 'T-path',
      description: 'path trigger',
      latitude: inside.latitude,
      longitude: inside.longitude,
      radiusMeters: 10.0,
    );

    final audioAsset = AudioAsset(
      uuid: 'audio-4',
      title: 'path-audio-resume',
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
    final savedPath = await pathRepo.fetchByUuid(path.uuid);
    expect(savedPath?.savedOffsetMs, equals(12000));

    // Re-enter: should resume from saved offset.
    playback.resetFlags();
    locationRepo.coord = inside;
    await usecase.executeSingleCheck();
    expect(playback.playFromCalled, isTrue);
    expect(playback.playedOffset, equals(const Duration(seconds: 12)));
  });
}
