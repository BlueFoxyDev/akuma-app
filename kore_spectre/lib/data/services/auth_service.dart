import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

class AuthService {
  final SecureStorageService _storage;

  AuthService(this._storage);

  Future<bool> validateConnection(String host, int port, String apiToken) async {
    if (apiToken.isEmpty) return false;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {'X-Api-Key': apiToken},
      ));
      // Usa /monitors em vez de /health porque /health não requer autenticação
      final resp = await dio.get('http://$host:$port/monitors');
      return resp.statusCode == 200;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return false;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connect(String host, int port, String apiToken) async {
    final ok = await validateConnection(host, port, apiToken);
    if (ok) {
      await _storage.saveUptimeKumaConfig(host: host, port: port);
      await _storage.saveApiToken(apiToken);
    }
    return ok;
  }

  Future<void> disconnect() => _storage.deleteApiToken();
}
