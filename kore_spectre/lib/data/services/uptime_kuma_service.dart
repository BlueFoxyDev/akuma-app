import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/monitor.dart';
import '../models/heartbeat.dart';

enum UptimeKumaConnectionState {
  disconnected,
  connecting,
  connected,
  authenticated,
  error,
}

class UptimeKumaService {
  Dio? _dio;
  Timer? _pollTimer;
  UptimeKumaConnectionState _state = UptimeKumaConnectionState.disconnected;

  final _connectionStateController =
      StreamController<UptimeKumaConnectionState>.broadcast();
  final _monitorsController =
      StreamController<Map<int, Monitor>>.broadcast();
  final _heartbeatController = StreamController<Heartbeat>.broadcast();
  final _errorController     = StreamController<String>.broadcast();

  Stream<UptimeKumaConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<Map<int, Monitor>> get monitorsStream => _monitorsController.stream;
  Stream<Heartbeat> get heartbeatStream        => _heartbeatController.stream;
  Stream<String> get errorStream               => _errorController.stream;
  UptimeKumaConnectionState get currentState   => _state;

  String _apiBase  = '';
  String _apiToken = '';

  final Map<int, Monitor> _monitors = {};
  Map<int, Monitor> get monitors => Map.unmodifiable(_monitors);
  bool _fetching  = false;
  bool _firstPoll = true;
  int _lastEventId = 0;

  // IDs de manutenção carregados ANTES do primeiro poll — evita alertas falsos
  Set<int> _maintenanceIds = {};

