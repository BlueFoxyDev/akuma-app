import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/monitor.dart';
import '../../../data/models/heartbeat.dart';
import '../../../data/services/uptime_kuma_service.dart'
    show UptimeKumaConnectionState;
import '../widgets/monitor_card.dart';

void _showMaintenanceSheet(
  BuildContext context,
  WidgetRef ref,
  Monitor monitor,
  bool isInMaintenance,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            monitor.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isInMaintenance
                ? 'Pausado — alertas silenciados'
                : monitor.status.label,
            style: TextStyle(
              color:
                  isInMaintenance ? AppTheme.warningColor : monitor.status.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: isInMaintenance
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Retomar monitoramento'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(kumaProvider.notifier)
                          .toggleMaintenance(monitor.id);
                    },
                  )
                : ElevatedButton.icon(
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: const Text('Pausar monitor'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warningColor,
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(kumaProvider.notifier)
                          .toggleMaintenance(monitor.id);
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            isInMaintenance
                ? 'O monitor voltará a aparecer nas abas Servidores e Offline'
                : 'Monitor pausado no Kuma — alertas silenciados',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    final storage = ref.read(secureStorageProvider);
    final config = await storage.getUptimeKumaConfig();
    final token = await storage.getApiToken();
    if (token == null || token.isEmpty) return;
    await ref.read(kumaProvider.notifier).connect(
          config['host']!,
          int.tryParse(config['port'] ?? '8765') ?? 8765,
          token,
        );
  }

  @override
  Widget build(BuildContext context) {
    final kuma = ref.watch(kumaProvider);
    final offlineCount = kuma.monitors.values
        .where((m) =>
            m.status == MonitorStatus.down &&
            !kuma.effectiveMaintenanceIds.contains(m.id))
        .length;
    final maintenanceCount = kuma.effectiveMaintenanceIds.length;

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _HomeTab(onRefresh: _autoConnect),
          const _ServersTab(),
          const _OfflineTab(),
          const _MaintenanceTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.dns_rounded),
            label: 'Servidores',
          ),
          NavigationDestination(
            icon: offlineCount > 0
                ? Badge(
                    label: Text('$offlineCount'),
                    backgroundColor: AppTheme.errorColor,
                    textColor: Colors.white,
                    child: const Icon(Icons.warning_rounded),
                  )
                : const Icon(Icons.warning_rounded),
            label: 'Offline',
          ),
          NavigationDestination(
            icon: maintenanceCount > 0
                ? Badge(
                    label: Text('$maintenanceCount'),
                    backgroundColor: AppTheme.warningColor,
                    textColor: Colors.black87,
                    child: const Icon(Icons.pause_circle_rounded),
                  )
                : const Icon(Icons.pause_circle_rounded),
            label: 'Pausa',
          ),
        ],
      ),
    );
  }
}

