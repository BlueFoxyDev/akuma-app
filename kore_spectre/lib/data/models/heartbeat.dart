import 'monitor.dart';

class Heartbeat {
  final int monitorId;
  final MonitorStatus status;
  final int? ping;
  final String? msg;
  final DateTime time;
  final bool important;

  const Heartbeat({
    required this.monitorId,
    required this.status,
    this.ping,
    this.msg,
    required this.time,
    this.important = false,
  });

}
