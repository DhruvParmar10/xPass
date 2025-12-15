import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:kdbx/kdbx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:csv/csv.dart';
import 'account_service.dart';
import 'secure_storage_service.dart';

class KdbxService {
  static final KdbxService _instance = KdbxService._internal();
  factory KdbxService() => _instance;
  KdbxService._internal();

  KdbxFile? _database;
  String? _databasePath;
  static final KdbxFormat _format = KdbxFormat();
  final AccountService _accountService = AccountService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// Check if a vault is currently loaded/unlocked
  bool get isVaultLoaded => _database != null;

  /// Get the appropriate directory for storing databases (account-specific)
  Future<Directory> _getStorageDirectory() async {
    final currentAccount = _accountService.currentAccount;
    if (currentAccount == null) {
      throw Exception('No account selected. Please select an account first.');
    }

    try {
      // Get account-specific directory
      return await _accountService.getAccountDirectory(currentAccount.id);
    } catch (e) {
      print('Error getting account directory: $e');
      rethrow;
    }
  }

  /// Get the default database path for the current account
  Future<String?> getDefaultDatabasePath() async {
    final currentAccount = _accountService.currentAccount;
    if (currentAccount == null) {
      print('Error: No account selected');
      return null;
    }

    final directory = await _getStorageDirectory();
    return '${directory.path}/${currentAccount.name.replaceAll(' ', '_')}_vault.kdbx';
  }

  /// Check if the default database exists for the current account
  Future<bool> hasDefaultDatabase() async {
    try {
      final defaultPath = await getDefaultDatabasePath();
      if (defaultPath == null) return false;
      print('=== KDBX DEBUG: Checking for database at: $defaultPath ===');
      final file = File(defaultPath);
      final exists = await file.exists();
      print('=== KDBX DEBUG: Database exists: $exists ===');
      return exists;
    } catch (e) {
      print('Error checking default database: $e');
      return false;
    }
  }

  /// Create the default database for the current account
  Future<bool> createDefaultDatabase(String masterPassword) async {
    final currentAccount = _accountService.currentAccount;
    if (currentAccount == null) return false;

    try {
      print('=== DEBUG: createDefaultDatabase called ===');
      print('Creating default database for account: ${currentAccount.name}');

      // Create new database
      final credentials = Credentials(
        ProtectedValue.fromString(masterPassword),
      );
      final db = _format.create(credentials, '${currentAccount.name} Vault');

      // Create a default group
      final rootGroup = db.body.rootGroup;
      rootGroup.name.set('Passwords');

      // Get default database path
      final filePath = await getDefaultDatabasePath();
      if (filePath == null) {
        print('Error: Could not get database path');
        return false;
      }
      print('Default database will be stored at: $filePath');

      // Save the database to file
      final bytes = await db.save();
      await File(filePath).writeAsBytes(bytes);

      _database = db;
      _databasePath = filePath;

      // Save as last used database
      await _saveLastDatabasePath(filePath);

      // Store the master password for background sync
      await _secureStorage.storeMasterPassword(
        currentAccount.id,
        masterPassword,
      );
      print('Master password stored for background sync');

      print('Default database created and loaded successfully at: $filePath');
      return true;
    } catch (e) {
      print('Error creating default database: $e');
      return false;
    }
  }

  /// Load the default database for the current account
  Future<bool> loadDefaultDatabase(String masterPassword) async {
    try {
      final defaultPath = await getDefaultDatabasePath();
      if (defaultPath == null) {
        print('Error: Could not get default database path');
        return false;
      }
      return await loadDatabase(defaultPath, masterPassword);
    } catch (e) {
      print('Error loading default database: $e');
      return false;
    }
  }

  /// Initialize the account database (create if new, load if exists)
  Future<bool> initializeAccountDatabase(String masterPassword) async {
    final currentAccount = _accountService.currentAccount;
    if (currentAccount == null) {
      print('No account selected for database initialization');
      return false;
    }

    print('=== DEBUG: initializeAccountDatabase called ===');
    print('Account: ${currentAccount.name}');

    try {
      final hasDefault = await hasDefaultDatabase();
      print('Has default database: $hasDefault');

      if (hasDefault) {
        // Load existing database
        print('Loading existing default database');
        return await loadDefaultDatabase(masterPassword);
      } else {
        // Create new database
        print('Creating new default database');
        return await createDefaultDatabase(masterPassword);
      }
    } catch (e) {
      print('Error initializing account database: $e');
      return false;
    }
  }

