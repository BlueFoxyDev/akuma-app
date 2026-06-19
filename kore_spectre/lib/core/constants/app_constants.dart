class AppConstants {
  static const String appName = 'KoreSpectre';
  static const String appVersion = '1.0.0';

  // Uptime Kuma padrão (pode ser alterado em configurações)
  static const String defaultUptimeKumaHost = '10.50.124.44'; // use IP publico fora da LAN
  static const int defaultUptimeKumaPort = 8765; // porta da API Bridge

  // Secure storage keys
  static const String keyUptimeKumaHost = 'uptime_kuma_host';
  static const String keyUptimeKumaPort = 'uptime_kuma_port';
  static const String keyApiToken       = 'api_token';
  static const String keyFcmToken       = 'fcm_token';

  // SharedPreferences keys
  static const String prefNotificationsEnabled = 'notifications_enabled';
  static const String prefThemeMode = 'theme_mode';
}
