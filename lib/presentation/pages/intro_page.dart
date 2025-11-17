import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../notifiers/permission_notifier.dart';
import '../notifiers/playback_notifier.dart';
import 'home_page.dart';

/// Pantalla de arranque que informa el estado de permisos y guia al usuario.
class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Esperamos un frame para tener un contexto valido y luego verificamos permisos.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PermissionNotifier>().requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final permissionNotifier = context.watch<PermissionNotifier>();

    if (permissionNotifier.isReady && !_navigated) {
      _navigated = true;
      // Una vez listos, preparamos el monitoreo y navegamos a la pantalla principal.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<PlaybackNotifier>().startMonitoring();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      });
    }

    final theme = Theme.of(context);
    final state = permissionNotifier.state;
    final message = permissionNotifier.message ??
        'Configurando permisos para iniciar la experiencia sonora.';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForState(state),
                size: 96,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                _titleForState(state),
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (!_showProgress(state))
                FilledButton.icon(
                  onPressed: () => _handleAction(state, permissionNotifier),
                  icon: Icon(_actionIcon(state)),
                  label: Text(_actionLabel(state)),
                )
              else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  bool _showProgress(PermissionState state) => state == PermissionState.checking;

  void _handleAction(PermissionState state, PermissionNotifier notifier) {
    switch (state) {
      case PermissionState.denied:
      case PermissionState.error:
        notifier.requestPermission();
        break;
      case PermissionState.serviceDisabled:
        Geolocator.openLocationSettings();
        break;
      case PermissionState.deniedForever:
        Geolocator.openAppSettings();
        break;
      case PermissionState.idle:
        notifier.requestPermission();
        break;
      case PermissionState.checking:
      case PermissionState.granted:
        break;
    }
  }

  String _titleForState(PermissionState state) {
    switch (state) {
      case PermissionState.granted:
        return 'Permisos listos!';
      case PermissionState.denied:
        return 'Permiso necesario';
      case PermissionState.deniedForever:
        return 'Habilita el permiso en configuraciones';
      case PermissionState.serviceDisabled:
        return 'Activa tu GPS';
      case PermissionState.error:
        return 'Ups, algo salio mal';
      case PermissionState.checking:
        return 'Verificando acceso';
      case PermissionState.idle:
        return 'Preparando Cingula';
    }
  }

  IconData _iconForState(PermissionState state) {
    switch (state) {
      case PermissionState.granted:
        return Icons.check_circle_outline;
      case PermissionState.denied:
        return Icons.gps_off;
      case PermissionState.deniedForever:
        return Icons.lock_outline;
      case PermissionState.serviceDisabled:
        return Icons.location_disabled;
      case PermissionState.error:
        return Icons.error_outline;
      case PermissionState.checking:
        return Icons.hourglass_top;
      case PermissionState.idle:
        return Icons.audiotrack;
    }
  }

  String _actionLabel(PermissionState state) {
    switch (state) {
      case PermissionState.denied:
      case PermissionState.idle:
      case PermissionState.error:
        return 'Intentar de nuevo';
      case PermissionState.serviceDisabled:
        return 'Abrir configuracion del GPS';
      case PermissionState.deniedForever:
        return 'Abrir configuracion de la app';
      case PermissionState.granted:
        return 'Continuar';
      case PermissionState.checking:
        return '';
    }
  }

  IconData _actionIcon(PermissionState state) {
    switch (state) {
      case PermissionState.denied:
      case PermissionState.idle:
      case PermissionState.error:
        return Icons.refresh;
      case PermissionState.serviceDisabled:
        return Icons.settings;
      case PermissionState.deniedForever:
        return Icons.app_settings_alt;
      case PermissionState.granted:
        return Icons.check;
      case PermissionState.checking:
        return Icons.hourglass_empty;
    }
  }
}
