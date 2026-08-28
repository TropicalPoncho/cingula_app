import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_mode_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/services/recorder_service.dart';
import '../../data/datasources/local/app_database.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showRecoveryBannerIfNeeded());
  }

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

  void _showRecoveryBannerIfNeeded() {
    final db = getIt<AppDatabase>();
    final event = db.lastRecoveryEvent;
    if (event == null || !mounted) return;
    // One-shot: limpiamos para que no reaparezca al volver a esta pantalla.
    db.lastRecoveryEvent = null;

    final cs = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: cs.errorContainer,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Base de datos restaurada automáticamente',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.2,
                color: cs.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Detectamos un problema al abrir tus datos. Guardamos una copia en '
              '${event.backupFileName} y la app sigue funcionando con normalidad.',
              style: TextStyle(fontSize: 16, height: 1.5, color: cs.onErrorContainer),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Entendido'),
          ),
        ],
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
    final recorder = getIt<RecorderService>();
    final currentAsset = notifier.currentAsset;
    final status = notifier.statusMessage;
    final showAudioCard = currentAsset != null || (status != null && status.toLowerCase().startsWith('reproduciendo'));

    return Stack(
      children: [
        SingleChildScrollView(
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
        ),
        _RecordingBanner(recorder: recorder),
      ],
    );
  }
}

// _MiniMapWidget replaced by reusable TriggerMapWidget in lib/presentation/widgets/trigger_map.dart

class _RecordingBanner extends StatefulWidget {
  const _RecordingBanner({required this.recorder});

  final RecorderService recorder;

  @override
  State<_RecordingBanner> createState() => _RecordingBannerState();
}

class _RecordingBannerState extends State<_RecordingBanner> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  RecordingStatus _status = const RecordingStatus();

  @override
  void initState() {
    super.initState();
    widget.recorder.recordingStatus.addListener(_handleStatusChange);
    _handleStatusChange();
  }

  @override
  void dispose() {
    widget.recorder.recordingStatus.removeListener(_handleStatusChange);
    _ticker?.cancel();
    super.dispose();
  }

  void _handleStatusChange() {
    final next = widget.recorder.recordingStatus.value;
    if (!next.isRecording || next.startedAt == null) {
      _ticker?.cancel();
      setState(() {
        _elapsed = Duration.zero;
        _status = next;
      });
      return;
    }

    _ticker?.cancel();
    setState(() {
      _status = next;
      _elapsed = DateTime.now().difference(next.startedAt!);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || widget.recorder.recordingStatus.value.startedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(widget.recorder.recordingStatus.value.startedAt!);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_status.isRecording || _status.startedAt == null) return const SizedBox.shrink();

    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final label = _status.label ?? 'Grabando micrófono';

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            color: Colors.red.shade50,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, color: Colors.red.shade400),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('$minutes:$seconds', style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
