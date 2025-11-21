import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/src/theme/theme_extension.dart';
import '../services/account_service.dart';
import '../services/kdbx_service.dart';
import 'account_management_screen.dart';
import 'vault_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final ThemeMode currentThemeMode;
  
  const HomeScreen({
    super.key,
    required this.onThemeToggle,
    required this.currentThemeMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AccountService _accountService = AccountService();
  final KdbxService _kdbxService = KdbxService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _kdbxService.closeDatabase();
    await _accountService.signOut();
    if (mounted) setState(() {});
  }

  Future<void> _navigateToAccountManagement() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AccountManagementScreen()),
    );

    if (result == true) {
      _navigateToVault();
    }
  }

  Future<void> _navigateToVault() async {
    if (!_kdbxService.isAccountSelected) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VaultScreen()),
    );

    _kdbxService.closeDatabase();
    await _accountService.signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = widget.currentThemeMode == ThemeMode.dark;

    return Scaffold(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 48.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                      onPressed: widget.onThemeToggle,
                      variance: ButtonVariance.ghost,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: 1,
                  height: 80,
                  color: theme.colorScheme.foreground,
                ),
                const SizedBox(height: 40),
                Text(
                  'xPass',
                  style: theme.typography.h1.copyWith(
                    fontWeight: FontWeight.w100,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Secure Password Manager',
                  style: theme.typography.base.copyWith(
                    fontWeight: FontWeight.w200,
                    letterSpacing: 1,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: 120),
                _buildFeatureItem('Multi-Account Support'),
                const SizedBox(height: 24),
                _buildFeatureItem('Military-Grade Encryption'),
                const SizedBox(height: 24),
                _buildFeatureItem('Password Generation'),
                const SizedBox(height: 24),
                _buildFeatureItem('Organized Storage'),
                const SizedBox(height: 120),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    onPressed: _navigateToAccountManagement,
                    size: ButtonSize.large,
                    child: const Text('GET STARTED'),
                  ),
                ),
                const SizedBox(height: 48),
                Center(
                  child: Container(
                    height: 1,
                    width: 60,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Your security is our priority',
                    style: theme.typography.small.copyWith(
                      fontWeight: FontWeight.w200,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String title) {
    final theme = context.theme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: theme.colorScheme.foreground,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 20),
        Text(
          title,
          style: theme.typography.p.copyWith(
            fontWeight: FontWeight.w200,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
