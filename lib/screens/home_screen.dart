import 'package:flutter/material.dart';
import '../services/account_service.dart';
import '../services/kdbx_service.dart';
import 'account_management_screen.dart';
import 'vault_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AccountService _accountService = AccountService();
  final KdbxService _kdbxService = KdbxService();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Always start fresh - close any existing database and sign out
    _kdbxService.closeDatabase();
    await _accountService.signOut();

    setState(() {});
  }

  Future<void> _navigateToAccountManagement() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AccountManagementScreen()),
    );

    if (result == true) {
      // Account was selected, navigate to vault
      _navigateToVault();
    }
  }

  Future<void> _navigateToVault() async {
    // First check if an account is selected
    if (!_kdbxService.isAccountSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account first')),
      );
      return;
    }

    // Navigate to vault screen
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VaultScreen()),
    );

    // When returning from vault, always sign out for security
    _kdbxService.closeDatabase();
    await _accountService.signOut();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),

                // App Logo/Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.security,
                    size: 60,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 30),

                // App Title
                const Text(
                  'xPass',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),

                const SizedBox(height: 12),

                // App Subtitle
                Text(
                  'Secure Password Manager',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 60),

                // Features Section
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'What We Provide',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Feature Items
                      _buildFeatureItem(
                        Icons.account_circle,
                        'Multi-Account Support',
                        'Create separate accounts for work, personal, or family use',
                      ),

                      const SizedBox(height: 16),

                      _buildFeatureItem(
                        Icons.security,
                        'Military-Grade Encryption',
                        'Your passwords are secured with KDBX encryption format',
                      ),

                      const SizedBox(height: 16),

                      _buildFeatureItem(
                        Icons.password,
                        'Password Generation',
                        'Generate strong, unique passwords for all your accounts',
                      ),

                      const SizedBox(height: 16),

                      _buildFeatureItem(
                        Icons.folder_outlined,
                        'Organized Storage',
                        'Keep your passwords organized and easily accessible',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),

                // Action Buttons
                Column(
                  children: [
                    // Account Management Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _navigateToAccountManagement,
                        icon: const Icon(Icons.arrow_forward, size: 24),
                        label: const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Footer
                Text(
                  'Your security is our priority',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.indigo, size: 24),
        ),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
