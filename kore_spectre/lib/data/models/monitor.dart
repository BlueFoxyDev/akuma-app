import 'package:flutter/material.dart';

enum MonitorStatus { up, down, pending, maintenance, unknown }

extension MonitorStatusExt on MonitorStatus {
  Color get color => switch (this) {
        MonitorStatus.up => const Color(0xFF2ED573),
        MonitorStatus.down => const Color(0xFFFF4757),
        MonitorStatus.pending => const Color(0xFFFFD32A),
        MonitorStatus.maintenance => const Color(0xFF5352ED),
        MonitorStatus.unknown => const Color(0xFF747D8C),
      };

  String get label => switch (this) {
        MonitorStatus.up => 'Online',
        MonitorStatus.down => 'Offline',
        MonitorStatus.pending => 'Verificando',
        MonitorStatus.maintenance => 'Manutenção',
        MonitorStatus.unknown => 'Desconhecido',
      };

  IconData get icon => switch (this) {
        MonitorStatus.up => Icons.check_circle_rounded,
        MonitorStatus.down => Icons.cancel_rounded,
        MonitorStatus.pending => Icons.pending_rounded,
        MonitorStatus.maintenance => Icons.build_circle_rounded,
        MonitorStatus.unknown => Icons.help_rounded,
      };
}

class Monitor {
  final int id;
  final String name;
  final String? url;
  final String type;
  final MonitorStatus status;
  final int? ping;
  final DateTime? lastChecked;
  final bool active;

  const Monitor({
    required this.id,
    required this.name,
    this.url,
    required this.type,
    required this.status,
    this.ping,
    this.lastChecked,
    this.active = true,
  });

  Monitor copyWith({MonitorStatus? status, int? ping, DateTime? lastChecked}) =>
      Monitor(
        id: id,
        name: name,
        url: url,
        type: type,
        status: status ?? this.status,
        ping: ping ?? this.ping,
        lastChecked: lastChecked ?? this.lastChecked,
        active: active,
      );
}
