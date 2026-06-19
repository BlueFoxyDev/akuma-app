import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/monitor.dart';

class MonitorDetailScreen extends ConsumerStatefulWidget {
  final int monitorId;
  const MonitorDetailScreen({super.key, required this.monitorId});

  @override
  ConsumerState<MonitorDetailScreen> createState() =>
      _MonitorDetailScreenState();
}

class _MonitorDetailScreenState extends ConsumerState<MonitorDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await ref
        .read(kumaProvider.notifier)
        .fetchMonitorDetail(widget.monitorId);
    if (mounted) setState(() { _detail = d; _loading = false; });
  }

  Future<void> _togglePause(Monitor monitor, bool isPaused) async {
    setState(() => _toggling = true);
    await ref.read(kumaProvider.notifier).toggleMaintenance(monitor.id);
    if (mounted) setState(() => _toggling = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final kuma   = ref.watch(kumaProvider);
    final monitor = kuma.monitors[widget.monitorId];
    final isPaused = kuma.effectiveMaintenanceIds.contains(widget.monitorId);

    if (monitor == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppTheme.backgroundDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          title: const Text('Monitor'),
        ),
        body: const Center(
          child: Text('Monitor não encontrado',
              style: TextStyle(color: Colors.white60)),
        ),
      );
    }

    final beats = (_detail?['heartbeats'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final avgPing    = (_detail?['avgPing'] as num?)?.toInt();
    final uptimePct  = (_detail?['uptimePct'] as num?)?.toDouble();

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          monitor.name,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(monitor: monitor, isPaused: isPaused),
              const SizedBox(height: 12),
              _StatsRow(
                currentPing: monitor.ping,
                avgPing:     avgPing,
                uptimePct:   uptimePct,
              ),
              const SizedBox(height: 12),
              _HeartbeatSection(beats: beats, loading: _loading),
              const SizedBox(height: 12),
              _InfoCard(monitor: monitor),
              const SizedBox(height: 20),
              _PauseButton(
                isPaused:  isPaused,
                toggling:  _toggling,
                onPressed: () => _togglePause(monitor, isPaused),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status Card ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final Monitor monitor;
  final bool isPaused;
  const _StatusCard({required this.monitor, required this.isPaused});

  @override
  Widget build(BuildContext context) {
    final color = isPaused
        ? AppTheme.warningColor
        : monitor.status.color;
    final icon = isPaused
        ? Icons.pause_circle_rounded
        : monitor.status.icon;
    final label = isPaused ? 'Pausado' : monitor.status.label;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                if (monitor.lastChecked != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Verificado ${timeago.format(monitor.lastChecked!, locale: 'pt_BR')}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (monitor.ping != null && !isPaused)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${monitor.ping}ms',
                  style: TextStyle(
                    color: _pingColor(monitor.ping!),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text('ping atual',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
        ],
      ),
    );
  }

  Color _pingColor(int ping) {
    if (ping < 100) return AppTheme.successColor;
    if (ping < 500) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int? currentPing;
  final int? avgPing;
  final double? uptimePct;
  const _StatsRow(
      {required this.currentPing,
      required this.avgPing,
      required this.uptimePct});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          label: 'Ping Atual',
          value: currentPing != null ? '${currentPing}ms' : '—',
          icon: Icons.speed_rounded,
          color: currentPing != null
              ? _pingColor(currentPing!)
              : Colors.white38,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Ping Médio',
          value: avgPing != null ? '${avgPing}ms' : '—',
          icon: Icons.bar_chart_rounded,
          color: avgPing != null ? _pingColor(avgPing!) : Colors.white38,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Uptime',
          value: uptimePct != null ? '${uptimePct!.toStringAsFixed(1)}%' : '—',
          icon: Icons.check_circle_outline_rounded,
          color: uptimePct != null
              ? (uptimePct! > 95
                  ? AppTheme.successColor
                  : uptimePct! > 80
                      ? AppTheme.warningColor
                      : AppTheme.errorColor)
              : Colors.white38,
        ),
      ],
    );
  }

  Color _pingColor(int ping) {
    if (ping < 100) return AppTheme.successColor;
    if (ping < 500) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.0),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ─── Heartbeat Chart ──────────────────────────────────────────────────────────

class _HeartbeatSection extends StatelessWidget {
  final List<Map<String, dynamic>> beats;
  final bool loading;
  const _HeartbeatSection({required this.beats, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'HISTÓRICO DE HEARTBEATS',
                style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5),
              ),
              const Spacer(),
              if (beats.isNotEmpty)
                Text(
                  '${beats.length} beats',
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Center(
              child: SizedBox(
                  height: 48,
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor)))),
            )
          else if (beats.isEmpty)
            const SizedBox(
              height: 48,
              child: Center(
                child: Text('Sem histórico disponível',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            )
          else
            _HeartbeatChart(beats: beats),
          const SizedBox(height: 10),
          Row(
            children: [
              _Legend(color: AppTheme.successColor, label: 'Online'),
              const SizedBox(width: 12),
              _Legend(color: AppTheme.errorColor, label: 'Offline'),
              const SizedBox(width: 12),
              _Legend(color: AppTheme.warningColor, label: 'Verificando'),
              const SizedBox(width: 12),
              _Legend(color: Colors.white24, label: 'Desconhecido'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      );
}

class _HeartbeatChart extends StatelessWidget {
  final List<Map<String, dynamic>> beats;
  const _HeartbeatChart({required this.beats});

  Color _colorForStatus(String status) => switch (status) {
        'up' => AppTheme.successColor,
        'down' => AppTheme.errorColor,
        'pending' => AppTheme.warningColor,
        _ => const Color(0xFF3D4451),
      };

  @override
  Widget build(BuildContext context) {
    // Mais recente à esquerda
    final reversed = beats.reversed.toList();
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: reversed.length,
        itemBuilder: (_, i) {
          final status =
              reversed[i]['status'] as String? ?? 'unknown';
          final ping = reversed[i]['ping'] as num?;
          return Tooltip(
            message: ping != null ? '$status • ${ping}ms' : status,
            child: Container(
              width: 6,
              margin: const EdgeInsets.symmetric(
                  horizontal: 1, vertical: 4),
              decoration: BoxDecoration(
                color: _colorForStatus(status),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final Monitor monitor;
  const _InfoCard({required this.monitor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INFORMAÇÕES',
            style: TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Tipo', value: monitor.type.toUpperCase()),
          if (monitor.url != null && monitor.url!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Host / URL', value: monitor.url!),
          ],
          const SizedBox(height: 8),
          _InfoRow(label: 'ID', value: '#${monitor.id}'),
          if (monitor.lastChecked != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Última verificação',
              value: _formatDateTime(monitor.lastChecked!),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ),
        ],
      );
}

// ─── Pause Button ─────────────────────────────────────────────────────────────

class _PauseButton extends StatelessWidget {
  final bool isPaused;
  final bool toggling;
  final VoidCallback onPressed;
  const _PauseButton(
      {required this.isPaused,
      required this.toggling,
      required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          icon: toggling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black87))
              : Icon(isPaused
                  ? Icons.play_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded),
          label: Text(
            toggling
                ? 'Aguardando...'
                : isPaused
                    ? 'Retomar monitoramento'
                    : 'Pausar monitor no Kuma',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isPaused ? AppTheme.successColor : AppTheme.warningColor,
            foregroundColor: Colors.black87,
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: toggling ? null : onPressed,
        ),
      );
}