// ─── Home Tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _HomeTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kuma = ref.watch(kumaProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context, kuma)),
        SliverToBoxAdapter(child: _buildMetrics(kuma)),
        SliverToBoxAdapter(child: _buildSectionHeader(kuma)),
        if (kuma.connectionState == UptimeKumaConnectionState.connecting)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
            ),
          )
        else if (kuma.recentIncidents.isEmpty)
          SliverToBoxAdapter(child: _buildEmptyIncidents(kuma))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final hb = kuma.recentIncidents[i];
                  final name = kuma.monitors[hb.monitorId]?.name ??
                      'Monitor #${hb.monitorId}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _IncidentCard(heartbeat: hb, monitorName: name),
                  );
                },
                childCount: kuma.recentIncidents.length.clamp(0, 30),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, KumaConnectionStatus kuma) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 8, 0),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.monitor_heart_rounded,
                color: AppTheme.primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Akuma',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5),
                  ),
                  const SizedBox(width: 8),
                  _ConnectionDot(state: kuma.connectionState),
                ],
              ),
              const Text(
                'DATACENTER MONITOR',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white38),
            onPressed: onRefresh,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white38),
            onPressed: () => context.push('/dashboard/settings'),
            tooltip: 'Configurações',
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(KumaConnectionStatus kuma) {
    final activeDown = kuma.monitors.values
        .where((m) =>
            m.status == MonitorStatus.down &&
            !kuma.effectiveMaintenanceIds.contains(m.id))
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Row(
        children: [
          _MetricCard(
            label: 'Total',
            value: kuma.total,
            color: Colors.white60,
            icon: Icons.monitor_heart_rounded,
          ),
          const SizedBox(width: 10),
          _MetricCard(
            label: 'Online',
            value: kuma.totalUp,
            color: AppTheme.successColor,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(width: 10),
          _MetricCard(
            label: 'Offline',
            value: activeDown,
            color: activeDown > 0 ? AppTheme.errorColor : Colors.white38,
            icon: activeDown > 0
                ? Icons.cancel_rounded
                : Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(KumaConnectionStatus kuma) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Row(
        children: [
          const Text(
            'ÚLTIMOS INCIDENTES',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          if (kuma.recentIncidents.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${kuma.recentIncidents.length}',
                style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyIncidents(KumaConnectionStatus kuma) {
    final isError = kuma.connectionState == UptimeKumaConnectionState.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError
                ? Icons.wifi_off_rounded
                : Icons.check_circle_outline_rounded,
            color: isError ? AppTheme.errorColor : Colors.white24,
            size: 52,
          ),
          const SizedBox(height: 14),
          Text(
            isError ? 'Sem conexão com o servidor' : 'Nenhum incidente recente',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            isError
                ? 'Verifique as configurações de rede'
                : 'Todos os monitores estão estáveis',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Servers Tab ──────────────────────────────────────────────────────────────

class _ServersTab extends ConsumerStatefulWidget {
  const _ServersTab();

  @override
  ConsumerState<_ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends ConsumerState<_ServersTab> {
  String _search = '';
  final _searchCtrl = SearchController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Monitor> _filtered(Map<int, Monitor> monitors, Set<int> maintenanceIds) {
    var list = monitors.values
        .where((m) => !maintenanceIds.contains(m.id))
        .toList();
    if (_search.isNotEmpty) {
      list = list
          .where((m) => m.name.toLowerCase().contains(_search.toLowerCase()))
          .toList();
    }
    list.sort((a, b) {
      if (a.status == MonitorStatus.down && b.status != MonitorStatus.down) {
        return -1;
      }
      if (b.status == MonitorStatus.down && a.status != MonitorStatus.down) {
        return 1;
      }
      return a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final kuma = ref.watch(kumaProvider);
    final monitors = _filtered(kuma.monitors, kuma.effectiveMaintenanceIds);
    final activeUp = kuma.monitors.values
        .where((m) =>
            m.status == MonitorStatus.up && !kuma.effectiveMaintenanceIds.contains(m.id))
        .length;
    final activeDown = kuma.monitors.values
        .where((m) =>
            m.status == MonitorStatus.down &&
            !kuma.effectiveMaintenanceIds.contains(m.id))
        .length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Servidores',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${monitors.length}',
                        style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$activeUp online · $activeDown offline',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Segure um monitor para gerenciar manutenção',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(height: 16),
                SearchBar(
                  controller: _searchCtrl,
                  hintText: 'Buscar monitor...',
                  leading: const Icon(Icons.search_rounded,
                      color: Colors.white38, size: 20),
                  trailing: _search.isEmpty
                      ? null
                      : [
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white38, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        ],
                  onChanged: (v) => setState(() => _search = v),
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12)),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (monitors.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded,
                      color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _search.isNotEmpty
                        ? 'Nenhum resultado para "$_search"'
                        : 'Nenhum monitor encontrado',
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MonitorCard(
                    monitor: monitors[i],
                    onTap: () => context.push(
                        '/dashboard/monitor/${monitors[i].id}'),
                    onLongPress: () => _showMaintenanceSheet(
                      context,
                      ref,
                      monitors[i],
                      kuma.effectiveMaintenanceIds.contains(monitors[i].id),
                    ),
                  ),
                ),
                childCount: monitors.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Offline Tab ──────────────────────────────────────────────────────────────

class _OfflineTab extends ConsumerWidget {
  const _OfflineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kuma = ref.watch(kumaProvider);
    final offline = kuma.monitors.values
        .where((m) =>
            m.status == MonitorStatus.down &&
            !kuma.effectiveMaintenanceIds.contains(m.id))
        .toList()
      ..sort((a, b) {
        if (a.lastChecked != null && b.lastChecked != null) {
          return b.lastChecked!.compareTo(a.lastChecked!);
        }
        return a.name.compareTo(b.name);
      });

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Offline',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
                if (offline.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.errorColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      '${offline.length}',
                      style: const TextStyle(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Text(
              offline.isEmpty
                  ? 'Todos os monitores estão respondendo'
                  : '${offline.length} monitor${offline.length == 1 ? '' : 'es'} sem resposta',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        ),
        if (offline.isEmpty)
          const SliverToBoxAdapter(child: _AllOnlineState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MonitorCard(
                    monitor: offline[i],
                    onTap: () => context.push(
                        '/dashboard/monitor/${offline[i].id}'),
                    onLongPress: () => _showMaintenanceSheet(
                      context,
                      ref,
                      offline[i],
                      kuma.effectiveMaintenanceIds.contains(offline[i].id),
                    ),
                  ),
                ),
                childCount: offline.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Maintenance Tab ──────────────────────────────────────────────────────────

class _MaintenanceTab extends ConsumerWidget {
  const _MaintenanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kuma = ref.watch(kumaProvider);
    final maintenance = kuma.monitors.values
        .where((m) => kuma.effectiveMaintenanceIds.contains(m.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Pausa',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800),
                    ),
                    if (maintenance.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.warningColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.warningColor
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          '${maintenance.length}',
                          style: const TextStyle(
                              color: AppTheme.warningColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  maintenance.isEmpty
                      ? 'Nenhum monitor pausado'
                      : '${maintenance.length} monitor${maintenance.length == 1 ? '' : 'es'} pausado${maintenance.length == 1 ? '' : 's'} no Kuma',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Segure qualquer monitor para gerenciar',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (maintenance.isEmpty)
          const SliverToBoxAdapter(child: _EmptyMaintenanceState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MonitorCard(
                    monitor: maintenance[i],
                    inMaintenance: true,
                    onTap: () => context.push(
                        '/dashboard/monitor/${maintenance[i].id}'),
                    onLongPress: () => _showMaintenanceSheet(
                      context, ref, maintenance[i], true,
                    ),
                  ),
                ),
                childCount: maintenance.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyMaintenanceState extends StatelessWidget {
  const _EmptyMaintenanceState();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.warningColor.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.build_circle_rounded,
                  color: AppTheme.warningColor, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nenhum monitor pausado',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Segure um monitor em Servidores ou Offline para pausar no Kuma',
              style: TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _AllOnlineState extends StatelessWidget {
  const _AllOnlineState();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.successColor.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppTheme.successColor, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tudo online!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nenhum monitor está offline agora',
              style: TextStyle(color: Colors.white38, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 10),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
}

class _IncidentCard extends StatelessWidget {
  final Heartbeat heartbeat;
  final String monitorName;

  const _IncidentCard({
    required this.heartbeat,
    required this.monitorName,
  });

  @override
  Widget build(BuildContext context) {
    final status = heartbeat.status;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: status.color),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(status.icon, color: status.color, size: 17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            monitorName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: status.color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status.label.toUpperCase(),
                              style: TextStyle(
                                color: status.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeago.format(heartbeat.time, locale: 'pt_BR'),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final UptimeKumaConnectionState state;
  const _ConnectionDot({required this.state});

  Color get _color => switch (state) {
        UptimeKumaConnectionState.authenticated => AppTheme.successColor,
        UptimeKumaConnectionState.connecting => AppTheme.warningColor,
        UptimeKumaConnectionState.error => AppTheme.errorColor,
        _ => Colors.white24,
      };

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: _color,
          shape: BoxShape.circle,
          boxShadow: state == UptimeKumaConnectionState.authenticated
              ? [
                  BoxShadow(
                      color: _color.withValues(alpha: 0.6), blurRadius: 6)
                ]
              : null,
        ),
      );
}
