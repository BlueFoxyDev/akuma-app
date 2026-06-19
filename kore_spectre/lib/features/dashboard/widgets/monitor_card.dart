import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../data/models/monitor.dart';
import '../../../core/theme/app_theme.dart';

class MonitorCard extends StatelessWidget {
  final Monitor monitor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool inMaintenance;

  const MonitorCard({
    super.key,
    required this.monitor,
    this.onTap,
    this.onLongPress,
    this.inMaintenance = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = monitor.status;
    final borderColor = inMaintenance ? AppTheme.warningColor : status.color;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        splashColor: borderColor.withValues(alpha: 0.06),
        highlightColor: borderColor.withValues(alpha: 0.04),
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: borderColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      _StatusBadge(status: status, inMaintenance: inMaintenance),
                      const SizedBox(width: 12),
                      Expanded(child: _MonitorInfo(monitor: monitor)),
                      if (inMaintenance)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.build_rounded,
                              color: AppTheme.warningColor, size: 14),
                        )
                      else if (status != MonitorStatus.down &&
                          monitor.ping != null)
                        _PingBadge(ping: monitor.ping!, status: status),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final MonitorStatus status;
  final bool inMaintenance;
  const _StatusBadge({required this.status, required this.inMaintenance});

  @override
  Widget build(BuildContext context) {
    final color = inMaintenance ? AppTheme.warningColor : status.color;
    final icon = inMaintenance ? Icons.build_rounded : status.icon;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _MonitorInfo extends StatelessWidget {
  final Monitor monitor;
  const _MonitorInfo({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          monitor.name,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _StatusLabel(monitor.status),
            if (monitor.lastChecked != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                timeago.format(monitor.lastChecked!, locale: 'pt_BR'),
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        if (monitor.url != null) ...[
          const SizedBox(height: 2),
          Text(
            monitor.url!,
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white30,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final MonitorStatus status;
  const _StatusLabel(this.status);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            color: status.color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );
}

class _PingBadge extends StatelessWidget {
  final int ping;
  final MonitorStatus status;
  const _PingBadge({required this.ping, required this.status});

  Color get _color {
    if (ping < 100) return AppTheme.successColor;
    if (ping < 500) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${ping}ms',
            style: TextStyle(
              color: _color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            height: 2,
            width: 28,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(1),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (1 - (ping.clamp(0, 1000) / 1000)),
              child: Container(
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      );
}
