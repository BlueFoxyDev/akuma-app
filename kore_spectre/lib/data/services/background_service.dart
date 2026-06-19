import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';
import '../models/monitor.dart';

@pragma('vm:entry-point')
void backgroundServiceMain(ServiceInstance service) async {
  final storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  final config = await Future.wait([
    storage.read(key: AppConstants.keyUptimeKumaHost),
    storage.read(key: AppConstants.keyUptimeKumaPort),
  ]);

  final host = config[0] ?? AppConstants.defaultUptimeKumaHost;
  final port = int.tryParse(config[1] ?? '') ?? AppConstants.defaultUptimeKumaPort;
  final apiBase = 'http://$host:$port';
  const apiKey = 'korespectre2024';

  final Map<int, MonitorStatus> lastStatus = {};
  bool stopped = false;

  service.on('stopService').listen((_) {
    stopped = true;
    service.stopSelf();
  });

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  Future<void> poll() async {
    try {
      final uri = Uri.parse('$apiBase/monitors');
      final req = await client.getUrl(uri);
      req.headers.set('X-Api-Key', apiKey);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;

      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = data['monitors'] as List<dynamic>?;
      if (list == null) return;

      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['id'] as num?)?.toInt();
        if (id == null) continue;
        final statusStr = item['status']?.toString();
        final current = _statusFromString(statusStr);
        final previous = lastStatus[id];
        lastStatus[id] = current;

        if (previous != null && previous != current) {
          final name = item['name']?.toString() ?? 'Monitor $id';
          if (current == MonitorStatus.down) {
            _sendNotification(notifications, '$name OFFLINE',
                'Monitor caiu — verifique seu datacenter');
          } else if (current == MonitorStatus.up && previous != MonitorStatus.unknown) {
            _sendNotification(notifications, '$name ONLINE',
                'Monitor recuperado com sucesso');
          }
          service.invoke('statusChange', {
            'monitorId': id,
            'status': current.name,
            'name': name,
          });
        }
      }
    } catch (_) {
      // ignore poll errors — will retry next interval
    }
  }

  while (!stopped) {
    await poll();
    await Future.delayed(const Duration(seconds: 60));
  }
  client.close();
}

MonitorStatus _statusFromString(String? s) => switch (s) {
      'up' => MonitorStatus.up,
      'down' => MonitorStatus.down,
      'pending' => MonitorStatus.pending,
      'maintenance' => MonitorStatus.maintenance,
      _ => MonitorStatus.unknown,
    };

void _sendNotification(
    FlutterLocalNotificationsPlugin plugin, String title, String body) {
  plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'korespectre_alerts',
        'Alertas de Monitor',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

class BackgroundServiceManager {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundServiceMain,
        isForegroundMode: true,
        autoStart: false,
        notificationChannelId: 'korespectre_bg',
        initialNotificationTitle: 'KoreSpectre',
        initialNotificationContent: 'Monitorando datacenter...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  static Future<bool> isRunning() => FlutterBackgroundService().isRunning();
}
