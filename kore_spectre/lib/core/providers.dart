import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/secure_storage_service.dart';
import '../data/services/uptime_kuma_service.dart';
import '../data/services/notification_service.dart';
import '../data/models/monitor.dart';
import '../data/models/heartbeat.dart';

final secureStorageProvider = Provider<SecureStorageService>(
  (_) => SecureStorageService(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

final uptimeKumaServiceProvider = Provider<UptimeKumaService>((ref) {
  final service = UptimeKumaService();
  ref.onDispose(service.dispose);
  return service;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(secureStorageProvider));
});

// ─── Auth ─────────────────────────────────────────────────────────────────────

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final SecureStorageService _storage;
  final AuthService _auth;

  AuthNotifier(this._storage, this._auth) : super(const AuthState()) {
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final token = await _storage.getApiToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(isLoading: false);
      return;
    }
    final config = await _storage.getUptimeKumaConfig();
    final host = config['host']!;
    final port = int.tryParse(config['port'] ?? '') ?? 8765;
    final ok = await _auth.validateConnection(host, port, token);
    if (ok) {
      state = const AuthState(isAuthenticated: true, isLoading: false);
    } else {
      await _storage.deleteApiToken();
      state = const AuthState(isLoading: false);
    }
  }

  Future<bool> connect(String host, int port, String apiToken) async {
    state = const AuthState(isLoading: true);
    try {
      final ok = await _auth.connect(host, port, apiToken);
      if (ok) {
        state = const AuthState(isAuthenticated: true, isLoading: false);
        return true;
      }
      state = const AuthState(
        isLoading: false,
        error: 'Token inválido ou servidor inacessível',
      );
      return false;
    } on Exception {
      state = const AuthState(
        isLoading: false,
        error: 'Não foi possível conectar ao servidor',
      );
      return false;
    }
  }

  Future<void> disconnect() async {
    await _auth.disconnect();
    state = const AuthState(isLoading: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(secureStorageProvider),
    ref.read(authServiceProvider),
  );
});

// ─── Conexão com Uptime Kuma ──────────────────────────────────────────────────

class KumaConnectionStatus {
  final UptimeKumaConnectionState connectionState;
  final Map<int, Monitor> monitors;
  final List<Heartbeat> recentIncidents;
  final Set<int> maintenanceIds;
  final String? error;

  const KumaConnectionStatus({
    this.connectionState = UptimeKumaConnectionState.disconnected,
    this.monitors = const {},
    this.recentIncidents = const [],
    this.maintenanceIds = const {},
    this.error,
  });

  int get totalUp =>
      monitors.values.where((m) => m.status == MonitorStatus.up).length;
  int get totalDown =>
      monitors.values.where((m) => m.status == MonitorStatus.down).length;
  int get total => monitors.length;

  // União dos IDs explícitos com os que o próprio Kuma reporta como maintenance.
  // Garante que monitores em manutenção no Kuma sempre apareçam corretamente,
  // mesmo que o storage local esteja desatualizado.
  Set<int> get effectiveMaintenanceIds => {
        ...maintenanceIds,
        ...monitors.entries
            .where((e) => !e.value.active)
            .map((e) => e.key),
      };

  KumaConnectionStatus copyWith({
    UptimeKumaConnectionState? connectionState,
    Map<int, Monitor>? monitors,
    List<Heartbeat>? recentIncidents,
    Set<int>? maintenanceIds,
    String? error,
  }) =>
      KumaConnectionStatus(
        connectionState: connectionState ?? this.connectionState,
        monitors: monitors ?? this.monitors,
        recentIncidents: recentIncidents ?? this.recentIncidents,
        maintenanceIds: maintenanceIds ?? this.maintenanceIds,
        error: error,
      );
}

class KumaNotifier extends StateNotifier<KumaConnectionStatus> {
  final UptimeKumaService _service;
  final NotificationService _notifications;
  final SecureStorageService _storage;

  KumaNotifier(this._service, this._notifications, this._storage)
      : super(const KumaConnectionStatus()) {
    _loadLocalMaintenanceIds();

    _service.connectionState.listen((cs) {
      state = state.copyWith(connectionState: cs);
    });

    _service.monitorsStream.listen((monitors) {
      state = state.copyWith(monitors: monitors);
    });

    _service.heartbeatStream.listen((hb) {
      if (state.effectiveMaintenanceIds.contains(hb.monitorId)) return;
      if (hb.status == MonitorStatus.maintenance) return;
      final monitor = state.monitors[hb.monitorId];
      if (monitor != null) {
        _notifications.showStatusChange(monitor.name, hb.status, at: hb.time);
      }
      final updated = [hb, ...state.recentIncidents];
      state = state.copyWith(
        recentIncidents:
            updated.length > 50 ? updated.sublist(0, 50) : updated,
      );
    });

    _service.errorStream.listen((err) {
      state = state.copyWith(error: err);
    });
  }

  // Carrega do storage LOCAL imediatamente — antes de qualquer chamada de rede.
  // Garante que o filtro de manutenção funcione mesmo se a API demorar ou falhar.
  Future<void> _loadLocalMaintenanceIds() async {
    final ids = await _storage.getMaintenanceIds();
    if (ids.isEmpty) return;
    _service.setMaintenanceIds(ids);
    state = state.copyWith(maintenanceIds: ids);
  }

  Future<bool> connect(String host, int port, String apiToken) async {
    final ok =
        await _service.connect(host: host, port: port, apiToken: apiToken);
    if (ok) {
      // Sincroniza com o servidor e salva localmente
      final mIds = await _service.fetchMaintenanceIds();
      await _storage.saveMaintenanceIds(mIds);
      state = state.copyWith(maintenanceIds: mIds);
    }
    return ok;
  }

  Future<void> toggleMaintenance(int monitorId) async {
    final Set<int> updated;
    if (state.maintenanceIds.contains(monitorId)) {
      await _service.removeFromMaintenance(monitorId);
      updated = Set<int>.from(state.maintenanceIds)..remove(monitorId);
    } else {
      await _service.addToMaintenance(monitorId);
      updated = {...state.maintenanceIds, monitorId};
    }
    // Persiste localmente para sobreviver ao restart do app
    await _storage.saveMaintenanceIds(updated);
    state = state.copyWith(maintenanceIds: updated);
  }

  Future<Map<String, dynamic>?> fetchMonitorDetail(int id) =>
      _service.fetchMonitorDetail(id);

  Future<bool> testConnection(String host, int port) =>
      _service.testConnection(host, port);

  void disconnect() => _service.disconnect();
}

final kumaProvider =
    StateNotifierProvider<KumaNotifier, KumaConnectionStatus>((ref) {
  return KumaNotifier(
    ref.read(uptimeKumaServiceProvider),
    ref.read(notificationServiceProvider),
    ref.read(secureStorageProvider),
  );
});
