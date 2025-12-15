import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class Account {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;
  final DateTime lastUsed;

  Account({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastUsed': lastUsed.millisecondsSinceEpoch,
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      lastUsed: DateTime.fromMillisecondsSinceEpoch(json['lastUsed']),
    );
  }

  Account copyWith({
    String? id,
    String? name,
    String? email,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

class AccountService {
  static final AccountService _instance = AccountService._internal();
  factory AccountService() => _instance;
  AccountService._internal();

  Account? _currentAccount;
  static const String _accountsKey = 'user_accounts';
  static const String _currentAccountKey = 'current_account_id';
  static const String _lastSyncAccountKey = 'last_sync_account_id';

  /// Get the current active account
  Account? get currentAccount => _currentAccount;

  /// Get the base directory for all accounts
  Future<Directory> _getAccountsBaseDirectory() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final accountsDir = Directory('${documentsDir.path}/xPass/accounts');

      if (!await accountsDir.exists()) {
        await accountsDir.create(recursive: true);
        print('Created accounts base directory: ${accountsDir.path}');
      }

      return accountsDir;
    } catch (e) {
      print('Error getting accounts directory: $e');
      rethrow;
    }
  }

  /// Get the directory for a specific account
  Future<Directory> getAccountDirectory(String accountId) async {
    final baseDir = await _getAccountsBaseDirectory();
    final accountDir = Directory('${baseDir.path}/$accountId');

    if (!await accountDir.exists()) {
      await accountDir.create(recursive: true);
      print('Created account directory: ${accountDir.path}');
    }

    return accountDir;
  }

  /// Get all registered accounts
  Future<List<Account>> getAllAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJsonList = prefs.getStringList(_accountsKey) ?? [];

      return accountsJsonList.map((jsonStr) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return Account.fromJson(json);
      }).toList();
    } catch (e) {
      print('Error getting accounts: $e');
      return [];
    }
  }

  /// Save accounts list to preferences
  Future<void> _saveAccounts(List<Account> accounts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJsonList = accounts.map((account) {
        return jsonEncode(account.toJson());
      }).toList();

      await prefs.setStringList(_accountsKey, accountsJsonList);
      print('Saved ${accounts.length} accounts');
    } catch (e) {
      print('Error saving accounts: $e');
    }
  }

  /// Create a new account
  Future<Account?> createAccount({
    required String name,
    required String email,
  }) async {
    try {
      // Check if account with email already exists
      final existingAccounts = await getAllAccounts();
      if (existingAccounts.any((account) => account.email == email)) {
        print('Account with email $email already exists');
        return null;
      }

      // Generate unique ID
      final accountId = DateTime.now().millisecondsSinceEpoch.toString();
      final now = DateTime.now();

      final account = Account(
        id: accountId,
        name: name,
        email: email,
        createdAt: now,
        lastUsed: now,
      );

      // Create account directory
      await getAccountDirectory(accountId);

      // Save to accounts list
      final accounts = await getAllAccounts();
      accounts.add(account);
      await _saveAccounts(accounts);

      print('Created account: ${account.name} (${account.email})');
      return account;
    } catch (e) {
      print('Error creating account: $e');
      return null;
    }
  }

  /// Select and switch to an account
  Future<bool> selectAccount(String accountId) async {
    try {
      final accounts = await getAllAccounts();
      final account = accounts.firstWhere(
        (acc) => acc.id == accountId,
        orElse: () => throw Exception('Account not found'),
      );

      // Update last used time
      final updatedAccount = account.copyWith(lastUsed: DateTime.now());
      final updatedAccounts = accounts.map((acc) {
        return acc.id == accountId ? updatedAccount : acc;
      }).toList();

      await _saveAccounts(updatedAccounts);

      // Save current account ID and last sync account ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentAccountKey, accountId);
      await prefs.setString(_lastSyncAccountKey, accountId);

      _currentAccount = updatedAccount;
      print('Selected account: ${account.name} (${account.email})');
      return true;
    } catch (e) {
      print('Error selecting account: $e');
      return false;
    }
  }

  /// Load the last used account (or last sync account if current is not set)
  Future<bool> loadLastAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Try current account first, then fall back to last sync account
      var lastAccountId = prefs.getString(_currentAccountKey);
      if (lastAccountId == null) {
        lastAccountId = prefs.getString(_lastSyncAccountKey);
        print('Using last sync account: $lastAccountId');
      }

      if (lastAccountId == null) {
        print('No last account found');
        return false;
      }

      return await selectAccount(lastAccountId);
    } catch (e) {
      print('Error loading last account: $e');
      return false;
    }
  }

  /// Delete an account and all its data
  Future<bool> deleteAccount(String accountId) async {
    try {
      // Remove from accounts list
      final accounts = await getAllAccounts();
      final updatedAccounts = accounts
          .where((acc) => acc.id != accountId)
          .toList();
      await _saveAccounts(updatedAccounts);

      // Delete account directory and all its data
      final accountDir = await getAccountDirectory(accountId);
      if (await accountDir.exists()) {
        await accountDir.delete(recursive: true);
        print('Deleted account directory: ${accountDir.path}');
      }

      // Clear current account if it was the deleted one
      if (_currentAccount?.id == accountId) {
        _currentAccount = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_currentAccountKey);
      }

      print('Deleted account: $accountId');
      return true;
    } catch (e) {
      print('Error deleting account: $e');
      return false;
    }
  }

  /// Sign out from current account
  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentAccountKey);
      _currentAccount = null;
      print('Signed out from account');
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  /// Check if any accounts exist
  Future<bool> hasAccounts() async {
    final accounts = await getAllAccounts();
    return accounts.isNotEmpty;
  }

  /// Get the last sync account ID without selecting it
  /// This is used for background sync when the user is signed out
  Future<String?> getLastSyncAccountId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Try current account first, then fall back to last sync account
      var accountId = prefs.getString(_currentAccountKey);
      if (accountId == null) {
        accountId = prefs.getString(_lastSyncAccountKey);
        print('AccountService: Using last sync account ID: $accountId');
      } else {
        print('AccountService: Using current account ID: $accountId');
      }
      return accountId;
    } catch (e) {
      print('AccountService: Error getting last sync account ID: $e');
      return null;
    }
  }

  /// Get an account by ID without selecting it
  /// Returns null if account not found
  Future<Account?> getAccountById(String accountId) async {
    try {
      final accounts = await getAllAccounts();
      return accounts.firstWhere(
        (acc) => acc.id == accountId,
        orElse: () => throw Exception('Account not found'),
      );
    } catch (e) {
      print('AccountService: Account not found: $accountId');
      return null;
    }
  }

  /// Restore account context for background sync without full sign-in
  /// This sets _currentAccount temporarily for sync operations
  Future<bool> restoreAccountForSync() async {
    try {
      final accountId = await getLastSyncAccountId();
      if (accountId == null) {
        print('AccountService: No account ID available for sync restoration');
        return false;
      }

      final account = await getAccountById(accountId);
      if (account == null) {
        print('AccountService: Account not found for sync restoration');
        return false;
      }

      // Set current account for sync (don't update SharedPreferences)
      _currentAccount = account;
      print('AccountService: Restored account for sync: ${account.name}');
      return true;
    } catch (e) {
      print('AccountService: Error restoring account for sync: $e');
      return false;
    }
  }
}
