import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../notifiers/playback_notifier.dart';
import 'home/widgets/audio_details.dart';
import 'home/widgets/diagnostics_panel.dart';

/// Clean HomePage implementation (separate file). This contains the repaired UI.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaybackNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cingula')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Monitorear ubicacion en segundo plano'),
              subtitle: Text(notifier.statusMessage ?? 'Listo para iniciar'),
              value: notifier.isMonitoring,
              onChanged: (v) => v ? notifier.startMonitoring() : notifier.stopMonitoring(),
            ),
            const SizedBox(height: 24),
            if (notifier.currentAsset != null) AudioDetails(asset: notifier.currentAsset!),
            const SizedBox(height: 16),
            const DiagnosticsPanel(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: notifier.isMonitoring ? notifier.stopMonitoring : notifier.startMonitoring,
        label: Text(notifier.isMonitoring ? 'Detener' : 'Iniciar'),
        icon: Icon(notifier.isMonitoring ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}

// _MiniMapWidget replaced by reusable TriggerMapWidget in lib/presentation/widgets/trigger_map.dart
