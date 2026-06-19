import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/app_constants.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  Future<void> saveUptimeKumaConfig({
    required String host,
    required int port,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.keyUptimeKumaHost, value: host),
      _storage.write(key: AppConstants.keyUptimeKumaPort, value: port.toString()),
    ]);
  }

  Future<Map<String, String?>> getUptimeKumaConfig() async {
    final results = await Future.wait([
      _storage.read(key: AppConstants.keyUptimeKumaHost),
      _storage.read(key: AppConstants.keyUptimeKumaPort),
    ]);
    return {
      'host': results[0] ?? AppConstants.defaultUptimeKumaHost,
      'port': results[1] ?? AppConstants.defaultUptimeKumaPort.toString(),
    };
  }

  Future<void> saveApiToken(String token) =>
      _storage.write(key: AppConstants.keyApiToken, value: token);

  Future<String?> getApiToken() =>
      _storage.read(key: AppConstants.keyApiToken);

  Future<void> deleteApiToken() =>
      _storage.delete(key: AppConstants.keyApiToken);

  Future<void> saveFcmToken(String token) =>
      _storage.write(key: AppConstants.keyFcmToken, value: token);

  Future<String?> getFcmToken() =>
      _storage.read(key: AppConstants.keyFcmToken);

  Future<void> saveMaintenanceIds(Set<int> ids) =>
      _storage.write(key: 'maintenanceIds', value: ids.join(','));

  Future<Set<int>> getMaintenanceIds() async {
    final raw = await _storage.read(key: 'maintenanceIds');
    if (raw == null || raw.isEmpty) return {};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> clearAll() => _storage.deleteAll();
}
