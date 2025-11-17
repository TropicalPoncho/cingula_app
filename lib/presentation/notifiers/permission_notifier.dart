import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/repositories/location_repository.dart';

/// Estados de alto nivel para comunicar la situacion del permiso.
enum PermissionState {
  idle,
  checking,
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  error,
}

/// Gestiona el ciclo de solicitud de permisos de geolocalizacion en la pantalla inicial.
class PermissionNotifier extends ChangeNotifier {
  PermissionNotifier({required LocationRepository locationRepository})
      : _locationRepository = locationRepository;

  final LocationRepository _locationRepository;

  PermissionState _state = PermissionState.idle;
  String? _message;

  PermissionState get state => _state;
  String? get message => _message;

  bool get isReady => _state == PermissionState.granted;

  /// Intenta obtener permisos y reporta los resultados a la UI.
  Future<void> requestPermission() async {
    _setState(PermissionState.checking, 'Comprobando permisos de ubicacion.');

    try {
      await _locationRepository.ensureServiceAndPermissions();
      _setState(PermissionState.granted, 'Permisos concedidos. Todo listo!');
    } on LocationServiceDisabledException {
      _setState(
        PermissionState.serviceDisabled,
        'Activa el GPS del dispositivo para continuar.',
      );
    } on PermissionDeniedException {
      _setState(
        PermissionState.denied,
        'Necesitamos tu permiso de ubicacion para reproducir audio contextual.',
      );
    } on PermissionDefinitionsNotFoundException {
      _setState(
        PermissionState.deniedForever,
        'Permiso denegado permanentemente. Abre la configuracion para habilitarlo.',
      );
    } catch (error) {
      _setState(
        PermissionState.error,
        'Ocurrio un error inesperado: $error',
      );
    }
  }

  void _setState(PermissionState newState, String? message) {
    _state = newState;
    _message = message;
    notifyListeners();
  }
}