  /// Create a new KDBX database (with proper file storage for Android)
  Future<bool> createNewDatabase(String masterPassword, String dbName) async {
    try {
      print('=== DEBUG: createNewDatabase called ===');
      print('Creating new database: $dbName');
      print('Instance hash: ${identityHashCode(this)}');

      // Create new database
      final credentials = Credentials(
        ProtectedValue.fromString(masterPassword),
      );
      final db = _format.create(credentials, 'MyDatabase');

      // Create a default group
      final rootGroup = db.body.rootGroup;
      rootGroup.name.set('Passwords');

      // Get proper storage directory for Android
      final directory = await _getStorageDirectory();
      final filePath = '${directory.path}/$dbName.kdbx';

      print('Database will be stored at: $filePath');

      // Save the database to file
      final bytes = await db.save();
      await File(filePath).writeAsBytes(bytes);

      _database = db;
      _databasePath = filePath;

      // Save as last used database
      await _saveLastDatabasePath(filePath);

      print('Database created and saved successfully at: $filePath');
      return true;
    } catch (e) {
      print('Error creating database: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Load an existing KDBX database from file
  Future<bool> loadDatabase(String filePath, String masterPassword) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Database file not found');
      }

      final bytes = await file.readAsBytes();
      final credentials = Credentials(
        ProtectedValue.fromString(masterPassword),
      );
      final db = await _format.read(bytes, credentials);

      _database = db;
      _databasePath = filePath;

      // Save as last used database
      await _saveLastDatabasePath(filePath);

      // Store the master password for background sync
      final currentAccount = _accountService.currentAccount;
      if (currentAccount != null) {
        await _secureStorage.storeMasterPassword(
          currentAccount.id,
          masterPassword,
        );
        print('Master password stored for background sync');
      }

      return true;
    } catch (e) {
      print('Error loading database: $e');
      return false;
    }
  }

  /// Verify the master password for a specific account without loading the database
  Future<bool> verifyMasterPassword(
    String accountId,
    String masterPassword,
  ) async {
    try {
      // Get the account directory
      final accountDir = await _accountService.getAccountDirectory(accountId);

      // Look for any .kdbx files in the account directory
      final kdbxFiles = await accountDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.kdbx'))
          .toList();

      if (kdbxFiles.isEmpty) {
        print('No database found for account $accountId');
        return false;
      }

      // Try to verify with the first database file found
      final file = File(kdbxFiles.first.path);
      final bytes = await file.readAsBytes();
      final credentials = Credentials(
        ProtectedValue.fromString(masterPassword),
      );

      // This will throw an exception if the password is wrong
      await _format.read(bytes, credentials);

      print('Master password verified successfully for account $accountId');
      return true;
    } catch (e) {
      print('Master password verification failed: $e');
      return false;
    }
  }

  /// Load the database for background sync using stored password
  /// This doesn't require user interaction - uses securely stored password
  /// Returns true if vault was loaded (either already loaded or successfully loaded now)
  Future<bool> ensureVaultLoadedForSync() async {
    print('=== ensureVaultLoadedForSync: Starting ===');

    // If already loaded, we're good
    if (_database != null) {
      print('ensureVaultLoadedForSync: Vault already loaded');
      return true;
    }

    // Try to get account for sync
    var currentAccount = _accountService.currentAccount;
    print(
      'ensureVaultLoadedForSync: Current account = ${currentAccount?.name ?? "NULL"}',
    );

    if (currentAccount == null) {
      print(
        'ensureVaultLoadedForSync: No account selected, attempting restoration...',
      );

      // Use the new lightweight restoration method
      final restored = await _accountService.restoreAccountForSync();
      if (!restored) {
        print('ensureVaultLoadedForSync: Failed to restore account for sync');

        // Try the old method as fallback
        print(
          'ensureVaultLoadedForSync: Trying loadLastAccount as fallback...',
        );
        final fallbackRestored = await _accountService.loadLastAccount();
        if (!fallbackRestored) {
          print('ensureVaultLoadedForSync: All restoration methods failed');
          return false;
        }
      }

      currentAccount = _accountService.currentAccount;
      if (currentAccount == null) {
        print('ensureVaultLoadedForSync: Account still null after restoration');
        return false;
      }
      print(
        'ensureVaultLoadedForSync: Restored account: ${currentAccount.name} (ID: ${currentAccount.id})',
      );
    }

    try {
      // Get stored password
      print(
        'ensureVaultLoadedForSync: Getting stored password for account ${currentAccount.id}',
      );
      final storedPassword = await _secureStorage.getMasterPassword(
        currentAccount.id,
      );
      if (storedPassword == null) {
        print(
          'ensureVaultLoadedForSync: No stored password for account ${currentAccount.id}',
        );
        return false;
      }
      print('ensureVaultLoadedForSync: Found stored password');

      // Check if database exists
      final hasDb = await hasDefaultDatabase();
      if (!hasDb) {
        print('ensureVaultLoadedForSync: No database file exists');
        return false;
      }

      // Load the database
      final defaultPath = await getDefaultDatabasePath();
      if (defaultPath == null) {
        throw Exception('Could not get default database path');
      }
      print('ensureVaultLoadedForSync: Loading vault from: $defaultPath');

      final file = File(defaultPath);
      final bytes = await file.readAsBytes();
      final credentials = Credentials(
        ProtectedValue.fromString(storedPassword),
      );
      final db = await _format.read(bytes, credentials);

      _database = db;
      _databasePath = defaultPath;

      print('=== ensureVaultLoadedForSync: SUCCESS ===');
      return true;
    } catch (e) {
      print('ensureVaultLoadedForSync: Failed to load vault: $e');
      return false;
    }
  }

