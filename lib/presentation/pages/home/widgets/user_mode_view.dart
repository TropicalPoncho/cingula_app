import 'package:flutter/material.dart';

import '../../../../domain/entities/audio_asset.dart';
import 'audio_details.dart';

/// Cuerpo de la pantalla en modo usuario final, según 01-UI-SPEC.md.
/// No depende de getIt/provider: recibe todo por parámetros.
class UserModeView extends StatelessWidget {
  const UserModeView({
    super.key,
    required this.isMonitoring,
    required this.statusMessage,
    required this.currentAsset,
    required this.onMonitoringChanged,
  });

  final bool isMonitoring;
  final String? statusMessage;
  final AudioAsset? currentAsset;
  final ValueChanged<bool> onMonitoringChanged;

  String get _statusText =>
      statusMessage ??
      (isMonitoring
          ? 'Caminando… te avisamos cuando estés cerca de un punto sonoro.'
          : 'Listo para iniciar');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isMonitoring ? Icons.hearing : Icons.play_circle_outline,
            size: 48,
            color: isMonitoring ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
          ),
          const SizedBox(height: 32),
          Card(
            color: cs.surfaceContainer,
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text(
                'Monitorear ubicacion en segundo plano',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              value: isMonitoring,
              onChanged: onMonitoringChanged,
            ),
          ),
          const SizedBox(height: 24),
          if (currentAsset != null) AudioDetails(asset: currentAsset!),
        ],
      ),
    );
  }
}
