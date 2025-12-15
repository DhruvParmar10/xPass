import 'package:flutter/material.dart'
    hide
        TextField,
        AlertDialog,
        showDialog,
        Scaffold,
        AppBar,
        Card,
        Badge,
        FormField,
        CircularProgressIndicator,
        IconButton,
        Theme;
import 'package:flutter/material.dart' as material show Colors;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../services/account_service.dart';
import '../services/kdbx_service.dart';
import '../services/sync/sync_manager.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});
  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final AccountService _accountService = AccountService();
  final KdbxService _kdbxService = KdbxService();
  List<Account> accounts = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => isLoading = true);
    final loadedAccounts = await _accountService.getAllAccounts();
    setState(() {
      accounts = loadedAccounts;
      isLoading = false;
    });
  }

  Future<void> _createAccount() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;
    String errorMessage = '';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = screenWidth > 450 ? 400.0 : screenWidth * 0.85;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Create New Account'),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.person_add, size: 40),
                    const SizedBox(height: 16),
                    FormField<String>(
                      key: FormKey<String>('name_field'),
                      label: const Text('Full Name'),
                      child: TextField(
                        controller: nameController,
                        initialValue: '',
                        onChanged: (v) {
                          nameController.text = v;
                          setDialogState(() => errorMessage = '');
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormField<String>(
                      key: FormKey<String>('email_field'),
                      label: const Text('Email Address'),
                      child: TextField(
                        controller: emailController,
                        initialValue: '',
                        onChanged: (v) {
                          emailController.text = v;
                          setDialogState(() => errorMessage = '');
                        },
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormField<String>(
                      key: FormKey<String>('password_field'),
                      label: const Text('Master Password'),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: passwordController,
                              initialValue: '',
                              onChanged: (v) {
                                passwordController.text = v;
                                setDialogState(() => errorMessage = '');
                              },
                              obscureText: obscurePassword,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 18,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            variance: ButtonVariance.ghost,
                            density: ButtonDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormField<String>(
                      key: FormKey<String>('confirm_password_field'),
                      label: const Text('Confirm Master Password'),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: confirmPasswordController,
                              initialValue: '',
                              onChanged: (v) {
                                confirmPasswordController.text = v;
                                setDialogState(() => errorMessage = '');
                              },
                              obscureText: obscureConfirmPassword,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              obscureConfirmPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 18,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscureConfirmPassword =
                                    !obscureConfirmPassword;
                              });
                            },
                            variance: ButtonVariance.ghost,
                            density: ButtonDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        errorMessage,
                        style: const TextStyle(
                          color: material.Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              Flexible(
                child: SecondaryButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: PrimaryButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final email = emailController.text.trim();
                    final password = passwordController.text;
                    final confirmPassword = confirmPasswordController.text;

                    if (name.isEmpty ||
                        email.isEmpty ||
                        password.isEmpty ||
                        confirmPassword.isEmpty) {
                      setDialogState(
                        () => errorMessage = 'All fields are required',
                      );
                      return;
                    }

                    if (password != confirmPassword) {
                      setDialogState(
                        () => errorMessage = 'Passwords do not match',
                      );
                      return;
                    }

                    if (password.length < 8) {
                      setDialogState(
                        () => errorMessage =
                            'Password must be at least 8 characters',
                      );
                      return;
                    }

                    try {
                      final account = await _accountService.createAccount(
                        name: name,
                        email: email,
                      );
                      if (account == null) {
                        setDialogState(
                          () => errorMessage =
                              'Account with this email already exists',
                        );
                        return;
                      }

                      // Select the newly created account
                      await _accountService.selectAccount(account.id);

                      // Create the KDBX database with the master password
                      final dbCreated = await _kdbxService
                          .createDefaultDatabase(password);

                      if (!dbCreated) {
                        setDialogState(
                          () =>
                              errorMessage = 'Failed to create password vault',
                        );
                        return;
                      }

                      // Notify SyncManager that vault is unlocked
                      SyncManager().onVaultUnlocked();

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                        if (context.mounted) {
                          Navigator.of(
                            context,
                          ).pop(true); // Return true to navigate to vault
                        }
                      }
                    } catch (e) {
                      setDialogState(
                        () => errorMessage = 'Error creating account: $e',
                      );
                    }
                  },
                  child: const Text('Create', overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectAccount(Account account) async {
    final passwordController = TextEditingController();
    String errorMessage = '';
    bool isVerifying = false;
    bool obscurePassword = true;
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Enter Master Password'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock, size: 48),
                const SizedBox(height: 24),
                Text(
                  'Switching to: ${account.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  account.email,
                  style: TextStyle(
                    color: theme.colorScheme.mutedForeground,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                FormField<String>(
                  key: FormKey<String>('master_password_field'),
                  label: const Text('Master Password'),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: passwordController,
                          initialValue: '',
                          onChanged: (v) {
                            if (errorMessage.isNotEmpty) {
                              setDialogState(() => errorMessage = '');
                            }
                          },
                          obscureText: obscurePassword,
                          enabled: !isVerifying,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 18,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        variance: ButtonVariance.ghost,
                        density: ButtonDensity.compact,
                      ),
                    ],
                  ),
                ),
                if (errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: material.Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage,
                            style: const TextStyle(
                              color: material.Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isVerifying)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          actions: [
            SecondaryButton(
              onPressed: isVerifying
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              onPressed: isVerifying
                  ? null
                  : () async {
                      final password = passwordController.text.trim();

                      if (password.isEmpty) {
                        setDialogState(() {
                          errorMessage = 'Please enter a password';
                        });
                        return;
                      }

                      setDialogState(() {
                        isVerifying = true;
                        errorMessage = '';
                      });

                      // Verify master password
                      final isValid = await _kdbxService.verifyMasterPassword(
                        account.id,
                        password,
                      );

                      if (isValid) {
                        // Password is correct, select the account
                        final success = await _accountService.selectAccount(
                          account.id,
                        );

                        if (success) {
                          // Load the database with the verified password
                          final dbLoaded = await _kdbxService
                              .loadDefaultDatabase(password);

                          if (dbLoaded && dialogContext.mounted) {
                            // Notify SyncManager that vault is unlocked
                            SyncManager().onVaultUnlocked();

                            Navigator.of(dialogContext).pop();
                            if (mounted) {
                              Navigator.pop(context, true);
                            }
                          } else {
                            setDialogState(() {
                              isVerifying = false;
                              errorMessage = 'Failed to load vault';
                            });
                          }
                        } else {
                          setDialogState(() {
                            isVerifying = false;
                            errorMessage = 'Failed to switch account';
                          });
                        }
                      } else {
                        setDialogState(() {
                          isVerifying = false;
                          errorMessage = 'Wrong password. Try again.';
                        });
                      }
                    },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(Account account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete "${account.name}"?\n\n'
          'This will permanently delete all databases and data associated with this account.',
        ),
        actions: [
          SecondaryButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => isLoading = true);
      final success = await _accountService.deleteAccount(account.id);
      setState(() => isLoading = false);

      if (success) {
        _loadAccounts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              variance: ButtonVariance.ghost,
            ),
          ],
          title: const Text('Account Management'),
        ),
      ],
      child: isLoading
          ? Center(child: CircularProgressIndicator())
          : _buildAccountList(),
    );
  }

  Widget _buildAccountList() {
    final theme = Theme.of(context);

    if (accounts.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'No accounts yet',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Create your first account to get started',
                  style: TextStyle(color: theme.colorScheme.mutedForeground),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                PrimaryButton(
                  onPressed: _createAccount,
                  size: ButtonSize.large,
                  child: const Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Accounts',
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              PrimaryButton(
                onPressed: _createAccount,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18),
                    SizedBox(width: 8),
                    Text('New Account'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index];
              final isCurrentAccount =
                  _accountService.currentAccount?.id == account.id;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  borderColor: isCurrentAccount
                      ? theme.colorScheme.primary
                      : null,
                  borderWidth: isCurrentAccount ? 2 : 1,
                  child: InkWell(
                    onTap: () => _selectAccount(account),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: isCurrentAccount
                                ? theme.colorScheme.primary
                                : null,
                            child: Text(
                              account.name.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                fontSize: 20,
                                color: isCurrentAccount
                                    ? theme.colorScheme.primaryForeground
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        account.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isCurrentAccount)
                                      const PrimaryBadge(child: Text('ACTIVE')),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.email, size: 14),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        account.email,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Created ${_formatDate(account.createdAt)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                if (isCurrentAccount) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to open vault',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCurrentAccount)
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => _selectAccount(account),
                                  variance: ButtonVariance.primary,
                                  density: ButtonDensity.compact,
                                ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'open':
                                      _selectAccount(account);
                                      break;
                                    case 'delete':
                                      _deleteAccount(account);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'open',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isCurrentAccount
                                              ? Icons.lock_open
                                              : Icons.login,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isCurrentAccount
                                              ? 'Open Vault'
                                              : 'Switch Account',
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 18),
                                        SizedBox(width: 8),
                                        Text('Delete Account'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
