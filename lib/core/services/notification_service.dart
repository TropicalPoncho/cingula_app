import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Pequeño wrapper para mostrar notificaciones locales persistentes durante la grabación.
class NotificationService {
  NotificationService();

  static const int _recordingNotificationId = 1001;
  static const String _recordingChannelId = 'recording_channel';
  static const String _recordingChannelName = 'Grabación';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showRecordingNotification({required String title, required String body}) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      _recordingChannelId,
      _recordingChannelName,
      channelDescription: 'Estado de grabación de micrófono',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentBanner: true, presentList: true, presentSound: false),
    );

    await _plugin.show(_recordingNotificationId, title, body, details);
  }

  Future<void> clearRecordingNotification() async {
    await init();
    await _plugin.cancel(_recordingNotificationId);
  }
}