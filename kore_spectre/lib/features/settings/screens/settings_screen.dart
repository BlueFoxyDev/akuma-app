import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/background_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _hostCtrl  = TextEditingController();
  final _portCtrl  = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _obscureToken     = true;
  bool _isSaving         = false;
  bool _isTesting        = false;
  bool _bgServiceRunning = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _checkBgService();
  }

  Future<void> _checkBgService() async {
    final running = await BackgroundServiceManager.isRunning();
    if (mounted) setState(() => _bgServiceRunning = running);
  }

  Future<void> _loadConfig() async {
    final storage = ref.read(secureStorageProvider);
    final config  = await storage.getUptimeKumaConfig();
    final token   = await storage.getApiToken();
    if (mounted) {
      setState(() {
        _hostCtrl.text  = config['host'] ?? AppConstants.defaultUptimeKumaHost;
        _portCtrl.text  = config['port'] ?? '${AppConstants.defaultUptimeKumaPort}';
        _tokenCtrl.text = token ?? '';
      });
    }
  }

  Future<void> _save() async {
    if (_hostCtrl.text.isEmpty || _tokenCtrl.text.isEmpty) {
      _showSnack('Preencha host e token', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final storage = ref.read(secureStorageProvider);
      await storage.saveUptimeKumaConfig(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text) ?? AppConstants.defaultUptimeKumaPort,
      );
      await storage.saveApiToken(_tokenCtrl.text.trim());
      if (mounted) _showSnack('Configurações salvas');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_hostCtrl.text.isEmpty) {
      _showSnack('Preencha o host para testar', isError: true);
      return;
    }
    setState(() => _isTesting = true);
    try {
      final host = _hostCtrl.text.trim();
      final port = int.tryParse(_portCtrl.text) ?? AppConstants.defaultUptimeKumaPort;
      final ok   = await ref.read(kumaProvider.notifier).testConnection(host, port);
      if (mounted) {
        _showSnack(ok ? 'Servidor acessível!' : 'Sem resposta do servidor',
            isError: !ok);
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(label: 'Conexão'),
          const SizedBox(height: 12),
          _field(
            controller: _hostCtrl,
            label: 'Host / IP',
            hint: AppConstants.defaultUptimeKumaHost,
            icon: Icons.dns_rounded,
            keyboard: TextInputType.url,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _portCtrl,
            label: 'Porta',
            hint: '${AppConstants.defaultUptimeKumaPort}',
            icon: Icons.lan_rounded,
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            obscureText: _obscureToken,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              labelText: 'Token de API',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.key_rounded,
                  color: Colors.white38, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isTesting ? null : _testConnection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isTesting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor))
                      : const Text('Testar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          _SectionHeader(label: 'App'),
          const SizedBox(height: 12),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: SwitchListTile(
              secondary: Icon(
                Icons.monitor_heart_rounded,
                color: _bgServiceRunning
                    ? AppTheme.successColor
                    : Colors.white54,
              ),
              title: Text(
                _bgServiceRunning
                    ? 'Monitoramento em background ativo'
                    : 'Monitoramento em background inativo',
                style: TextStyle(
                  color: _bgServiceRunning ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                'Receba notificações mesmo com app fechado',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              value: _bgServiceRunning,
              activeThumbColor: AppTheme.primaryColor,
              activeTrackColor:
                  AppTheme.primaryColor.withValues(alpha: 0.4),
              onChanged: (v) async {
                if (v) {
                  await BackgroundServiceManager.start();
                } else {
                  await BackgroundServiceManager.stop();
                }
                await _checkBgService();
              },
            ),
          ),
          _SettingsTile(
            icon: Icons.notifications_active_rounded,
            label: 'Testar notificação',
            onTap: () =>
                ref.read(notificationServiceProvider).showTestNotification(),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.logout_rounded,
            label: 'Desconectar',
            color: AppTheme.errorColor,
            onTap: () => ref.read(authProvider.notifier).disconnect(),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white54),
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: color ?? Colors.white70, size: 22),
          title: Text(
            label,
            style: TextStyle(
                color: color ?? Colors.white, fontWeight: FontWeight.w500),
          ),
          trailing:
              const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          onTap: onTap,
        ),
      );
}
