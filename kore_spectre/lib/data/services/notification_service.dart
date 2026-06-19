import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/monitor.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'korespectre_alerts';
  static const _channelName = 'Alertas de Monitor';

  Future<void> initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notificações de status do datacenter',
      importance: Importance.max,
    ));

    // Android 13+ requer permissão em runtime
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> show(String title, String body) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> showStatusChange(
    String name,
    MonitorStatus status, {
    DateTime? at,
  }) async {
    final time = _formatTime(at ?? DateTime.now());
    if (status == MonitorStatus.down) {
      await show('$name OFFLINE', 'Monitor caiu às $time');
    } else if (status == MonitorStatus.up) {
      await show('$name ONLINE', 'Monitor recuperado às $time');
    }
  }

  Future<void> showTestNotification() =>
      show('KoreSpectre', 'Notificações funcionando corretamente!');

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

}
