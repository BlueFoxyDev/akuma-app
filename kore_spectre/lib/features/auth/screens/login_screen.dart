import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _hostCtrl  = TextEditingController(text: AppConstants.defaultUptimeKumaHost);
  final _portCtrl  = TextEditingController(text: '${AppConstants.defaultUptimeKumaPort}');
  final _tokenCtrl = TextEditingController();
  bool _obscureToken = true;
  bool _submitting   = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final storage = ref.read(secureStorageProvider);
    final config  = await storage.getUptimeKumaConfig();
    setState(() {
      _hostCtrl.text = config['host'] ?? AppConstants.defaultUptimeKumaHost;
      _portCtrl.text = config['port'] ?? '${AppConstants.defaultUptimeKumaPort}';
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final host  = _hostCtrl.text.trim();
    final port  = int.tryParse(_portCtrl.text.trim()) ?? AppConstants.defaultUptimeKumaPort;
    final token = _tokenCtrl.text.trim();
    if (host.isEmpty || token.isEmpty) return;

    setState(() => _submitting = true);
    await ref.read(authProvider.notifier).connect(host, port, token);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading && !_submitting) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLogo(),
                const SizedBox(height: 48),
                if (authState.error != null) ...[
                  _ErrorBanner(message: authState.error!),
                  const SizedBox(height: 20),
                ],
                _InputField(
                  controller: _hostCtrl,
                  label: 'Host / IP do servidor',
                  icon: Icons.dns_rounded,
                  keyboard: TextInputType.url,
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _InputField(
                  controller: _portCtrl,
                  label: 'Porta',
                  icon: Icons.lan_rounded,
                  keyboard: TextInputType.number,
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _TokenField(
                  controller: _tokenCtrl,
                  obscure: _obscureToken,
                  onToggle: () =>
                      setState(() => _obscureToken = !_obscureToken),
                  onSubmit: _submit,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Conectar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() => Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.monitor_heart_rounded,
              color: AppTheme.primaryColor,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Akuma',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const Text(
            'Datacenter Monitor',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white38,
              letterSpacing: 2,
            ),
          ),
        ],
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.errorColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  final TextInputAction action;

  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.keyboard,
    required this.action,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboard,
        textInputAction: action,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        ),
      );
}

class _TokenField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final VoidCallback onSubmit;

  const _TokenField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmit(),
        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: 'Token de API',
          labelStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.key_rounded,
              color: Colors.white38, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: onToggle,
          ),
        ),
      );
}
