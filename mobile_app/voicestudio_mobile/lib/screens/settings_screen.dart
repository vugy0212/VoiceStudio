import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import 'admin_panel_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _localController;
  late final TextEditingController _remoteController;
  late final TextEditingController _cfIdController;
  late final TextEditingController _cfSecretController;
  late String _connectionMode;
  late bool _streamingEnabled;
  bool _obscureSecret = true;
  bool _syncToFirebase = true;
  Map<String, dynamic>? _testResults;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _localController = TextEditingController(text: state.localServerUrl);
    _remoteController = TextEditingController(text: state.remoteServerUrl);
    _cfIdController = TextEditingController(text: state.cfClientId);
    _cfSecretController = TextEditingController(text: state.cfClientSecret);
    _connectionMode = state.connectionMode;
    _streamingEnabled = state.streamingEnabled;
  }

  @override
  void dispose() {
    _localController.dispose();
    _remoteController.dispose();
    _cfIdController.dispose();
    _cfSecretController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final state = context.read<AppState>();
    if (!state.isAdmin) {
      await state.setStreamingEnabled(_streamingEnabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Postavke reprodukcije spremljene!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
      return;
    }

    await state.updateConnectionSettings(
      newLocalUrl: _localController.text.trim(),
      newRemoteUrl: _remoteController.text.trim(),
      newConnectionMode: _connectionMode,
      newCfClientId: _cfIdController.text.trim(),
      newCfClientSecret: _cfSecretController.text.trim(),
      newStreamingEnabled: _streamingEnabled,
      syncToFirebaseHub: _syncToFirebase,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.isConnected
                ? (_syncToFirebase
                    ? 'Spremljeno lokalno i sinkronizirano u Firebase za sve korisnike!'
                    : 'Postavke spremljene!')
                : 'Spremljeno. Poslužitelj trenutno nije dostupan.',
          ),
          backgroundColor: state.isConnected ? AppTheme.accentGreen : AppTheme.primary,
        ),
      );
    }
  }

  Future<void> _runDetailedTest() async {
    setState(() {
      _isTesting = true;
      _testResults = null;
    });

    final state = context.read<AppState>();
    await state.updateConnectionSettings(
      newLocalUrl: _localController.text.trim(),
      newRemoteUrl: _remoteController.text.trim(),
      newConnectionMode: _connectionMode,
      newCfClientId: _cfIdController.text.trim(),
      newCfClientSecret: _cfSecretController.text.trim(),
      newStreamingEnabled: _streamingEnabled,
    );

    final results = await state.testDetailedEndpoints();

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResults = results;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;
    final isAdmin = state.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Postavke & Admin Sustav' : 'Moj Profil i Postavke'),
        actions: [
          IconButton(
            icon: state.isCheckingConnection || _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                  )
                : const Icon(Icons.check_rounded, color: AppTheme.accentCyan),
            tooltip: 'Spremi postavke',
            onPressed: (state.isCheckingConnection || _isTesting) ? null : _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. User Account & Quota Card (Visible to all users)
          if (user != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAdmin
                      ? AppTheme.primaryNeon.withValues(alpha: 0.45)
                      : AppTheme.accentCyan.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 21,
                        backgroundColor: (isAdmin ? AppTheme.primaryNeon : AppTheme.accentCyan)
                            .withValues(alpha: 0.15),
                        child: Icon(
                          isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                          color: isAdmin ? AppTheme.primaryNeon : AppTheme.accentCyan,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isAdmin
                                            ? AppTheme.primaryNeon
                                            : (state.isPremium
                                                ? Colors.amberAccent
                                                : AppTheme.accentGreen))
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    isAdmin
                                        ? 'ADMIN'
                                        : (state.isPremium ? '⭐ PREMIUM (SVI GLASOVI)' : 'DEMO (4 GLASA)'),
                                    style: TextStyle(
                                      color: isAdmin
                                          ? AppTheme.primaryNeon
                                          : (state.isPremium
                                              ? Colors.amberAccent
                                              : AppTheme.accentGreen),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                        tooltip: 'Odjava iz računa',
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          await state.logout();
                          if (mounted) navigator.popUntil((route) => route.isFirst);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Daily Quota Progress Bar
                  if (!isAdmin) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dnevna kvota generiranja:',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        Text(
                          '${user.effectiveUsedToday} / ${user.dailyQuota} iskorišteno (preostalo: ${user.remainingQuota})',
                          style: const TextStyle(
                            color: AppTheme.accentCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: user.dailyQuota > 0
                            ? (user.effectiveUsedToday / user.dailyQuota).clamp(0.0, 1.0)
                            : 0.0,
                        minHeight: 7,
                        backgroundColor: AppTheme.surfaceHighlight,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          user.remainingQuota <= 3 ? Colors.amberAccent : AppTheme.accentCyan,
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                          );
                        },
                        icon: const Icon(Icons.people_alt_rounded, size: 19),
                        label: const Text('Otvori Admin Panel (Korisnici, Kvote i Pozivnice)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryNeon,
                          foregroundColor: const Color(0xFF0A0D14),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 18),

          // 2. Server Connection Status Card (Sanitized for regular users; full info for Admin)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: state.isConnected
                  ? (state.isBackendSleeping
                      ? AppTheme.accentCyan.withValues(alpha: 0.1)
                      : AppTheme.accentGreen.withValues(alpha: 0.1))
                  : AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: state.isConnected
                    ? (state.isBackendSleeping
                        ? AppTheme.accentCyan.withValues(alpha: 0.35)
                        : AppTheme.accentGreen.withValues(alpha: 0.3))
                    : AppTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      state.isConnected
                          ? (state.isBackendSleeping ? Icons.bedtime_rounded : Icons.cloud_done_rounded)
                          : Icons.cloud_off_rounded,
                      color: state.isConnected
                          ? (state.isBackendSleeping ? AppTheme.accentCyan : AppTheme.accentGreen)
                          : AppTheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.isConnected
                                ? (state.isBackendSleeping
                                    ? 'VoiceStudio Cloud spreman (Auto-Wake)'
                                    : 'VoiceStudio Cloud aktivan')
                                : 'Poslužitelj trenutno nije dostupan',
                            style: TextStyle(
                              color: state.isConnected
                                  ? (state.isBackendSleeping ? AppTheme.accentCyan : AppTheme.accentGreen)
                                  : AppTheme.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isAdmin && state.isConnected
                                ? 'Aktivna ruta: ${state.activeBaseUrl} • Red čekanja: ${state.queueLength}'
                                : (state.isConnected
                                    ? (state.queueLength > 0
                                        ? 'Trenutačno u redu čekanja na poslužitelju: ${state.queueLength}'
                                        : 'Svi servisi sinteze i kloniranja su dostupni')
                                    : 'Provjerite internetsku vezu ili pokušajte ponovno'),
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan, size: 20),
                      tooltip: 'Osvježi vezu',
                      onPressed: state.isCheckingConnection
                          ? null
                          : () => state.refreshUserAndSyncConfig(),
                    ),
                  ],
                ),
                // GPU Wake/Sleep button ONLY visible to Admin!
                if (isAdmin && state.isConnected && state.backendStatus != 'DIRECT') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: state.isCheckingConnection
                          ? null
                          : () async {
                              if (state.isBackendSleeping) {
                                await state.wakeEngine();
                              } else {
                                await state.sleepEngine();
                              }
                            },
                      icon: Icon(
                        state.isBackendSleeping ? Icons.power_settings_new_rounded : Icons.bedtime_outlined,
                        size: 17,
                      ),
                      label: Text(
                        state.isBackendSleeping
                            ? 'Probudi GPU unaprijed (Admin Wake)'
                            : 'Uspavaj GPU odmah (Admin Sleep)',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: state.isBackendSleeping ? AppTheme.accentGreen : AppTheme.accentCyan,
                        side: BorderSide(
                          color: (state.isBackendSleeping ? AppTheme.accentGreen : AppTheme.accentCyan)
                              .withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Streaming Audio Toggle (Visible to all users)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _streamingEnabled
                    ? AppTheme.accentCyan.withValues(alpha: 0.4)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: AppTheme.accentCyan, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Brzo strujanje (Streaming)',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Zvuk počinje svirati odmah (za ~1–2 sek.) dok se ostatak teksta još sintetizira.',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _streamingEnabled,
                  activeThumbColor: AppTheme.accentCyan,
                  onChanged: (val) {
                    setState(() => _streamingEnabled = val);
                    if (!isAdmin) {
                      state.setStreamingEnabled(val);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // =====================================================================
          // 3b. USER GUIDE (UPUTE ZA KORIŠTENJE) & ABOUT (O APLIKACIJI)
          // =====================================================================
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: AppTheme.accentCyan, size: 22),
                  ),
                  title: const Text(
                    'Upute za korištenje (Vodič)',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Kako klonirati glas, koristiti arhetipove, karaoke praćenje i dijaloge',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textMuted),
                  onTap: () => _showUserGuideSheet(context),
                ),
                const Divider(height: 1, color: AppTheme.border),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNeon.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.info_outline_rounded,
                        color: AppTheme.primaryNeon, size: 22),
                  ),
                  title: const Text(
                    'O aplikaciji (About)',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'VoiceStudio Mobile v1.2.0 • AI arhitektura, modeli i privatnost',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textMuted),
                  onTap: () => _showAboutAppDialog(context),
                ),
              ],
            ),
          ),

          // =====================================================================
          // 4. ADMIN-ONLY INFRASTRUCTURE & CLOUDFLARE TOKEN SETTINGS
          // (Completely hidden from standard users!)
          // =====================================================================
          if (isAdmin) ...[
            const SizedBox(height: 28),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.security_rounded, color: AppTheme.primaryNeon, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'INFRASTRUKTURA I TOKENI (SAMO ZA ADMINA)',
                  style: TextStyle(
                    color: AppTheme.primaryNeon,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Ovi podaci su skriveni od standardnih korisnika i sinkroniziraju se kroz zaštićeni Firebase Hub.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
            ),
            const SizedBox(height: 16),

            // Connection Mode
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  _buildModeTab('auto', '⚡ Automatski', 'Lokalno pa CF'),
                  _buildModeTab('local', '🏠 Lokalno', 'Samo Wi-Fi/USB'),
                  _buildModeTab('remote', '☁️ Cloudflare', 'Samo udaljeno'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _localController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'Lokalna adresa (Wi-Fi / USB)',
                hintText: 'http://192.168.50.175:3900',
                prefixIcon: Icon(Icons.home_work_outlined, size: 20, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remoteController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'Cloudflare Tunel URL',
                hintText: 'https://studiovoice.trustshome.org',
                prefixIcon: Icon(Icons.language_rounded, size: 20, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cfIdController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'CF-Access-Client-Id',
                prefixIcon: Icon(Icons.key_rounded, size: 20, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cfSecretController,
              obscureText: _obscureSecret,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              decoration: InputDecoration(
                labelText: 'CF-Access-Client-Secret',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppTheme.textMuted),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 20,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _syncToFirebase,
              activeColor: AppTheme.accentCyan,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Sinkroniziraj ove mrežne postavke u Firebase za sve odobrene korisnike',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              onChanged: (val) => setState(() => _syncToFirebase = val ?? true),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isTesting ? null : _runDetailedTest,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                    )
                  : const Icon(Icons.network_check_rounded, size: 18),
              label: Text(_isTesting ? 'Testiram obje veze...' : 'Testiraj obje veze (Lokalno & Cloudflare)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppTheme.accentCyan),
              ),
            ),
            if (_testResults != null) ...[
              const SizedBox(height: 14),
              _buildTestResultsCard(_testResults!),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: state.isCheckingConnection || _isTesting ? null : _saveSettings,
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('Spremi i sinkroniziraj postavke'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildModeTab(String modeKey, String title, String subtitle) {
    final isSelected = _connectionMode == modeKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _connectionMode = modeKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white70 : AppTheme.textMuted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestResultsCard(Map<String, dynamic> res) {
    final localOk = res['localOk'] == true;
    final remoteOk = res['remoteOk'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIJAGNOSTIKA VEZE',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          _buildDiagRow(
            icon: Icons.home_rounded,
            label: 'Lokalna veza (Wi-Fi / USB)',
            isOk: localOk,
            detail: localOk
                ? 'Dostupno (${res['localPing']} ms • ${res['localState'] ?? "OK"})'
                : (res['localError'] ?? 'Nije dostupno'),
          ),
          const Divider(color: AppTheme.border, height: 16),
          _buildDiagRow(
            icon: Icons.cloud_rounded,
            label: 'Cloudflare Tunel (Udaljeno)',
            isOk: remoteOk,
            detail: remoteOk
                ? 'Dostupno (${res['remotePing']} ms • ${res['remoteState'] ?? "OK"})'
                : (res['remoteError'] ?? 'Nije dostupno'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagRow({
    required IconData icon,
    required String label,
    required bool isOk,
    required String detail,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: isOk ? AppTheme.accentGreen : AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Text(
                detail,
                style: TextStyle(
                  color: isOk ? AppTheme.accentGreen : AppTheme.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        Icon(
          isOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 18,
          color: isOk ? AppTheme.accentGreen : AppTheme.primary,
        ),
      ],
    );
  }

  void _showUserGuideSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppTheme.accentCyan, width: 1.5)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, color: AppTheme.accentCyan, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Upute za korištenje VoiceStudio Mobile',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    _buildGuideSection(
                      icon: Icons.record_voice_over_rounded,
                      color: AppTheme.accentCyan,
                      title: '1. Odabir glasa i Studio Arhetipovi (🎭)',
                      body:
                          '• U gornjoj traci na početnom zaslonu nalaze se klonirani glasovi i 16 ugrađenih Studio Arhetipova (Dokumentarac, TV Voditelj, Filmski Trailer, Stari Pripovjedač, Mirni Šapat...).\n'
                          '• Pomoću filtara iznad trake ("Svi u traci", "Klonirani", "🎭 Arhetipovi") možete brzo filtrirati prikaz.\n'
                          '• Dodirom na bilo koji zlatni Arhetip on se automatski aktivira i spreman je za čitanje teksta na hrvatskom, srpskom, bosanskom ili engleskom jeziku.',
                    ),
                    _buildGuideSection(
                      icon: Icons.lyrics_rounded,
                      color: AppTheme.accentGreen,
                      title: '2. Sinteza govora i Karaoke praćenje riječi',
                      body:
                          '• Unesite ili zalijepite tekst u središnji okvir, odaberite jezik (npr. Croatian ili Auto) i pritisnite "Sintetiziraj".\n'
                          '• Čim krene reprodukcija, tekst u okviru automatski prelazi u Karaoke način rada: izgovorena riječ svijetli u cijan boji, a tekst se sam podiže kako govor odmiče.\n'
                          '• Dodirnite bilo koju riječ u tekstu da odmah premotate zvuk na to mjesto, ili kliknite gumb "Uredi" u zaglavlju okvira za izmjenu teksta.',
                    ),
                    _buildGuideSection(
                      icon: Icons.graphic_eq_rounded,
                      color: AppTheme.primaryNeon,
                      title: '3. Kloniranje glasa i AI Denoise čišćenje šuma',
                      body:
                          '• Kliknite "Kloniraj novi" i snimite 10–20 sekundi čistog govora mikrofonom ili odaberite audio datoteku (WAV, MP3, M4A).\n'
                          '• Uključite opciju "AI Denoise (Ukloni šum)" prije kloniranja kako bi sustav automatski očistio pozadinski šum i jeku za najvišu kvalitetu klona.',
                    ),
                    _buildGuideSection(
                      icon: Icons.auto_awesome_motion_rounded,
                      color: Colors.amber,
                      title: '4. Napredni Studio Alati',
                      body:
                          '• Speech-to-Speech: Snimite vlastiti glas s željenom intonacijom i emocijom, a sustav će vaš govor pretvoriti u odabrani ciljani glas.\n'
                          '• Višeglasni dijalog: Sastavite scenarij s više različitih govornika i spojite cijeli razgovor u jednu audio datoteku.\n'
                          '• Dizajn glasa: Kreirajte novi sintetički glas podešavanjem dobi, spola i dubine glasa.\n'
                          '• Pametni Čitač (Čitač): Idealan za duge članke i knjige — čita odlomak po odlomak uz unaprijed spremanje idućeg odlomka bez pauze.',
                    ),
                    _buildGuideSection(
                      icon: Icons.library_music_rounded,
                      color: AppTheme.accentCyan,
                      title: '5. Offline Biblioteka i Korisničke razine',
                      body:
                          '• Svaki generirani govor možete spremiti u "Biblioteku" (ikona nota u vrhu) za trajno slušanje bez interneta ili dijeljenje (WhatsApp, Viber, Telegram).\n'
                          '• Korisnički računi mogu imati Demo pristup, grupni pristup određenim glasovima ili ⭐ Premium pristup svim glasovnim modelima.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuideSection({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutAppDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryNeon, AppTheme.accentCyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.waves_rounded, color: Color(0xFF0A0D14), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VoiceStudio Mobile',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Verzija 1.2.0 • Multi-User Studio Edition',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VoiceStudio Mobile je napredna platforma za zero-shot kloniranje glasa, sintezu govora u stvarnom vremenu, pretvorbu govora (Speech-to-Speech) i kreiranje višeglasnih dijaloga.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45),
                ),
                SizedBox(height: 14),
                Text(
                  'TEHNOLOGIJE I POGON:',
                  style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '• AI Sinteza & Kloniranje: OmniVoice Zero-Shot Neural TTS\n'
                  '• Prepoznavanje govora (STS): Faster-Whisper STT\n'
                  '• Obrada zvuka: AI Spectral / DeepFilter Denoise\n'
                  '• Sigurnost i računi: Firebase Cloud Hub + Cloudflare Zero Trust\n'
                  '• GPU Orkestracija: On-Demand Lazy Gateway s FIFO redom čekanja',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, height: 1.5),
                ),
                SizedBox(height: 14),
                Text(
                  'PRIVATNOST I SIGURNOST:',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Sva sinteza zvuka izvršava se na zaštićenom privatnom GPU poslužitelju bez dijeljenja vaših glasovnih uzoraka s vanjskim komercijalnim servisima.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Zatvori'),
            ),
          ],
        );
      },
    );
  }
}
