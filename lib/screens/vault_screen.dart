import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kdbx/kdbx.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:math';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/kdbx_service.dart';
import '../services/account_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final KdbxService _kdbxService = KdbxService();
  final AccountService _accountService = AccountService();
  final TextEditingController _searchController = TextEditingController();
  List<KdbxEntry> entries = [];
  List<KdbxEntry> filteredEntries = [];
  bool isLoading = false;
  Set<String> availableTags = {};
  String? selectedTag;

  // Predefined common tags
  final List<String> commonTags = [
    'Work',
    'Personal',
    'Family',
    'Development',
    'Finance',
    'Social',
    'Entertainment',
    'Shopping',
    'Health',
    'Education',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterEntries);
    _initializeVault();
  }

  Future<void> _initializeVault() async {
    // Check if account is selected
    if (!_kdbxService.isAccountSelected) {
      Navigator.pop(context);
      return;
    }

    // Initialize database for the account
    await _initializeAccountDatabase();
  }

  Future<void> _initializeAccountDatabase() async {
    setState(() => isLoading = true);

    try {
      // Debug: debugPrint current account info
      final currentAccount = _accountService.currentAccount;
      debugPrint(
        '=== VAULT DEBUG: Current account: ${currentAccount?.name} (${currentAccount?.id}) ===',
      );

      // Check if default database exists using KdbxService
      final hasDatabase = await _kdbxService.hasDefaultDatabase();
      debugPrint('=== VAULT DEBUG: Has default database: $hasDatabase ===');

      if (hasDatabase) {
        // Database exists, ask for password to load it
        await _showPasswordDialog((password) async {
          final success = await _kdbxService.loadDefaultDatabase(password);
          if (success) {
            _loadEntries();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vault loaded successfully')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to load vault. Check your password.'),
              ),
            );
            // Return to home screen on failed password
            Navigator.pop(context);
          }
        });
      } else {
        // Database doesn't exist, create it
        await _createDefaultDatabase();
      }
    } catch (e) {
      debugPrint('Error initializing database: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error initializing vault')));
      Navigator.pop(context);
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _createDefaultDatabase() async {
    await _showCreateVaultPasswordDialog((password) async {
      final success = await _kdbxService.createDefaultDatabase(password);

      if (success) {
        _loadEntries();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault created successfully')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to create vault')));
        Navigator.pop(context);
      }
    });
  }

  void _loadEntries() {
    debugPrint('=== DEBUG: _loadEntries called ===');
    final newEntries = _kdbxService.getAllEntries();
    debugPrint('Found ${newEntries.length} entries');

    // Extract all available tags from entries
    Set<String> allTags = {};
    for (final entry in newEntries) {
      final tags = _getEntryTags(entry);
      allTags.addAll(tags);
      debugPrint('Entry ${entry.title} has tags: $tags');
    }

    setState(() {
      entries = newEntries;
      availableTags = allTags;
      _filterEntries(); // Apply current filters
    });
    debugPrint(
      'UI updated with ${entries.length} entries and ${availableTags.length} unique tags',
    );
  }

  List<String> _getEntryTags(KdbxEntry entry) {
    final tagsString = entry.getString(KdbxKey('Tags'))?.getText() ?? '';
    if (tagsString.isEmpty) return [];
    return tagsString
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  void _filterEntries() {
    final query = _searchController.text.toLowerCase();

    List<KdbxEntry> filtered = entries;

    // Apply tag filter first
    if (selectedTag != null && selectedTag!.isNotEmpty) {
      filtered = filtered.where((entry) {
        final entryTags = _getEntryTags(entry);
        return entryTags.contains(selectedTag!);
      }).toList();
    }

    // Apply search filter
    if (query.isNotEmpty) {
      filtered = filtered.where((entry) {
        return entry.title.toLowerCase().contains(query) ||
            entry.username.toLowerCase().contains(query) ||
            entry.url.toLowerCase().contains(query);
      }).toList();
    }

    setState(() {
      filteredEntries = filtered;
    });
  }

  Widget _buildTagChip(String tag, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedTag = isSelected ? null : tag;
        });
        _filterEntries();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer,
              size: 14,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              tag,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportDatabase() async {
    try {
      final exportPath = await _kdbxService.exportDatabase();
      if (exportPath != null) {
        if (mounted) {
          // Extract just the filename for display
          final fileName = exportPath.split('/').last;

          // Determine location message based on platform and path
          String locationMessage;
          if (exportPath.contains('/storage/emulated/0/Documents')) {
            locationMessage = 'Saved to device Documents folder';
          } else if (exportPath.contains('/storage/emulated/0/Download')) {
            locationMessage = 'Saved to device Downloads folder';
          } else {
            locationMessage = 'Saved to Documents folder';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Vault exported successfully as:\n$fileName\n\n$locationMessage',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to export vault'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting vault: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showImportDialog() async {
    // Show dialog to choose import type
    final importType = await _showImportTypeDialog();
    if (importType == null) return;

    if (importType == 'csv') {
      await _showCsvImportDialog();
    } else {
      await _showKdbxImportDialog();
    }
  }

  Future<String?> _showImportTypeDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose Import Type'),
          content: const Text('What type of file would you like to import?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'csv'),
              child: const Text('CSV File'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'kdbx'),
              child: const Text('KDBX Vault'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showKdbxImportDialog() async {
    // On macOS, show a simpler approach due to sandbox restrictions
    if (Platform.isMacOS) {
      await _showMacOSImportDialog();
      return;
    }

    try {
      // Try different file picker approaches for better compatibility
      FilePickerResult? result;

      try {
        // First try with any file type (more compatible)
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          withData: false,
          withReadStream: false,
          dialogTitle: 'Select KDBX file to import',
        );
      } catch (e) {
        debugPrint('Standard file picker failed: $e');
        // If that fails, try with bytes
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
            withData: true,
            withReadStream: false,
          );
        } catch (e2) {
          debugPrint('File picker with data failed: $e2');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'File picker not available. Please check app permissions.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final pickedFile = result.files.first;
      final filePath = pickedFile.path;
      final fileBytes = pickedFile.bytes;

      // We need either a path or bytes
      if (filePath == null && fileBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to access selected file'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Validate file extension using filename
      final fileName = pickedFile.name.toLowerCase();
      if (!fileName.endsWith('.kdbx')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a .kdbx file'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Show password and import options dialog
      await _showImportOptionsDialog(filePath, fileBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showMacOSImportDialog() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final kdbxFiles = Directory(documentsDir.path)
        .listSync()
        .where(
          (file) =>
              file.path.endsWith('.kdbx') &&
              FileSystemEntity.isFileSync(file.path),
        )
        .map((file) => File(file.path))
        .toList();

    if (kdbxFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No KDBX files found in Documents folder.\nPath: ${documentsDir.path}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final selectedFile = await showDialog<File>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select KDBX File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a KDBX file from your Documents folder:'),
            const SizedBox(height: 16),
            ...kdbxFiles.map(
              (file) => ListTile(
                title: Text(file.path.split('/').last),
                subtitle: Text(file.path),
                onTap: () => Navigator.of(context).pop(file),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedFile != null) {
      await _showImportOptionsDialog(selectedFile.path, null);
    }
  }

  Future<void> _showImportOptionsDialog(
    String? filePath,
    Uint8List? fileBytes,
  ) async {
    String password = '';
    bool replaceExisting = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Import Vault'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter the password for the imported vault:'),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => password = value,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Replace existing vault'),
                    subtitle: const Text(
                      'If unchecked, entries will be merged',
                    ),
                    value: replaceExisting,
                    onChanged: (value) {
                      setState(() {
                        replaceExisting = value ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: password.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('Import'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && password.isNotEmpty) {
      await _performImport(filePath, fileBytes, password, replaceExisting);
    }
  }

  Future<void> _performImport(
    String? filePath,
    Uint8List? fileBytes,
    String password,
    bool replaceExisting,
  ) async {
    setState(() => isLoading = true);

    try {
      final success = await _kdbxService.importAndMergeDatabaseWithBytes(
        filePath,
        fileBytes,
        password,
        replaceExisting,
      );

      if (success) {
        // Reload entries to show imported data
        _loadEntries();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                replaceExisting
                    ? 'Vault replaced successfully'
                    : 'Vault merged successfully',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to import vault. Check password and file.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing vault: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _showCsvImportDialog() async {
    try {
      // Try different file picker approaches for better compatibility
      FilePickerResult? result;

      try {
        // Pick CSV files
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          allowMultiple: false,
          withData: false,
          withReadStream: false,
          dialogTitle: 'Select CSV file to import',
        );
      } catch (e) {
        debugPrint('CSV file picker failed: $e');
        // If that fails, try with any file type and validate manually
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
            withData: true,
            withReadStream: false,
            dialogTitle: 'Select CSV file to import',
          );
        } catch (e2) {
          debugPrint('File picker with data failed: $e2');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'File picker not available. Please check app permissions.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final pickedFile = result.files.first;
      final filePath = pickedFile.path;
      final fileBytes = pickedFile.bytes;

      // We need either a path or bytes
      if (filePath == null && fileBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to access selected file'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Validate file extension using filename
      final fileName = pickedFile.name.toLowerCase();
      if (!fileName.endsWith('.csv')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a .csv file'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Show CSV import options dialog
      await _showCsvImportOptionsDialog(filePath, fileBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting CSV file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showCsvImportOptionsDialog(
    String? filePath,
    Uint8List? fileBytes,
  ) async {
    String password = '';
    bool replaceExisting = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Import CSV'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter a master password for the imported data.\n'
                    'Expected CSV format: user_name,title,password,url,tags',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Master Password',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => password = value,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Replace existing data'),
                    subtitle: const Text(
                      'Uncheck to merge with existing vault',
                    ),
                    value: replaceExisting,
                    onChanged: (value) {
                      setState(() {
                        replaceExisting = value ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: password.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('Import CSV'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && password.isNotEmpty) {
      await _performCsvImport(filePath, fileBytes, password, replaceExisting);
    }
  }

  Future<void> _performCsvImport(
    String? filePath,
    Uint8List? fileBytes,
    String password,
    bool replaceExisting,
  ) async {
    setState(() => isLoading = true);

    try {
      final success = await _kdbxService.importCsvDatabase(
        filePath,
        fileBytes,
        replaceExisting,
        password,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV imported successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh the entries list
          _loadEntries();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to import CSV. Please check the file format.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _showPasswordDialog(Function(String) onPasswordSubmitted) async {
    String? password;
    await showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing without password
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text('Enter Vault Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your master password to unlock ${_accountService.currentAccount?.name}\'s vault.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Master Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Return to home screen
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                password = controller.text;
                Navigator.pop(context);
                if (password != null && password!.isNotEmpty) {
                  onPasswordSubmitted(password!);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateVaultPasswordDialog(
    Function(String) onPasswordSubmitted,
  ) async {
    String? password;
    String? confirmPassword;

    await showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing without creating vault
      builder: (context) {
        final passwordController = TextEditingController();
        final confirmPasswordController = TextEditingController();

        return AlertDialog(
          title: Text(
            'Create Vault for ${_accountService.currentAccount?.name}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create a master password for your vault. This will encrypt all your passwords.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Master Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Return to home screen
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                password = passwordController.text;
                confirmPassword = confirmPasswordController.text;

                if (password != null && password!.isNotEmpty) {
                  if (password == confirmPassword) {
                    Navigator.pop(context);
                    onPasswordSubmitted(password!);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passwords do not match')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a password')),
                  );
                }
              },
              child: const Text('Create Vault'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              _kdbxService.isDatabaseLoaded
                  ? 'Vault - ${_kdbxService.databaseName ?? 'Unknown'}'
                  : 'Password Vault',
              style: const TextStyle(fontSize: 18),
            ),
            if (_accountService.currentAccount != null)
              Text(
                _accountService.currentAccount!.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        elevation: 2,
        centerTitle: true,
        backgroundColor: Colors.indigo,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            // Always close database when going back to home for security
            _kdbxService.closeDatabase();
            Navigator.pop(context);
          },
        ),
        actions: _kdbxService.isDatabaseLoaded
            ? [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'export':
                        _exportDatabase();
                        break;
                      case 'import':
                        _showImportDialog();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.download, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text('Export Vault'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.upload, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text('Import Vault'),
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : null,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_kdbxService.isDatabaseLoaded
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Vault not loaded',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your password and try again',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Return Home'),
                  ),
                ],
              ),
            )
          : entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_open_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your vault is empty',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your first password entry',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Search bar
                if (entries.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search passwords...',
                        prefixIcon: Icon(Icons.search, color: Colors.indigo),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.indigo,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                // Tag selector
                if (entries.isNotEmpty &&
                    (availableTags.isNotEmpty || selectedTag != null))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_offer,
                              size: 16,
                              color: Colors.indigo,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Filter by Tags:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Spacer(),
                            if (selectedTag != null)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    selectedTag = null;
                                  });
                                  _filterEntries();
                                },
                                child: Text(
                                  'Clear Filter',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              // Show all available tags
                              ...availableTags.map(
                                (tag) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _buildTagChip(tag, selectedTag == tag),
                                ),
                              ),
                              // Show selected tag if it's not in available tags (edge case)
                              if (selectedTag != null &&
                                  !availableTags.contains(selectedTag!))
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _buildTagChip(selectedTag!, true),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                // Results area
                Expanded(
                  child:
                      filteredEntries.isEmpty &&
                          _searchController.text.isNotEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No matching entries found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try a different search term',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: filteredEntries.length,
                          itemBuilder: (context, index) {
                            final entry = filteredEntries[index];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  entry.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 17,
                                  ),
                                ),
                                subtitle: Text(
                                  entry.username,
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[500],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AddEditEntryScreen(),
                                      settings: RouteSettings(arguments: entry),
                                    ),
                                  ).then((result) {
                                    debugPrint(
                                      '=== NAVIGATION DEBUG: Returned from AddEditEntryScreen with result: $result ===',
                                    );
                                    _loadEntries();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _kdbxService.isDatabaseLoaded
          ? FloatingActionButton(
              onPressed: () =>
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddEditEntryScreen(),
                    ),
                  ).then((result) {
                    debugPrint(
                      '=== NAVIGATION DEBUG: Returned from AddEditEntryScreen (new entry) with result: $result ===',
                    );
                    _loadEntries();
                  }),
              backgroundColor: Colors.indigo,
              elevation: 6,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// Move AddEditEntryScreen here or import it
class AddEditEntryScreen extends StatefulWidget {
  const AddEditEntryScreen({super.key});

  @override
  State<AddEditEntryScreen> createState() => _AddEditEntryScreenState();
}

class _AddEditEntryScreenState extends State<AddEditEntryScreen> {
  final KdbxService _kdbxService = KdbxService();
  final TextEditingController titleController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController urlController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController tagsController = TextEditingController();

  KdbxEntry? editingEntry;
  bool isEditing = false;
  bool isLoading = false;
  bool isPasswordVisible = false;
  Set<String> entryTags = {};
  List<String> predefinedTags = [
    'work',
    'personal',
    'development',
    'family',
    'banking',
    'social',
    'gaming',
    'shopping',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final entry = ModalRoute.of(context)?.settings.arguments as KdbxEntry?;
    if (entry != null && !isEditing) {
      editingEntry = entry;
      isEditing = true;
      _populateFields();
    }
  }

  void _populateFields() {
    if (editingEntry != null) {
      titleController.text = editingEntry!.title;
      usernameController.text = editingEntry!.username;
      passwordController.text = editingEntry!.password;
      urlController.text = editingEntry!.url;
      notesController.text = editingEntry!.notes;

      // Load tags from the entry
      entryTags = _getEntryTags(editingEntry!);
      tagsController.text = entryTags.join(', ');
    }
  }

  Set<String> _getEntryTags(KdbxEntry entry) {
    final tagsString = entry.getString(KdbxKey('Tags'))?.getText() ?? '';
    if (tagsString.isEmpty) return {};
    return tagsString
        .toLowerCase()
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
  }

  void _toggleQuickTag(String tag) {
    setState(() {
      final lowerTag = tag.toLowerCase();
      if (entryTags.contains(lowerTag)) {
        entryTags.remove(lowerTag);
      } else {
        entryTags.add(lowerTag);
      }
      tagsController.text = entryTags.join(', ');
    });
  }

  Future<void> _saveEntry() async {
    if (titleController.text.isEmpty ||
        usernameController.text.isEmpty ||
        passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() => isLoading = true);

    bool success;
    final tagsString = entryTags.isNotEmpty ? entryTags.join(',') : null;

    if (isEditing && editingEntry != null) {
      success = await _kdbxService.updateEntry(
        entry: editingEntry!,
        title: titleController.text,
        username: usernameController.text,
        password: passwordController.text,
        url: urlController.text.isEmpty ? null : urlController.text,
        notes: notesController.text.isEmpty ? null : notesController.text,
        tags: tagsString,
      );
    } else {
      success = await _kdbxService.addEntry(
        title: titleController.text,
        username: usernameController.text,
        password: passwordController.text,
        url: urlController.text.isEmpty ? null : urlController.text,
        notes: notesController.text.isEmpty ? null : notesController.text,
        tags: tagsString,
      );
    }

    setState(() => isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Entry updated successfully'
                : 'Entry added successfully',
          ),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing ? 'Failed to update entry' : 'Failed to add entry',
          ),
        ),
      );
    }
  }

  void _copyPasswordToClipboard() {
    if (passwordController.text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: passwordController.text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password copied to clipboard')),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No password to copy')));
    }
  }

  void _showPasswordGeneratorDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return PasswordGeneratorDialog(
          onPasswordGenerated: (generatedPassword) {
            setState(() {
              passwordController.text = generatedPassword;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Entry' : 'Add Entry'),
        elevation: 2,
        centerTitle: true,
        backgroundColor: Colors.indigo,
        actions: [
          if (isEditing && editingEntry != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Entry'),
                    content: const Text(
                      'Are you sure you want to delete this entry?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  setState(() => isLoading = true);
                  debugPrint(
                    '=== DELETE DEBUG: Attempting to delete entry: ${editingEntry!.title} ===',
                  );

                  final success = await _kdbxService.deleteEntry(editingEntry!);

                  setState(() => isLoading = false);

                  if (success) {
                    debugPrint(
                      '=== DELETE DEBUG: Entry deleted successfully ===',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Entry deleted successfully'),
                      ),
                    );
                    Navigator.pop(
                      context,
                      true,
                    ); // Return true to indicate deletion
                  } else {
                    debugPrint('=== DELETE DEBUG: Failed to delete entry ===');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to delete entry')),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title*',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username*',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password*',
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: _copyPasswordToClipboard,
                              tooltip: 'Copy Password',
                            ),
                            IconButton(
                              icon: Icon(
                                isPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  isPasswordVisible = !isPasswordVisible;
                                });
                              },
                              tooltip: isPasswordVisible
                                  ? 'Hide Password'
                                  : 'Show Password',
                            ),
                          ],
                        ),
                      ),
                      obscureText: !isPasswordVisible,
                    ),
                    // Show generate password option only when creating new entry
                    if (!isEditing) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showPasswordGeneratorDialog,
                              icon: const Icon(Icons.auto_fix_high),
                              label: const Text('Generate Secure Password'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo,
                                side: const BorderSide(color: Colors.indigo),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'URL (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    // Tags input field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: tagsController,
                          decoration: const InputDecoration(
                            labelText: 'Tags (Optional)',
                            border: OutlineInputBorder(),
                            hintText:
                                'Separate tags with commas (e.g., work, personal)',
                            suffixIcon: Icon(Icons.local_offer),
                          ),
                          onChanged: (value) {
                            setState(() {
                              entryTags = value
                                  .toLowerCase()
                                  .split(',')
                                  .map((tag) => tag.trim())
                                  .where((tag) => tag.isNotEmpty)
                                  .toSet();
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        // Quick tag buttons
                        if (predefinedTags.isNotEmpty) ...[
                          Text(
                            'Quick Tags:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: predefinedTags.map((tag) {
                              final isSelected = entryTags.contains(
                                tag.toLowerCase(),
                              );
                              return GestureDetector(
                                onTap: () => _toggleQuickTag(tag),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.indigo.shade100
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.indigo
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected
                                          ? Colors.indigo.shade700
                                          : Colors.grey[700],
                                      fontWeight: isSelected
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveEntry,
                        child: Text(
                          isEditing ? 'Update Entry' : 'Save Entry',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    urlController.dispose();
    notesController.dispose();
    super.dispose();
  }
}

class PasswordGeneratorDialog extends StatefulWidget {
  final Function(String) onPasswordGenerated;

  const PasswordGeneratorDialog({super.key, required this.onPasswordGenerated});

  @override
  State<PasswordGeneratorDialog> createState() =>
      _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  double _passwordLength = 16.0;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  bool _excludeSimilar = false;
  bool _useWordBased = false;
  int _wordCount = 3;
  String _requiredCharacters = '';
  String _generatedPassword = '';

  final TextEditingController _requiredCharsController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _generatePassword();
  }

  void _generatePassword() {
    final random = Random.secure();

    debugPrint('=== PASSWORD DEBUG: _useWordBased = $_useWordBased ===');

    if (_useWordBased) {
      debugPrint('=== PASSWORD DEBUG: Generating word-based password ===');
      _generateWordBasedPassword(random);
    } else {
      debugPrint('=== PASSWORD DEBUG: Generating random password ===');
      _generateRandomPassword(random);
    }
  }

  void _generateWordBasedPassword(Random random) {
    // Common memorable words for password generation
    const words = [
      'apple',
      'brave',
      'cloud',
      'dance',
      'eagle',
      'flame',
      'green',
      'happy',
      'inbox',
      'juice',
      'knife',
      'light',
      'mouse',
      'night',
      'ocean',
      'phone',
      'quick',
      'river',
      'storm',
      'table',
      'ultra',
      'voice',
      'water',
      'extra',
      'youth',
      'zebra',
      'bread',
      'chair',
      'dream',
      'frost',
      'ghost',
      'heart',
      'image',
      'judge',
      'kayak',
      'lemon',
      'magic',
      'ninja',
      'orbit',
      'peace',
      'quest',
      'robot',
      'smile',
      'tiger',
      'unity',
      'virus',
      'whale',
      'xenon',
      'young',
      'zesty',
      'block',
      'craft',
      'drive',
      'flash',
      'giant',
      'house',
      'index',
      'jewel',
      'kings',
      'laser',
      'maple',
      'novel',
      'onion',
      'piano',
    ];

    List<String> selectedWords = [];
    List<String> availableWords = List.from(words);

    // Select random words
    debugPrint('=== PASSWORD DEBUG: Selecting $_wordCount words ===');
    for (int i = 0; i < _wordCount && availableWords.isNotEmpty; i++) {
      int index = random.nextInt(availableWords.length);
      String word = availableWords.removeAt(index);
      debugPrint('=== PASSWORD DEBUG: Selected word: $word ===');

      // Capitalize first letter if uppercase is enabled
      if (_includeUppercase && i == 0) {
        word = word[0].toUpperCase() + word.substring(1);
      } else if (_includeUppercase && random.nextBool()) {
        word = word[0].toUpperCase() + word.substring(1);
      }
      debugPrint('=== PASSWORD DEBUG: Final word: $word ===');

      selectedWords.add(word);
    }

    debugPrint('=== PASSWORD DEBUG: Selected words: $selectedWords ===');

    // Create base password from words
    String basePassword = selectedWords.join('');
    debugPrint(
      '=== PASSWORD DEBUG: Base password from words: $basePassword ===',
    );

    // Collect additional characters to add
    List<String> additionalChars = [];

    // Add numbers if enabled
    if (_includeNumbers) {
      int numberCount = random.nextInt(3) + 1; // 1-3 numbers
      for (int i = 0; i < numberCount; i++) {
        additionalChars.add(random.nextInt(10).toString());
      }
      debugPrint(
        '=== PASSWORD DEBUG: Added numbers: ${additionalChars.where((c) => RegExp(r'\d').hasMatch(c)).toList()} ===',
      );
    }

    // Add symbols if enabled
    if (_includeSymbols) {
      const symbols = '!@#\$%^&*';
      int symbolCount = random.nextInt(2) + 1; // 1-2 symbols
      for (int i = 0; i < symbolCount; i++) {
        additionalChars.add(symbols[random.nextInt(symbols.length)]);
      }
      debugPrint(
        '=== PASSWORD DEBUG: Added symbols: ${additionalChars.where((c) => RegExp(r'[!@#\$%^&*]').hasMatch(c)).toList()} ===',
      );
    }

    // Add required characters
    if (_requiredCharacters.isNotEmpty) {
      additionalChars.addAll(_requiredCharacters.split(''));
      debugPrint(
        '=== PASSWORD DEBUG: Added required chars: $_requiredCharacters ===',
      );
    }

    // Create final password by keeping words intact and adding extras at strategic positions
    String finalPassword = basePassword;

    if (additionalChars.isNotEmpty) {
      // Simple approach: add all additional characters at the end or beginning
      String additionalString = additionalChars.join('');

      // Randomly decide whether to add at beginning, end, or split between
      int strategy = random.nextInt(3);

      if (strategy == 0) {
        // Add all at the beginning
        finalPassword = additionalString + finalPassword;
        debugPrint(
          '=== PASSWORD DEBUG: Added "$additionalString" at beginning ===',
        );
      } else if (strategy == 1) {
        // Add all at the end
        finalPassword = finalPassword + additionalString;
        debugPrint('=== PASSWORD DEBUG: Added "$additionalString" at end ===');
      } else {
        // Split: some at beginning, some at end
        int splitPoint = additionalChars.length ~/ 2;
        String beginPart = additionalChars.take(splitPoint).join('');
        String endPart = additionalChars.skip(splitPoint).join('');
        finalPassword = beginPart + finalPassword + endPart;
        debugPrint(
          '=== PASSWORD DEBUG: Added "$beginPart" at beginning and "$endPart" at end ===',
        );
      }
    }

    debugPrint(
      '=== PASSWORD DEBUG: Final word-based password: $finalPassword ===',
    );

    setState(() {
      _generatedPassword = finalPassword;
    });
  }

  void _generateRandomPassword(Random random) {
    const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
    const similar = 'il1Lo0O';

    String charset = '';

    if (_includeUppercase) charset += uppercase;
    if (_includeLowercase) charset += lowercase;
    if (_includeNumbers) charset += numbers;
    if (_includeSymbols) charset += symbols;

    if (_excludeSimilar) {
      for (String char in similar.split('')) {
        charset = charset.replaceAll(char, '');
      }
    }

    if (charset.isEmpty) {
      setState(() {
        _generatedPassword = 'Error: No character types selected';
      });
      return;
    }

    String password = '';

    // First, ensure required characters are included
    if (_requiredCharacters.isNotEmpty) {
      password += _requiredCharacters;
    }

    // Generate remaining characters
    int remainingLength = _passwordLength.toInt() - password.length;
    if (remainingLength > 0) {
      for (int i = 0; i < remainingLength; i++) {
        password += charset[random.nextInt(charset.length)];
      }
    }

    // Shuffle the password to randomize position of required characters
    List<String> passwordChars = password.split('');
    passwordChars.shuffle(random);

    setState(() {
      _generatedPassword = passwordChars.join('');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.indigo.shade50, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.indigo.shade400,
                          Colors.indigo.shade600,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_fix_high,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Password Generator',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Generated Password Display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _generatedPassword,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _generatedPassword),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password copied to clipboard'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: 'Copy Password',
                        ),
                        IconButton(
                          onPressed: _generatePassword,
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Generate New Password',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Password Length Slider (only for random passwords)
              if (!_useWordBased) ...[
                Row(
                  children: [
                    const Text(
                      'Length:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Slider(
                        value: _passwordLength,
                        min: 8.0,
                        max: 32.0,
                        divisions: 24,
                        label: _passwordLength.round().toString(),
                        onChanged: (value) {
                          setState(() {
                            _passwordLength = value;
                          });
                          _generatePassword();
                        },
                      ),
                    ),
                    Text(
                      _passwordLength.round().toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Required Characters Input
              TextField(
                controller: _requiredCharsController,
                decoration: InputDecoration(
                  labelText: 'Required Characters',
                  hintText: 'Characters that must be included',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.key),
                ),
                onChanged: (value) {
                  setState(() {
                    _requiredCharacters = value;
                  });
                  _generatePassword();
                },
              ),
              const SizedBox(height: 12),

              // Password Type Selection
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildRadioOption(
                            'Random Characters',
                            'Strong but hard to remember',
                            !_useWordBased,
                            () {
                              setState(() {
                                _useWordBased = false;
                              });
                              _generatePassword();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRadioOption(
                            'Memorable Words',
                            'Easier to remember, still secure',
                            _useWordBased,
                            () {
                              setState(() {
                                _useWordBased = true;
                              });
                              _generatePassword();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Options based on password type
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_useWordBased) ...[
                    // Word-based options
                    Row(
                      children: [
                        const Text(
                          'Word Count:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Slider(
                            value: _wordCount.toDouble(),
                            min: 2.0,
                            max: 5.0,
                            divisions: 3,
                            label: _wordCount.toString(),
                            onChanged: (value) {
                              setState(() {
                                _wordCount = value.round();
                              });
                              _generatePassword();
                            },
                          ),
                        ),
                        Text(
                          _wordCount.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildCheckboxOption(
                      'Add Numbers (123...)',
                      _includeNumbers,
                      (value) {
                        setState(() {
                          _includeNumbers = value;
                        });
                        _generatePassword();
                      },
                    ),
                    _buildCheckboxOption(
                      'Add Symbols (!@#...)',
                      _includeSymbols,
                      (value) {
                        setState(() {
                          _includeSymbols = value;
                        });
                        _generatePassword();
                      },
                    ),
                    _buildCheckboxOption(
                      'Capitalize Words',
                      _includeUppercase,
                      (value) {
                        setState(() {
                          _includeUppercase = value;
                        });
                        _generatePassword();
                      },
                    ),
                  ] else ...[
                    // Random character options
                    _buildCheckboxOption(
                      'Include Uppercase (A-Z)',
                      _includeUppercase,
                      (value) {
                        setState(() {
                          _includeUppercase = value;
                        });
                        _generatePassword();
                      },
                    ),
                    _buildCheckboxOption(
                      'Include Lowercase (a-z)',
                      _includeLowercase,
                      (value) {
                        setState(() {
                          _includeLowercase = value;
                        });
                        _generatePassword();
                      },
                    ),
                    _buildCheckboxOption(
                      'Include Numbers (0-9)',
                      _includeNumbers,
                      (value) {
                        setState(() {
                          _includeNumbers = value;
                        });
                        _generatePassword();
                      },
                    ),
                    _buildCheckboxOption(
                      'Include Symbols (!@#\$...)',
                      _includeSymbols,
                      (value) {
                        setState(() {
                          _includeSymbols = value;
                        });
                        _generatePassword();
                      },
                    ),
                    _buildCheckboxOption(
                      'Exclude Similar Characters (il1Lo0O)',
                      _excludeSimilar,
                      (value) {
                        setState(() {
                          _excludeSimilar = value;
                        });
                        _generatePassword();
                      },
                    ),
                  ],
                ],
              ),

              // Action Buttons
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade400,
                            Colors.indigo.shade600,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onPasswordGenerated(_generatedPassword);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Use Password',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxOption(
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return CheckboxListTile(
      title: Text(title, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: (newValue) => onChanged(newValue ?? false),
      activeColor: Colors.indigo,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildRadioOption(
    String title,
    String subtitle,
    bool value,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? Colors.indigo : Colors.grey.shade300,
            width: value ? 2 : 1,
          ),
          color: value ? Colors.indigo.shade50 : Colors.white,
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: value,
              onChanged: (_) => onTap(),
              activeColor: Colors.indigo,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: value ? Colors.indigo.shade700 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: value
                          ? Colors.indigo.shade600
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requiredCharsController.dispose();
    super.dispose();
  }
}