  /// Check if we have a stored password that can be used for background sync
  Future<bool> canLoadForBackgroundSync() async {
    var currentAccount = _accountService.currentAccount;

    // If no current account, try to get last sync account ID
    if (currentAccount == null) {
      final accountId = await _accountService.getLastSyncAccountId();
      if (accountId == null) {
        print('canLoadForBackgroundSync: No account available');
        return false;
      }

      // Check if password exists for this account
      final hasPassword = await _secureStorage.hasMasterPassword(accountId);
      final hasDb = await hasDefaultDatabase();
      print(
        'canLoadForBackgroundSync: accountId=$accountId, hasPassword=$hasPassword, hasDb=$hasDb',
      );
      return hasPassword && hasDb;
    }

    final hasPassword = await _secureStorage.hasMasterPassword(
      currentAccount.id,
    );
    final hasDb = await hasDefaultDatabase();
    print(
      'canLoadForBackgroundSync: accountId=${currentAccount.id}, hasPassword=$hasPassword, hasDb=$hasDb',
    );
    return hasPassword && hasDb;
  }

  /// Save the current database
  Future<bool> saveDatabase() async {
    if (_database == null) {
      print('Error: No database to save');
      return false;
    }

    try {
      print('Saving database to: $_databasePath');
      final bytes = await _database!.save();

      // Save to file if we have a valid path
      if (_databasePath != null && _databasePath!.isNotEmpty) {
        await File(_databasePath!).writeAsBytes(bytes);
        print('Database saved successfully to: $_databasePath');
      } else {
        print('Warning: Saving in-memory only (no file path)');
      }

      return true;
    } catch (e) {
      print('Error saving database: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Get the database as bytes (for downloading/saving)
  Future<Uint8List?> getDatabaseBytes() async {
    if (_database == null) return null;

    try {
      return await _database!.save();
    } catch (e) {
      print('Error getting database bytes: $e');
      return null;
    }
  }

  /// Get all entries from the database
  List<KdbxEntry> getAllEntries() {
    print('=== DEBUG: getAllEntries called ===');
    print('Database instance: $_database');
    print('Instance hash: ${identityHashCode(this)}');

    if (_database == null) {
      print('Database is null, returning empty list');
      return [];
    }

    List<KdbxEntry> allEntries = [];

    void collectEntries(KdbxGroup group) {
      print('Checking group: ${group.name.get()}');
      print('Group has ${group.entries.length} entries');

      // Filter out deleted entries
      for (final entry in group.entries) {
        final isDeleted =
            entry.getString(KdbxKey('Deleted'))?.getText() == 'true';
        final hasTitle = entry.title.isNotEmpty;

        if (!isDeleted && hasTitle) {
          allEntries.add(entry);
        } else if (isDeleted) {
          print(
            'Skipping deleted entry: ${entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? 'Unknown'}',
          );
        }
      }

      for (final subgroup in group.groups) {
        print('Recursing into subgroup: ${subgroup.name.get()}');
        collectEntries(subgroup);
      }
    }

    final rootGroup = _database!.body.rootGroup;
    print('Root group name: ${rootGroup.name.get()}');
    print('Root group has ${rootGroup.entries.length} direct entries');
    print('Root group has ${rootGroup.groups.length} subgroups');

    collectEntries(rootGroup);

    print('Total entries collected: ${allEntries.length}');
    for (int i = 0; i < allEntries.length; i++) {
      final entry = allEntries[i];
      print('Entry $i: ${entry.title}');
    }

    return allEntries;
  }

  /// Add a new entry to the database
  Future<bool> addEntry({
    required String title,
    required String username,
    required String password,
    String? url,
    String? notes,
    String? tags,
  }) async {
    print('=== DEBUG: addEntry called ===');
    print('Database instance: $_database');
    print('Database path: $_databasePath');
    print('Instance hash: ${identityHashCode(this)}');

    if (_database == null) {
      print('Error: No database loaded in addEntry');
      return false;
    }

    try {
      print('Adding entry: $title');
      final rootGroup = _database!.body.rootGroup;
      print(
        'Root group before entry creation has ${rootGroup.entries.length} entries',
      );

      final entry = KdbxEntry.create(_database!, rootGroup);

      entry.setString(KdbxKeyCommon.TITLE, ProtectedValue.fromString(title));
      entry.setString(
        KdbxKeyCommon.USER_NAME,
        ProtectedValue.fromString(username),
      );
      entry.setString(
        KdbxKeyCommon.PASSWORD,
        ProtectedValue.fromString(password),
      );

      if (url != null && url.isNotEmpty) {
        entry.setString(KdbxKeyCommon.URL, ProtectedValue.fromString(url));
      }

      if (notes != null && notes.isNotEmpty) {
        entry.setString(KdbxKey('Notes'), ProtectedValue.fromString(notes));
      }

      if (tags != null && tags.isNotEmpty) {
        entry.setString(KdbxKey('Tags'), ProtectedValue.fromString(tags));
      }

      // Explicitly add the entry to the root group to ensure it's included
      rootGroup.addEntry(entry);
      print(
        'Root group after adding entry has ${rootGroup.entries.length} entries',
      );
      print('Entry title: ${entry.title}');

      print('Entry created, attempting to save...');
      final saved = await saveDatabase();
      print('Save result: $saved');
      return saved;
    } catch (e) {
      print('Error adding entry: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Update an existing entry
  Future<bool> updateEntry({
    required KdbxEntry entry,
    required String title,
    required String username,
    required String password,
    String? url,
    String? notes,
    String? tags,
  }) async {
    if (_database == null) return false;

    try {
      entry.setString(KdbxKeyCommon.TITLE, ProtectedValue.fromString(title));
      entry.setString(
        KdbxKeyCommon.USER_NAME,
        ProtectedValue.fromString(username),
      );
      entry.setString(
        KdbxKeyCommon.PASSWORD,
        ProtectedValue.fromString(password),
      );

      if (url != null && url.isNotEmpty) {
        entry.setString(KdbxKeyCommon.URL, ProtectedValue.fromString(url));
      } else {
        entry.removeString(KdbxKeyCommon.URL);
      }

      if (notes != null && notes.isNotEmpty) {
        entry.setString(KdbxKey('Notes'), ProtectedValue.fromString(notes));
      } else {
        entry.removeString(KdbxKey('Notes'));
      }

      if (tags != null && tags.isNotEmpty) {
        entry.setString(KdbxKey('Tags'), ProtectedValue.fromString(tags));
      } else {
        entry.removeString(KdbxKey('Tags'));
      }

      await saveDatabase();
      return true;
    } catch (e) {
      print('Error updating entry: $e');
      return false;
    }
  }

  /// Delete an entry from the database
  Future<bool> deleteEntry(KdbxEntry entry) async {
    if (_database == null) return false;

    try {
      print('=== DELETE DEBUG: Attempting to delete entry: ${entry.title} ===');
      print('=== DELETE DEBUG: Entry UUID: ${entry.uuid} ===');

      // Simple approach: mark the entry as deleted by clearing its fields
      // This effectively "deletes" it from the user's perspective
      entry.setString(KdbxKeyCommon.TITLE, ProtectedValue.fromString(''));
      entry.setString(KdbxKeyCommon.USER_NAME, ProtectedValue.fromString(''));
      entry.setString(KdbxKeyCommon.PASSWORD, ProtectedValue.fromString(''));
      entry.setString(KdbxKeyCommon.URL, ProtectedValue.fromString(''));
      entry.setString(KdbxKey('Notes'), ProtectedValue.fromString(''));

      // Mark the entry with a special flag to indicate it's deleted
      entry.setString(KdbxKey('Deleted'), ProtectedValue.fromString('true'));

      await saveDatabase();
      print('=== DELETE DEBUG: Entry marked as deleted and database saved ===');

      return true;
    } catch (e) {
      print('Error deleting entry: $e');
      return false;
    }
  }

  /// Close the current database
  void closeDatabase() {
    _database = null;
    _databasePath = null;
  }

  /// Check if a database is currently loaded
  bool get isDatabaseLoaded {
    final loaded = _database != null;
    print(
      'Database loaded status: $loaded (path: $_databasePath) [Instance: ${identityHashCode(this)}]',
    );
    return loaded;
  }

  /// Check if an account is currently selected
  bool get isAccountSelected {
    return _accountService.currentAccount != null;
  }

  /// Get current account info
  Account? get currentAccount {
    return _accountService.currentAccount;
  }

  /// Get the current database path
  String? get databasePath => _databasePath;

  /// Get database name from path
  String? get databaseName {
    if (_databasePath == null) return null;
    return _databasePath!.split('/').last.replaceAll('.kdbx', '');
  }

  /// Save the last used database path to preferences (account-specific)
  Future<void> _saveLastDatabasePath(String path) async {
    final currentAccount = _accountService.currentAccount;
    if (currentAccount == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'last_database_path_${currentAccount.id}';
      await prefs.setString(key, path);
      print(
        'Saved last database path for account ${currentAccount.name}: $path',
      );
    } catch (e) {
      print('Error saving last database path: $e');
    }
  }

  /// Get the last used database path from preferences (account-specific)
  Future<String?> _getLastDatabasePath() async {
    final currentAccount = _accountService.currentAccount;
    if (currentAccount == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'last_database_path_${currentAccount.id}';
      final path = prefs.getString(key);
      print(
        'Retrieved last database path for account ${currentAccount.name}: $path',
      );
      return path;
    } catch (e) {
      print('Error getting last database path: $e');
      return null;
    }
  }

  /// Check if the last used database exists and is accessible
  Future<bool> hasLastDatabase() async {
    final lastPath = await _getLastDatabasePath();
    if (lastPath == null) return false;

    final file = File(lastPath);
    return await file.exists();
  }

  /// Get the last database info for display
  Future<Map<String, String>?> getLastDatabaseInfo() async {
    final lastPath = await _getLastDatabasePath();
    if (lastPath == null) return null;

    final file = File(lastPath);
    if (!await file.exists()) return null;

    final name = lastPath.split('/').last.replaceAll('.kdbx', '');
    return {'name': name, 'path': lastPath};
  }

  /// Generate a secure password
  String generatePassword({int length = 16, bool includeSymbols = true}) {
    if (length < 4) length = 4;

    const lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digits = '0123456789';
    const symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    final random = Random.secure();
    final password = <String>[];

    // Ensure at least one of each required type
    password.add(lowercase[random.nextInt(lowercase.length)]);
    password.add(uppercase[random.nextInt(uppercase.length)]);
    password.add(digits[random.nextInt(digits.length)]);

    if (includeSymbols && length > 3) {
      password.add(symbols[random.nextInt(symbols.length)]);
    }

    // Fill remaining length
    final charset =
        lowercase + uppercase + digits + (includeSymbols ? symbols : '');
    while (password.length < length) {
      password.add(charset[random.nextInt(charset.length)]);
    }

    // Shuffle to avoid predictable patterns
    password.shuffle(random);

    return password.join();
  }

  /// Debug method to list all .kdbx files in storage directory
  Future<void> listStoredDatabases() async {
    try {
      final directory = await _getStorageDirectory();
      print('Storage directory: ${directory.path}');

      final files = directory.listSync();
      final kdbxFiles = files.where((file) => file.path.endsWith('.kdbx'));

      print('Found ${kdbxFiles.length} .kdbx files:');
      for (final file in kdbxFiles) {
        print('  - ${file.path}');
      }
    } catch (e) {
      print('Error listing databases: $e');
    }
  }

  /// Export current database to Documents folder
  Future<String?> exportDatabase() async {
    if (_database == null) {
      print('Error: No database to export');
      return null;
    }

    try {
      final currentAccount = _accountService.currentAccount;
      if (currentAccount == null) {
        print('Error: No account selected');
        return null;
      }

      // Use external storage Documents directory for Android, app Documents for others
      late Directory exportDir;
      if (Platform.isAndroid) {
        // Request storage permission first
        bool hasPermission = await _requestStoragePermission();

        if (hasPermission) {
          // Use external storage Documents directory for Android
          try {
            exportDir = Directory('/storage/emulated/0/Documents');
            if (!await exportDir.exists()) {
              // Create Documents directory if it doesn't exist
              try {
                await exportDir.create(recursive: true);
              } catch (e) {
                print('Could not create Documents directory: $e');
                // Fallback to Downloads if Documents can't be created
                exportDir = Directory('/storage/emulated/0/Download');
                if (!await exportDir.exists()) {
                  // Final fallback to app documents directory
                  exportDir = await getApplicationDocumentsDirectory();
                }
              }
            }
          } catch (e) {
            print('Error accessing external storage, using app documents: $e');
            exportDir = await getApplicationDocumentsDirectory();
          }
        } else {
          print('Storage permission denied, using app documents directory');
          exportDir = await getApplicationDocumentsDirectory();
        }
      } else {
        // Use app Documents directory for iOS/macOS to avoid sandbox restrictions
        exportDir = await getApplicationDocumentsDirectory();
      }

      // Create filename with timestamp
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final filename =
          '${currentAccount.name.replaceAll(' ', '_')}_vault_$timestamp.kdbx';
      final exportPath = '${exportDir.path}/$filename';

      // Save database to chosen directory
      final bytes = await _database!.save();
      await File(exportPath).writeAsBytes(bytes);

      print('Database exported successfully to: $exportPath');
      return exportPath;
    } catch (e) {
      print('Error exporting database: $e');
      return null;
    }
  }

  /// Export passwords to CSV file
  Future<String?> exportCsvPasswords() async {
    if (_database == null) {
      print('Error: No database to export');
      return null;
    }

    try {
      final currentAccount = _accountService.currentAccount;
      if (currentAccount == null) {
        print('Error: No account selected');
        return null;
      }

      // Get all entries
      final entries = getAllEntries();
      if (entries.isEmpty) {
        print('No entries to export');
        return null;
      }

      // Create CSV content
      List<List<String>> csvData = [];

      // Add header row
      csvData.add([
        'Title',
        'Username/Email',
        'Password',
        'URL',
        'Tags',
        'Notes',
      ]);

      // Add entry rows
      for (final entry in entries) {
        final title = entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '';
        final username =
            entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '';
        final password =
            entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '';
        final url = entry.getString(KdbxKeyCommon.URL)?.getText() ?? '';
        final tags = entry.getString(KdbxKey('Tags'))?.getText() ?? '';
        final notes = entry.getString(KdbxKey('Notes'))?.getText() ?? '';

        csvData.add([title, username, password, url, tags, notes]);
      }

      // Convert to CSV string
      final csvString = const ListToCsvConverter().convert(csvData);

      // Get export directory
      late Directory exportDir;
      if (Platform.isAndroid) {
        bool hasPermission = await _requestStoragePermission();
        if (hasPermission) {
          try {
            // Try multiple storage locations for compatibility
            final List<Directory?> possibleDirs = [
              await getExternalStorageDirectory(), // App-specific external storage
              Directory('/storage/emulated/0/Documents'),
              Directory('/storage/emulated/0/Download'),
            ];

            Directory? validDir;
            for (final dir in possibleDirs) {
              if (dir != null) {
                try {
                  if (await dir.exists() ||
                      await dir
                          .create(recursive: true)
                          .then((_) => true)
                          .catchError((_) => false)) {
                    validDir = dir;
                    break;
                  }
                } catch (e) {
                  continue;
                }
              }
            }

            exportDir = validDir ?? await getApplicationDocumentsDirectory();
          } catch (e) {
            print('Error accessing Android storage: $e');
            exportDir = await getApplicationDocumentsDirectory();
          }
        } else {
          exportDir = await getApplicationDocumentsDirectory();
        }
      } else {
        exportDir = await getApplicationDocumentsDirectory();
      }

      // Create filename with timestamp
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final filename =
          '${currentAccount.name.replaceAll(' ', '_')}_passwords_$timestamp.csv';
      final exportPath = '${exportDir.path}/$filename';

      // Write CSV to file
      await File(exportPath).writeAsString(csvString);

      print('CSV exported successfully to: $exportPath');
      return exportPath;
    } catch (e) {
      print('Error exporting CSV: $e');
      return null;
    }
  }

  /// Request storage permission for Android devices
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // Check current permission status
      var status = await Permission.storage.status;

      if (status.isGranted) {
        return true;
      }

      if (status.isDenied) {
        // Request permission
        status = await Permission.storage.request();
        if (status.isGranted) {
          return true;
        }
      }

      // For Android 11+ (API 30+), also check manage external storage permission
      if (Platform.isAndroid) {
        var manageStatus = await Permission.manageExternalStorage.status;
        if (manageStatus.isDenied) {
          manageStatus = await Permission.manageExternalStorage.request();
          if (manageStatus.isGranted) {
            return true;
          }
        } else if (manageStatus.isGranted) {
          return true;
        }
      }

      return false;
    } catch (e) {
      print('Error requesting storage permission: $e');
      return false;
    }
  }

  /// Import KDBX file and merge with current database
  Future<bool> importAndMergeDatabase(
    String filePath,
    String password,
    bool replaceExisting,
  ) async {
    try {
      // Load the imported database
      final importedFile = File(filePath);
      if (!await importedFile.exists()) {
        print('Error: Import file does not exist');
        return false;
      }

      final importedBytes = await importedFile.readAsBytes();
      final importedCredentials = Credentials(
        ProtectedValue.fromString(password),
      );

      KdbxFile importedDb;
      try {
        importedDb = await _format.read(importedBytes, importedCredentials);
        print('Successfully loaded imported database');
      } catch (e) {
        print('Error: Invalid password or corrupted file: $e');
        return false;
      }

      if (replaceExisting) {
        // Replace entire database
        _database = importedDb;
        await saveDatabase();
        print('Database replaced successfully');
        return true;
      } else {
        // Merge entries
        if (_database == null) {
          print('Error: No current database to merge with');
          return false;
        }

        final currentGroup = _database!.body.rootGroup;
        final importedGroup = importedDb.body.rootGroup;
        int mergedCount = 0;

        // Add all entries from imported database to current database
        for (final entry in importedGroup.entries) {
          // Create a copy of the entry
          final newEntry = KdbxEntry.create(_database!, currentGroup);

          // Copy all standard fields
          newEntry.setString(
            KdbxKeyCommon.TITLE,
            entry.getString(KdbxKeyCommon.TITLE),
          );
          newEntry.setString(
            KdbxKeyCommon.USER_NAME,
            entry.getString(KdbxKeyCommon.USER_NAME),
          );
          newEntry.setString(
            KdbxKeyCommon.PASSWORD,
            entry.getString(KdbxKeyCommon.PASSWORD),
          );
          newEntry.setString(
            KdbxKeyCommon.URL,
            entry.getString(KdbxKeyCommon.URL),
          );
          newEntry.setString(
            KdbxKey('Notes'),
            entry.getString(KdbxKey('Notes')),
          );

          // Copy tags if they exist
          final tags = entry.getString(KdbxKey('Tags'));
          if (tags != null) {
            newEntry.setString(KdbxKey('Tags'), tags);
          }

          currentGroup.addEntry(newEntry);
          mergedCount++;
        }

        await saveDatabase();
        print('Successfully merged $mergedCount entries');
        return true;
      }
    } catch (e) {
      print('Error importing database: $e');
      return false;
    }
  }

  /// Import KDBX file using either file path or bytes and merge with current database
  Future<bool> importAndMergeDatabaseWithBytes(
    String? filePath,
    Uint8List? fileBytes,
    String password,
    bool replaceExisting,
  ) async {
    try {
      // Get bytes either from file or parameter
      Uint8List importedBytes;
      if (fileBytes != null) {
        importedBytes = fileBytes;
      } else if (filePath != null) {
        final importedFile = File(filePath);
        if (!await importedFile.exists()) {
          print('Error: Import file does not exist');
          return false;
        }
        importedBytes = await importedFile.readAsBytes();
      } else {
        print('Error: No file path or bytes provided');
        return false;
      }

      final importedCredentials = Credentials(
        ProtectedValue.fromString(password),
      );

      KdbxFile importedDb;
      try {
        importedDb = await _format.read(importedBytes, importedCredentials);
        print('Successfully loaded imported database');
      } catch (e) {
        print('Error: Invalid password or corrupted file: $e');
        return false;
      }

      if (replaceExisting) {
        // Replace entire database
        _database = importedDb;
        await saveDatabase();
        print('Database replaced successfully');
        return true;
      } else {
        // Merge entries
        if (_database == null) {
          print('No current database found, creating new one for merge');
          // Create a new database if one doesn't exist
          final currentAccount = _accountService.currentAccount;
          if (currentAccount == null) {
            print('Error: No account selected');
            return false;
          }

          // Create a new database with the imported data
          _database = importedDb;
          await saveDatabase();
          print('New database created with imported data');
          return true;
        }

        final currentGroup = _database!.body.rootGroup;
        final importedGroup = importedDb.body.rootGroup;
        int mergedCount = 0;

        // Add all entries from imported database to current database
        for (final entry in importedGroup.entries) {
          // Create a copy of the entry
          final newEntry = KdbxEntry.create(_database!, currentGroup);

          // Copy all standard fields
          newEntry.setString(
            KdbxKeyCommon.TITLE,
            entry.getString(KdbxKeyCommon.TITLE),
          );
          newEntry.setString(
            KdbxKeyCommon.USER_NAME,
            entry.getString(KdbxKeyCommon.USER_NAME),
          );
          newEntry.setString(
            KdbxKeyCommon.PASSWORD,
            entry.getString(KdbxKeyCommon.PASSWORD),
          );
          newEntry.setString(
            KdbxKeyCommon.URL,
            entry.getString(KdbxKeyCommon.URL),
          );
          newEntry.setString(
            KdbxKey('Notes'),
            entry.getString(KdbxKey('Notes')),
          );

          // Copy tags if they exist
          final tags = entry.getString(KdbxKey('Tags'));
          if (tags != null) {
            newEntry.setString(KdbxKey('Tags'), tags);
          }

          currentGroup.addEntry(newEntry);
          mergedCount++;
        }

        await saveDatabase();
        print('Successfully merged $mergedCount entries');
        return true;
      }
    } catch (e) {
      print('Error importing database: $e');
      return false;
    }
  }

  /// Parse CSV content to a list of entry maps
  /// Expected CSV format: user_name,title,password,url,tags
  List<Map<String, String>> parseCsvToEntries(String csvContent) {
    try {
      // Parse CSV content
      final csvData = const CsvToListConverter().convert(csvContent);

      if (csvData.isEmpty) {
        print('Error: CSV file is empty');
        return [];
      }

      // Check if first row is header
      final originalHeaders = csvData.first
          .map((e) => e.toString().toLowerCase().trim())
          .toList();

      // Map common header variations to our expected format
      final headers = originalHeaders.map((header) {
        switch (header) {
          case 'username':
          case 'username/email':
          case 'user':
          case 'login':
          case 'email':
            return 'user_name';
          case 'title':
          case 'site':
          case 'service':
          case 'website_name':
            return 'title';
          case 'name':
            // Ambiguous: could be username OR site name - default to username with warning
            print(
              'WARNING: CSV column "name" is ambiguous. Treating as username. Consider using "title" for site name or "username" for login.',
            );
            return 'user_name';
          case 'pass':
          case 'pwd':
            return 'password';
          case 'website':
          case 'site_url':
            return 'url';
          case 'tag':
          case 'category':
          case 'group':
            return 'tags';
          case 'note':
          case 'comment':
            return 'notes';
          default:
            return header;
        }
      }).toList();

      // Validate expected columns
      final expectedColumns = [
        'title',
        'user_name',
        'password',
        'url',
        'tags',
        'notes',
      ];
      for (String column in expectedColumns) {
        if (!headers.contains(column)) {
          print('Warning: CSV missing expected column: $column');
        }
      }

      print('Original CSV Headers: $originalHeaders');
      print('Mapped Headers: $headers');

      // Parse data rows
      List<Map<String, String>> entries = [];
      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.isEmpty ||
            (row.length == 1 && row[0].toString().trim().isEmpty)) {
          // Skip empty rows
          continue;
        }
        if (row.length < headers.length) {
          print(
            'Warning: Row $i has ${row.length} columns but expected ${headers.length}, padding with empty values',
          );
        }

        Map<String, String> entry = {};
        for (int j = 0; j < headers.length && j < row.length; j++) {
          entry[headers[j]] = row[j]?.toString() ?? '';
        }

        // Ensure all expected fields exist
        for (String field in expectedColumns) {
          if (!entry.containsKey(field)) {
            entry[field] = '';
          }
        }

        // Debug: Print the first few entries
        if (entries.length < 3) {
          print('Parsed entry ${entries.length + 1}: $entry');
        }

        entries.add(entry);
      }

      print('Successfully parsed ${entries.length} CSV entries');
      return entries;
    } catch (e) {
      print('Error parsing CSV content: $e');
      return [];
    }
  }

  /// Import CSV file and merge with current database
  /// Returns a map with 'imported' and 'skipped' counts, or null on error
  Future<Map<String, int>?> importCsvDatabase(
    String? filePath,
    Uint8List? fileBytes,
    bool replaceExisting,
    String? masterPassword,
  ) async {
    try {
      // Get CSV content either from file or bytes
      String csvContent;
      if (fileBytes != null) {
        csvContent = utf8.decode(fileBytes);
      } else if (filePath != null) {
        final csvFile = File(filePath);
        if (!await csvFile.exists()) {
          print('Error: CSV file does not exist');
          return null;
        }
        csvContent = await csvFile.readAsString();
      } else {
        print('Error: No file path or bytes provided');
        return null;
      }

      // Parse CSV to entries
      final csvEntries = parseCsvToEntries(csvContent);
      if (csvEntries.isEmpty) {
        print('Error: No valid entries found in CSV file');
        return null;
      }

      // Handle database creation/replacement
      if (replaceExisting || _database == null) {
        final currentAccount = _accountService.currentAccount;
        if (currentAccount == null) {
          print('Error: No account selected');
          return null;
        }

        if (_database == null || replaceExisting) {
          // Create new database for CSV import
          if (masterPassword == null || masterPassword.isEmpty) {
            print('Error: Master password required for database creation');
            return null;
          }

          final success = await createNewDatabase(
            masterPassword,
            'csv_import_${DateTime.now().millisecondsSinceEpoch}',
          );
          if (!success) {
            print('Error: Failed to create new database for CSV import');
            return null;
          }
          print('Created new database for CSV import');
        }
      }

      if (_database == null) {
        print('Error: Failed to create or load database');
        return null;
      }

      final currentGroup = _database!.body.rootGroup;
      int importedCount = 0;
      int skippedCount = 0;

      // Get all existing entries for duplicate checking
      final existingEntries = getAllEntries();

      // Convert CSV entries to KDBX entries
      for (final csvEntry in csvEntries) {
        final csvUsername = csvEntry['user_name'] ?? '';
        final csvUrl = csvEntry['url'] ?? '';
        final csvPassword = csvEntry['password'] ?? '';

        // Check if entry already exists (matching username/email, url, and password)
        final isDuplicate = existingEntries.any((entry) {
          final existingUsername =
              entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '';
          final existingUrl =
              entry.getString(KdbxKeyCommon.URL)?.getText() ?? '';
          final existingPassword =
              entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '';

          return existingUsername == csvUsername &&
              existingUrl == csvUrl &&
              existingPassword == csvPassword;
        });

        if (isDuplicate) {
          print('Skipping duplicate entry: ${csvEntry['title']}');
          skippedCount++;
          continue;
        }

        final newEntry = KdbxEntry.create(_database!, currentGroup);

        // Debug: Print what we're importing
        print('Importing entry with data: $csvEntry');
        print('Username from CSV: "${csvEntry['user_name']}"');
        print('Title from CSV: "${csvEntry['title']}"');

        // Set standard fields
        newEntry.setString(
          KdbxKeyCommon.TITLE,
          ProtectedValue.fromString(csvEntry['title'] ?? ''),
        );
        newEntry.setString(
          KdbxKeyCommon.USER_NAME,
          ProtectedValue.fromString(csvUsername),
        );
        newEntry.setString(
          KdbxKeyCommon.PASSWORD,
          ProtectedValue.fromString(csvPassword),
        );
        newEntry.setString(
          KdbxKeyCommon.URL,
          ProtectedValue.fromString(csvUrl),
        );

        // Set tags if provided
        final tags = csvEntry['tags']?.trim();
        print('DEBUG: Tags from CSV entry: "$tags"');
        if (tags != null && tags.isNotEmpty) {
          newEntry.setString(KdbxKey('Tags'), ProtectedValue.fromString(tags));
          print('DEBUG: Tags set on entry: "$tags"');
        } else {
          print('DEBUG: No tags to set');
        }

        // Set notes if provided
        final notes = csvEntry['notes']?.trim();
        if (notes != null && notes.isNotEmpty) {
          newEntry.setString(
            KdbxKey('Notes'),
            ProtectedValue.fromString(notes),
          );
        }

        currentGroup.addEntry(newEntry);

        // Debug: Verify the entry was added with tags
        final verifyTags = newEntry.getString(KdbxKey('Tags'))?.getText() ?? '';
        print('DEBUG: Verified tags on newly added entry: "$verifyTags"');

        importedCount++;
      }

      await saveDatabase();
      print('Successfully imported $importedCount CSV entries');
      if (skippedCount > 0) {
        print('Skipped $skippedCount duplicate entries');
      }
      return {'imported': importedCount, 'skipped': skippedCount};
    } catch (e) {
      print('Error importing CSV database: $e');
      return null;
    }
  }
}

// Extension to get string values safely from KdbxEntry
extension KdbxEntryExtension on KdbxEntry {
  String getStringValue(KdbxKey key) {
    return getString(key)?.getText() ?? '';
  }

  String get title => getStringValue(KdbxKeyCommon.TITLE);
  String get username => getStringValue(KdbxKeyCommon.USER_NAME);
  String get password => getStringValue(KdbxKeyCommon.PASSWORD);
  String get url => getStringValue(KdbxKeyCommon.URL);
  String get notes => getStringValue(KdbxKey('Notes'));
}
