import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_mode_config.dart';
import '../notifiers/playback_notifier.dart';
import '../widgets/hidden_tap_gesture.dart';
import 'home/widgets/audio_details.dart';
import 'home/widgets/diagnostics_panel.dart';
import 'home/widgets/user_mode_view.dart';

/// Clean HomePage implementation (separate file). This contains the repaired UI.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _toggleMode() async {
    final next = !AppModeConfig.isDebugMode;
    await AppModeConfig.setDebugMode(next);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Modo debug activado' : 'Modo usuario activado'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaybackNotifier>();
    final isDebug = AppModeConfig.isDebugMode;

    return Scaffold(
      appBar: AppBar(
        title: HiddenTapGesture(
          onActivated: _toggleMode,
          child: const Text(
            'Cingula',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2),
          ),
        ),
      ),
      body: isDebug ? _buildDebugBody(context, notifier) : _buildUserBody(notifier),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: notifier.isMonitoring ? notifier.stopMonitoring : notifier.startMonitoring,
        label: Text(notifier.isMonitoring ? 'Detener' : 'Iniciar'),
        icon: Icon(notifier.isMonitoring ? Icons.stop : Icons.play_arrow),
      ),
    );
  }

  Widget _buildUserBody(PlaybackNotifier notifier) {
    return UserModeView(
      isMonitoring: notifier.isMonitoring,
      statusMessage: notifier.statusMessage,
      currentAsset: notifier.currentAsset,
      onMonitoringChanged: (v) =>
          v ? notifier.startMonitoring() : notifier.stopMonitoring(),
    );
  }

  Widget _buildDebugBody(BuildContext context, PlaybackNotifier notifier) {
    final currentAsset = notifier.currentAsset;
    final status = notifier.statusMessage;
    final showAudioCard = currentAsset != null || (status != null && status.toLowerCase().startsWith('reproduciendo'));

    return SingleChildScrollView(
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
          if (showAudioCard)
            currentAsset != null
                ? AudioDetails(asset: currentAsset)
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(status ?? 'Reproduciendo…'),
                    ),
                  ),
          const SizedBox(height: 16),
          const DiagnosticsPanel(),
        ],
      ),
    );
  }
}

// _MiniMapWidget replaced by reusable TriggerMapWidget in lib/presentation/widgets/trigger_map.dart
