import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../state/app_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _errorMsg = null);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      HapticFeedback.lightImpact();
      await context.read<AppState>().login(
            email: _emailController.text,
            password: _passwordController.text,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitRegister() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      HapticFeedback.lightImpact();
      await context.read<AppState>().register(
            displayName: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            inviteCode: _inviteCodeController.text,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitQuickInvite() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      HapticFeedback.lightImpact();
      await context.read<AppState>().redeemInviteCode(
            inviteCode: _inviteCodeController.text,
            displayName: _nameController.text,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // If user is authenticated but awaiting admin approval or blocked, show Waiting Room
    if (state.isAuthenticated && !state.isApprovedUser) {
      return _buildWaitingRoom(context, state);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo & Brand Header
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryNeon, AppTheme.accentCyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentCyan.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.waves_rounded,
                      color: Color(0xFF0A0D14),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'VoiceStudio Cloud',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Prijavite se za pristup AI sintezi, kloniranju glasa i višeglasnom studiju',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Mode Tabs
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppTheme.textSecondary,
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      tabs: const [
                        Tab(text: 'Prijava'),
                        Tab(text: 'Registracija'),
                        Tab(text: 'Pozivnica'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Error Alert
                  if (_errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Form Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: _buildActiveTabForm(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabForm() {
    final tab = _tabController.index;

    if (tab == 0) {
      // TAB 0: Login (Email + Password)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'E-mail adresa',
              hintText: 'ime@primjer.com',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Lozinka',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppTheme.textMuted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitLogin,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login_rounded, size: 20),
            label: Text(_isLoading ? 'Prijava u tijeku...' : 'Prijavi se'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ],
      );
    }

    if (tab == 1) {
      // TAB 1: Register (Name, Email, Password, optional Invite Code)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Vaše ime ili nadimak',
              hintText: 'npr. Ivan Horvat',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'E-mail adresa',
              hintText: 'ime@primjer.com',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Odaberite lozinku',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppTheme.textMuted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _inviteCodeController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: AppTheme.accentCyan, fontSize: 14, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: 'Pristupni kod (opcionalno za odmah odobrenje)',
              hintText: 'npr. VS-8F4K2A',
              prefixIcon: Icon(Icons.vpn_key_rounded, size: 20, color: AppTheme.accentCyan),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitRegister,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.person_add_alt_1_rounded, size: 20),
            label: Text(_isLoading ? 'Kreiranje računa...' : 'Kreiraj račun'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ],
      );
    }

    // TAB 2: Quick Invite Code Login (Name + Invite Code)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Imate pristupni kod od administratora? Unesite svoje ime i kod za trenutačni ulaz bez lozinke.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Vaše ime ili nadimak',
            hintText: 'npr. Marko',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _inviteCodeController,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppTheme.accentCyan, fontSize: 15, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            labelText: 'Pristupni kod (Invite Code)',
            hintText: 'VS-XXXXXX',
            prefixIcon: Icon(Icons.vpn_key_rounded, size: 20, color: AppTheme.accentCyan),
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _submitQuickInvite,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.bolt_rounded, size: 20),
          label: Text(_isLoading ? 'Provjeravam kod...' : 'Aktiviraj pristup'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingRoom(BuildContext context, AppState state) {
    final user = state.currentUser!;
    final isBlocked = user.blocked;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isBlocked
                        ? Colors.redAccent.withValues(alpha: 0.45)
                        : AppTheme.accentCyan.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBlocked ? Icons.block_rounded : Icons.hourglass_top_rounded,
                      size: 52,
                      color: isBlocked ? Colors.redAccent : AppTheme.accentCyan,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isBlocked ? 'Pristup ograničen' : 'Čeka se odobrenje administratora',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isBlocked
                          ? 'Vaš račun (${user.email}) je trenutačno deaktiviran od strane administratora.'
                          : 'Račun "${user.displayName}" (${user.email}) je uspješno registriran u Firebase sustavu.\n\nČim administrator u Admin Panelu odobri vaš zahtjev, kliknite gumb ispod za ulazak u aplikaciju.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 22),
                    if (!isBlocked)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  await state.refreshUserAndSyncConfig();
                                  if (mounted) setState(() => _isLoading = false);
                                },
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: const Text('Provjeri status odobrenja'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => state.logout(),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Odjava / Drugi račun'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

