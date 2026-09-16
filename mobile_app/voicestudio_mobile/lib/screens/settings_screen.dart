import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../state/app_state.dart';

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
  bool _showTutorial = false;
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
    await state.updateConnectionSettings(
      newLocalUrl: _localController.text.trim(),
      newRemoteUrl: _remoteController.text.trim(),
      newConnectionMode: _connectionMode,
      newCfClientId: _cfIdController.text.trim(),
      newCfClientSecret: _cfSecretController.text.trim(),
      newStreamingEnabled: _streamingEnabled,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.isConnected
                ? 'Postavke spremljene! Aktivna veza: ${state.isUsingLocalUrl ? "Lokalno (Wi-Fi/USB)" : "Cloudflare Tunel"}'
                : 'Spremljeno. Poslužitelj nije dostupan (${state.errorMessage ?? "Provjerite adrese"})',
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
    // First save in-flight form edits
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mreža i Povezivanje'),
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
          // 1. Connection Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: state.isConnected
                  ? AppTheme.accentGreen.withValues(alpha: 0.1)
                  : AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: state.isConnected
                    ? AppTheme.accentGreen.withValues(alpha: 0.3)
                    : AppTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  state.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: state.isConnected ? AppTheme.accentGreen : AppTheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            state.isConnected ? 'Povezano' : 'Nije povezano',
                            style: TextStyle(
                              color: state.isConnected ? AppTheme.accentGreen : AppTheme.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (state.isConnected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: state.isUsingLocalUrl
                                    ? AppTheme.accentCyan.withValues(alpha: 0.2)
                                    : AppTheme.accentAmber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                state.isUsingLocalUrl ? 'LOKALNO' : 'CLOUDFLARE',
                                style: TextStyle(
                                  color: state.isUsingLocalUrl ? AppTheme.accentCyan : AppTheme.accentAmber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        state.isConnected
                            ? 'Aktivna adresa: ${state.activeBaseUrl}'
                            : (state.errorMessage ?? 'Provjerite je li VoiceStudio pokrenut'),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Connection Mode (P1 Auto Network Fallback)
          const Text(
            'NAČIN POVEZIVANJA (AUTO-FALLBACK)',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 6),
          Text(
            _connectionMode == 'auto'
                ? '⚡ Automatski provjerava brzu kućnu mrežu/USB, a ako ste izvan kuće automatski prebacuje na Cloudflare tunel.'
                : _connectionMode == 'local'
                    ? '🏠 Koristi samo lokalnu mrežu (Wi-Fi ili USB kabel).'
                    : '☁️ Koristi isključivo Cloudflare Zero Trust tunel.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 24),

          // 3. Local URL configuration
          const Text(
            '1. LOKALNA ADRESA (WI-FI / USB)',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.usb_rounded, size: 15, color: AppTheme.accentCyan),
                label: const Text('USB (127.0.0.1:3900)', style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary)),
                backgroundColor: AppTheme.surfaceElevated,
                side: const BorderSide(color: AppTheme.border),
                onPressed: () {
                  setState(() => _localController.text = 'http://127.0.0.1:3900');
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.wifi_rounded, size: 15, color: AppTheme.accentGreen),
                label: const Text('Wi-Fi (192.168.50.175)', style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary)),
                backgroundColor: AppTheme.surfaceElevated,
                side: const BorderSide(color: AppTheme.border),
                onPressed: () {
                  setState(() => _localController.text = 'http://192.168.50.175:3900');
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _localController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
            decoration: const InputDecoration(
              labelText: 'Lokalna adresa',
              hintText: 'http://192.168.50.175:3900 ili http://127.0.0.1:3900',
              prefixIcon: Icon(Icons.home_work_outlined, size: 20, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 24),

          // 4. Remote URL configuration
          const Text(
            '2. UDALJENA ADRESA (CLOUDFLARE TUNEL)',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _remoteController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
            decoration: const InputDecoration(
              labelText: 'Cloudflare Tunel URL',
              hintText: 'https://studiovoice.trustshome.org',
              prefixIcon: Icon(Icons.language_rounded, size: 20, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 24),

          // 5. Cloudflare Service Token (P1)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text(
                'CLOUDFLARE ZERO TRUST TOKEN',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ZA UDALJENI RAD',
                  style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Service Token omogućava mobilnoj aplikaciji pristup iza Cloudflare Accessa bez traženja PIN koda preko e-maila.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),

          // Tutorial Expandable Card
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _showTutorial = !_showTutorial),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.help_outline_rounded, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Kako kreirati Service Token u Cloudflareu?',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showTutorial ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showTutorial) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TutorialStep(step: '1', text: 'Otvorite Cloudflare Zero Trust: dash.teams.cloudflare.com'),
                  _TutorialStep(step: '2', text: 'U lijevom izborniku: Access ➔ Service Auth ➔ Service Tokens'),
                  _TutorialStep(step: '3', text: 'Kliknite "Create Service Token" i unesite naziv "VoiceStudio Mobile"'),
                  _TutorialStep(step: '4', text: 'Kopirajte Client ID i Client Secret (Secret se vidi samo jednom!)'),
                  _TutorialStep(step: '5', text: 'Idite na Access ➔ Applications ➔ odaberite VoiceStudio aplikaciju ➔ Policies'),
                  _TutorialStep(step: '6', text: 'Dodajte pravilo: Action: "Service Auth", Include: "Service Token" ➔ "VoiceStudio Mobile"'),
                  _TutorialStep(step: '7', text: 'Zalijepite tokene u polja ispod i spremite postavke!'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          TextField(
            controller: _cfIdController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
            decoration: const InputDecoration(
              labelText: 'CF-Access-Client-Id',
              hintText: 'xxxxxxxx.access',
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
          const SizedBox(height: 28),

          // 6. Streaming Audio Toggle (P3)
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
                        'Zvuk počinje svirati odmah (za ~1–2 sek.) dok se ostatak teksta još sintetizira na računalu.',
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
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 7. Test Endpoints & Save CTAs
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
            label: const Text('Spremi promjene'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
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
                ? 'Dostupno (${res['localPing']} ms)'
                : (res['localError'] ?? 'Nije dostupno'),
          ),
          const Divider(color: AppTheme.border, height: 16),
          _buildDiagRow(
            icon: Icons.cloud_rounded,
            label: 'Cloudflare Tunel (Udaljeno)',
            isOk: remoteOk,
            detail: remoteOk
                ? 'Dostupno (${res['remotePing']} ms)'
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
}

class _TutorialStep extends StatelessWidget {
  final String step;
  final String text;

  const _TutorialStep({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              step,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