  UptimeKumaService() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint('[KumaService] Token FCM renovado, re-registrando...');
      if (_state == UptimeKumaConnectionState.authenticated && _dio != null) {
        _registerFcmToken();
      }
    });
  }

  void _setState(UptimeKumaConnectionState state) {
    _state = state;
    _connectionStateController.add(state);
  }

  Future<bool> connect({
    required String host,
    required int port,
    required String apiToken,
  }) async {
    _setState(UptimeKumaConnectionState.connecting);
    _pollTimer?.cancel();
    _firstPoll   = true;
    _lastEventId = 0;
    _apiBase     = 'http://$host:$port';
    _apiToken    = apiToken;

    _dio = Dio(BaseOptions(
      baseUrl:        _apiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'X-Api-Key': _apiToken},
    ));

    debugPrint('[KumaService] Conectando à API Bridge em $_apiBase');

    try {
      final resp = await _dio!.get('/health');
      if (resp.statusCode == 200 && resp.data['ok'] == true) {
        // Carrega manutenção ANTES dos polls para filtrar heartbeats corretamente
        _maintenanceIds = await _fetchMaintenanceFromApi();
        debugPrint('[KumaService] ${_maintenanceIds.length} monitores em manutenção carregados');
        _setState(UptimeKumaConnectionState.authenticated);
        await _fetchMonitors();
        await _fetchMissedEvents();
        _startPolling();
        await _registerFcmToken();
        return true;
      } else {
        _setState(UptimeKumaConnectionState.error);
        _errorController.add('Bridge respondeu com erro');
        _startPolling();
        return false;
      }
    } on DioException catch (e) {
      final msg = 'Erro ao conectar à API Bridge: ${e.message}';
      debugPrint('[KumaService] $msg');
      _setState(UptimeKumaConnectionState.error);
      _errorController.add(msg);
      _startPolling();
      return false;
    }
  }

  Future<Set<int>> _fetchMaintenanceFromApi() async {
    if (_dio == null) return {};
    try {
      final resp = await _dio!.get('/maintenance');
      if (resp.statusCode == 200 && resp.data is List) {
        return Set<int>.from(
            (resp.data as List).map((e) => (e as num).toInt()));
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _fetchMonitors() async {
    if (_fetching || _dio == null) return;
    _fetching = true;
    try {
      final resp = await _dio!.get('/monitors');
      if (resp.statusCode != 200) return;
      final data = resp.data;
      if (data is! Map) return;
      final list = data['monitors'];
      if (list is! List) return;

      final prevMonitors = Map<int, Monitor>.from(_monitors);
      _monitors.clear();
      for (final m in list) {
        try {
          final monitor = _monitorFromApi(m as Map<String, dynamic>);
          _monitors[monitor.id] = monitor;
          if (_maintenanceIds.contains(monitor.id)) continue;
          if (monitor.status == MonitorStatus.maintenance) continue;
          final prev = prevMonitors[monitor.id];
          if (prev != null && prev.status != monitor.status) {
            _heartbeatController.add(Heartbeat(
              monitorId: monitor.id,
              status: monitor.status,
              time: DateTime.now(),
              important: true,
            ));
          } else if (_firstPoll && monitor.status == MonitorStatus.down) {
            _heartbeatController.add(Heartbeat(
              monitorId: monitor.id,
              status: MonitorStatus.down,
              time: DateTime.now(),
              important: true,
            ));
          }
        } catch (e) {
          debugPrint('[KumaService] Erro ao parsear monitor: $e');
        }
      }
      _firstPoll = false;
      if (_state == UptimeKumaConnectionState.error ||
          _state == UptimeKumaConnectionState.disconnected) {
        _setState(UptimeKumaConnectionState.authenticated);
      }
      _monitorsController.add(Map.from(_monitors));
    } on DioException catch (e) {
      debugPrint('[KumaService] DioException ao buscar monitors: ${e.message}');
      if (_state == UptimeKumaConnectionState.authenticated) {
        _setState(UptimeKumaConnectionState.disconnected);
      }
    } catch (e, st) {
      debugPrint('[KumaService] Erro inesperado: $e\n$st');
    } finally {
      _fetching = false;
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _fetchMonitors();
      await _fetchMissedEvents();
    });
  }

  Future<void> _fetchMissedEvents() async {
    if (_dio == null) return;
    try {
      final resp = await _dio!.get(
        '/events',
        queryParameters: {'since': _lastEventId},
      );
      if (resp.statusCode != 200) return;
      final events = resp.data;
      if (events is! List || events.isEmpty) return;

      final cutoff = DateTime.now().subtract(const Duration(hours: 4));

      for (final e in events) {
        if (e is! Map<String, dynamic>) continue;
        final id = (e['id'] as num?)?.toInt() ?? 0;
        if (id > _lastEventId) _lastEventId = id;

        final timeStr   = e['time']?.toString();
        final eventTime = timeStr != null
            ? DateTime.tryParse(timeStr)?.toLocal()
            : null;

        if (eventTime != null && eventTime.isBefore(cutoff)) continue;

        final status    = _statusFromString(e['status']?.toString());
        final monitorId = (e['monitorId'] as num?)?.toInt();
        if (monitorId == null) continue;
        if (status == MonitorStatus.unknown) continue;
        if (status == MonitorStatus.maintenance) continue;
        if (_maintenanceIds.contains(monitorId)) continue;

        _heartbeatController.add(Heartbeat(
          monitorId: monitorId,
          status:    status,
          time:      eventTime ?? DateTime.now(),
          important: true,
        ));
      }
    } catch (e) {
      debugPrint('[KumaService] Erro ao buscar eventos perdidos: $e');
    }
  }

  Monitor _monitorFromApi(Map<String, dynamic> m) => Monitor(
        id: (m['id'] as num).toInt(),
        name: m['name']?.toString() ?? 'Monitor',
        url: m['url']?.toString(),
        type: m['type']?.toString() ?? 'http',
        status: _statusFromString(m['status']?.toString()),
        ping: m['ping'] != null ? (m['ping'] as num).toInt() : null,
        lastChecked: m['lastCheck'] != null
            ? DateTime.tryParse(m['lastCheck'].toString())
            : null,
        active: m['active'] as bool? ?? true,
      );

  MonitorStatus _statusFromString(String? s) => switch (s) {
        'up' => MonitorStatus.up,
        'down' => MonitorStatus.down,
        'pending' => MonitorStatus.pending,
        'maintenance' => MonitorStatus.maintenance,
        _ => MonitorStatus.unknown,
      };

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || _dio == null) return;
      await _dio!.post('/register', data: {'token': token});
      debugPrint('[KumaService] FCM token registrado na bridge');
    } catch (e) {
      debugPrint('[KumaService] Erro ao registrar FCM token: $e');
    }
  }

  // Injeta IDs externos (ex: storage local) antes do primeiro poll
  void setMaintenanceIds(Set<int> ids) => _maintenanceIds = Set.from(ids);

  // Retorna o cache local (já carregado no connect) — sem chamada de rede
  Future<Set<int>> fetchMaintenanceIds() async => Set.from(_maintenanceIds);

  Future<void> addToMaintenance(int monitorId) async {
    try {
      await _dio?.post('/maintenance/$monitorId');
      _maintenanceIds.add(monitorId);
    } catch (e) {
      debugPrint('[KumaService] Erro ao adicionar manutenção: $e');
    }
  }

  Future<void> removeFromMaintenance(int monitorId) async {
    try {
      await _dio?.delete('/maintenance/$monitorId');
      _maintenanceIds.remove(monitorId);
    } catch (e) {
      debugPrint('[KumaService] Erro ao remover manutenção: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchMonitorDetail(int id) async {
    if (_dio == null) return null;
    try {
      final resp = await _dio!.get('/monitors/$id');
      if (resp.statusCode == 200) return resp.data as Map<String, dynamic>;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> testConnection(String host, int port) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final resp = await dio.get('http://$host:$port/health');
      return resp.statusCode == 200 && resp.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _monitors.clear();
    _maintenanceIds.clear();
    _setState(UptimeKumaConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _monitorsController.close();
    _heartbeatController.close();
    _errorController.close();
  }
}
