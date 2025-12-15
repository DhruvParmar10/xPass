import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for securely storing sensitive data like master passwords
/// Uses platform-native secure storage (Keychain on iOS/macOS, Keystore on Android)
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  // Configure secure storage with platform-specific options
  // For macOS, use useDataProtectionKeyChain: false to avoid keychain-access-groups entitlement
  // which requires code signing
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  // Key prefixes for different types of stored data
  static const String _masterPasswordPrefix = 'master_password_';
  static const String _syncEnabledKey = 'background_sync_enabled';

  /// Store the master password for an account
  /// This enables background sync without requiring the user to unlock the vault
  Future<bool> storeMasterPassword(String accountId, String password) async {
    try {
      final key = '$_masterPasswordPrefix$accountId';
      await _storage.write(key: key, value: password);
      print('SecureStorage: Stored master password for account $accountId');
      return true;
    } catch (e) {
      print('SecureStorage: Failed to store master password: $e');
      return false;
    }
  }

  /// Retrieve the stored master password for an account
  /// Returns null if no password is stored
  Future<String?> getMasterPassword(String accountId) async {
    try {
      final key = '$_masterPasswordPrefix$accountId';
      final password = await _storage.read(key: key);
      if (password != null) {
        print(
          'SecureStorage: Retrieved master password for account $accountId',
        );
      } else {
        print('SecureStorage: No stored password for account $accountId');
      }
      return password;
    } catch (e) {
      print('SecureStorage: Failed to retrieve master password: $e');
      return null;
    }
  }

  /// Check if a master password is stored for an account
  Future<bool> hasMasterPassword(String accountId) async {
    try {
      final key = '$_masterPasswordPrefix$accountId';
      final password = await _storage.read(key: key);
      return password != null;
    } catch (e) {
      print('SecureStorage: Failed to check master password: $e');
      return false;
    }
  }

  /// Delete the stored master password for an account
  /// Call this when user logs out or wants to disable background sync
  Future<bool> deleteMasterPassword(String accountId) async {
    try {
      final key = '$_masterPasswordPrefix$accountId';
      await _storage.delete(key: key);
      print('SecureStorage: Deleted master password for account $accountId');
      return true;
    } catch (e) {
      print('SecureStorage: Failed to delete master password: $e');
      return false;
    }
  }

  /// Delete all stored master passwords
  /// Call this when user wants to completely clear stored credentials
  Future<bool> deleteAllMasterPasswords() async {
    try {
      final allKeys = await _storage.readAll();
      for (final key in allKeys.keys) {
        if (key.startsWith(_masterPasswordPrefix)) {
          await _storage.delete(key: key);
        }
      }
      print('SecureStorage: Deleted all master passwords');
      return true;
    } catch (e) {
      print('SecureStorage: Failed to delete all master passwords: $e');
      return false;
    }
  }

  /// Check if background sync is enabled (user preference)
  Future<bool> isBackgroundSyncEnabled() async {
    try {
      final value = await _storage.read(key: _syncEnabledKey);
      // Default to true if not set
      return value != 'false';
    } catch (e) {
      return true;
    }
  }

  /// Set background sync enabled/disabled
  Future<void> setBackgroundSyncEnabled(bool enabled) async {
    try {
      await _storage.write(key: _syncEnabledKey, value: enabled.toString());
    } catch (e) {
      print('SecureStorage: Failed to set background sync enabled: $e');
    }
  }
}
