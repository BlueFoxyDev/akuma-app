import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'app.dart';
import 'core/providers.dart';
import 'data/services/background_service.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cria canais de notificação antes do background service iniciar
  // (o canal korespectre_bg precisa existir antes de startForeground())
  final notifPlugin = FlutterLocalNotificationsPlugin();
  await notifPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final androidPlugin = notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    'korespectre_bg',
    'KoreSpectre Background',
    description: 'Monitorando datacenter em background',
    importance: Importance.low,
  ));
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    'korespectre_alerts',
    'Alertas de Monitor',
    description: 'Notificações de status do datacenter',
    importance: Importance.max,
  ));
  await androidPlugin?.requestNotificationsPermission();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());

  await BackgroundServiceManager.initialize();

  final container = ProviderContainer();
  final notifService = container.read(notificationServiceProvider);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final n = message.notification;
    if (n != null) {
      notifService.show(n.title ?? 'KoreSpectre', n.body ?? '');
    }
  });

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KoreSpectreApp(),
    ),
  );
}
