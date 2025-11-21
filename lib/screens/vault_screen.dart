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
        Theme,
        Divider;
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:kdbx/kdbx.dart';
import 'package:file_picker/file_picker.dart';
import '../services/kdbx_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final KdbxService _kdbxService = KdbxService();
  final TextEditingController _searchController = TextEditingController();
  List<KdbxEntry> entries = [];
  List<KdbxEntry> filteredEntries = [];
  Set<String> availableTags = {};
  String? selectedTag;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterEntries);
    _initializeVault();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeVault() async {
    if (!_kdbxService.isAccountSelected) {
      Navigator.pop(context);
      return;
    }
    await _initializeAccountDatabase();
  }

  Future<void> _initializeAccountDatabase() async {
    setState(() => isLoading = true);

    try {
      if (_kdbxService.isDatabaseLoaded) {
        _loadEntries();
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _loadEntries() {
    setState(() {
      entries = _kdbxService.getAllEntries();
      _extractTags();
      _filterEntries();
    });
  }

  void _extractTags() {
    final tags = <String>{};
    for (final entry in entries) {
      final entryTags = _getEntryTags(entry);
      tags.addAll(entryTags);
    }
    availableTags = tags;
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
    setState(() {
      filteredEntries = entries.where((entry) {
        final title =
            entry.getString(KdbxKeyCommon.TITLE)?.getText()?.toLowerCase() ??
            '';

        // Filter by search query
        final matchesSearch = query.isEmpty || title.contains(query);

        // Filter by selected tag
        final matchesTag =
            selectedTag == null || _getEntryTags(entry).contains(selectedTag);

        return matchesSearch && matchesTag;
      }).toList();
    });
  }

  Future<void> _showAddPasswordDialog() async {
    final titleController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final urlController = TextEditingController();
    final notesController = TextEditingController();
    final tagsController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Password'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                FormField<String>(
                  key: FormKey<String>('title_field'),
                  label: const Text('Title'),
                  child: TextField(controller: titleController),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('username_field'),
                  label: const Text('Username/Email'),
                  child: TextField(controller: usernameController),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('password_field'),
                  label: const Text('Password'),
                  child: TextField(
                    controller: passwordController,
                    obscureText: true,
                  ),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('url_field'),
                  label: const Text('URL (Optional)'),
                  child: TextField(controller: urlController),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('tags_field'),
                  label: const Text('Tags (Optional, comma-separated)'),
                  child: TextField(controller: tagsController),
                ),
                if (availableTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: availableTags.map((tag) {
                      return SizedBox(
                        height: 28,
                        child: FilterChip(
                          label: Text(
                            tag,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: false,
                          onSelected: (selected) {
                            final currentTags = tagsController.text.trim();
                            final tagsList = currentTags.isEmpty
                                ? []
                                : currentTags
                                      .split(',')
                                      .map((t) => t.trim())
                                      .toList();

                            if (!tagsList.contains(tag)) {
                              tagsList.add(tag);
                              tagsController.text = tagsList.join(', ');
                              setDialogState(() {});
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('notes_field'),
                  label: const Text('Notes (Optional)'),
                  child: TextField(controller: notesController),
                ),
              ],
            ),
          ),
          actions: [
            SecondaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final username = usernameController.text.trim();
                final password = passwordController.text.trim();

                if (title.isEmpty || username.isEmpty || password.isEmpty) {
                  return;
                }

                await _kdbxService.addEntry(
                  title: title,
                  username: username,
                  password: password,
                  url: urlController.text.trim(),
                  notes: notesController.text.trim(),
                  tags: tagsController.text.trim(),
                );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _loadEntries();
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditPasswordDialog(KdbxEntry entry) async {
    final titleController = TextEditingController(
      text: entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '',
    );
    final usernameController = TextEditingController(
      text: entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '',
    );
    final passwordController = TextEditingController(
      text: entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '',
    );
    final urlController = TextEditingController(
      text: entry.getString(KdbxKeyCommon.URL)?.getText() ?? '',
    );
    final tagsController = TextEditingController(
      text: entry.getString(KdbxKey('Tags'))?.getText() ?? '',
    );
    final notesController = TextEditingController(
      text: entry.getString(KdbxKey('Notes'))?.getText() ?? '',
    );

    bool obscurePassword = true;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Password'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                FormField<String>(
                  key: FormKey<String>('title_field'),
                  label: const Text('Title'),
                  child: TextField(controller: titleController),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('username_field'),
                  label: const Text('Username/Email'),
                  child: TextField(controller: usernameController),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('password_field'),
                  label: const Text('Password'),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 20,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        variance: ButtonVariance.ghost,
                        density: ButtonDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: passwordController.text),
                          );
                          _showCopiedToast(context);
                        },
                        variance: ButtonVariance.ghost,
                        density: ButtonDensity.compact,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('url_field'),
                  label: const Text('URL (Optional)'),
                  child: TextField(controller: urlController),
                ),
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('tags_field'),
                  label: const Text('Tags (Optional, comma-separated)'),
                  child: TextField(controller: tagsController),
                ),
                if (availableTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: availableTags.map((tag) {
                      return SizedBox(
                        height: 28,
                        child: FilterChip(
                          label: Text(
                            tag,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: false,
                          onSelected: (selected) {
                            final currentTags = tagsController.text.trim();
                            final tagsList = currentTags.isEmpty
                                ? []
                                : currentTags
                                      .split(',')
                                      .map((t) => t.trim())
                                      .toList();

                            if (!tagsList.contains(tag)) {
                              tagsList.add(tag);
                              tagsController.text = tagsList.join(', ');
                              setDialogState(() {});
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                FormField<String>(
                  key: FormKey<String>('notes_field'),
                  label: const Text('Notes (Optional)'),
                  child: TextField(controller: notesController),
                ),
              ],
            ),
          ),
          actions: [
            SecondaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final username = usernameController.text.trim();
                final password = passwordController.text.trim();

                if (title.isEmpty || username.isEmpty || password.isEmpty) {
                  return;
                }

                await _kdbxService.updateEntry(
                  entry: entry,
                  title: title,
                  username: username,
                  password: password,
                  url: urlController.text.trim(),
                  notes: notesController.text.trim(),
                  tags: tagsController.text.trim(),
                );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _loadEntries();
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEntry(KdbxEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Password'),
        content: Text(
          'Are you sure you want to delete "${entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? 'this entry'}"?',
        ),
        actions: [
          SecondaryButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _kdbxService.deleteEntry(entry);
      _loadEntries();
    }
  }

  void _showCopiedToast(BuildContext context) {
    final theme = Theme.of(context);
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 50,
        left: MediaQuery.of(context).size.width * 0.5 - 150,
        width: 300,
        child: Material(
          color: theme.colorScheme.popover,
          borderRadius: BorderRadius.circular(8),
          surfaceTintColor: theme.colorScheme.popoverForeground,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.popover,
              border: Border.all(color: theme.colorScheme.border, width: 1),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.foreground.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Password copied to clipboard',
                    style: TextStyle(
                      color: theme.colorScheme.popoverForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  Future<void> _exportCsv() async {
    setState(() => isLoading = true);
    
    try {
      final exportPath = await _kdbxService.exportCsvPasswords();
      
      if (exportPath != null && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('CSV Exported'),
            content: Text('Passwords exported successfully to:\n$exportPath'),
            actions: [
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Failed'),
            content: const Text('Failed to export passwords to CSV.'),
            actions: [
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Error'),
            content: Text('Error: $e'),
            actions: [
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _importCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      
      setState(() => isLoading = true);

      final importResult = await _kdbxService.importCsvDatabase(
        file.path,
        file.bytes,
        false, // Don't replace existing, merge instead
        null, // No master password needed, database already loaded
      );

      setState(() => isLoading = false);

      if (importResult != null) {
        _loadEntries();
        final imported = importResult['imported'] ?? 0;
        final skipped = importResult['skipped'] ?? 0;
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Import Complete'),
              content: Text(
                'Import Summary:\n'
                '✓ Imported: $imported password${imported != 1 ? 's' : ''}\n'
                '${skipped > 0 ? '⊘ Skipped (duplicates): $skipped' : ''}',
              ),
              actions: [
                PrimaryButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Failed'),
            content: const Text('Failed to import passwords from CSV. Please check the file format.'),
            actions: [
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Error'),
            content: Text('Error: $e'),
            actions: [
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoading) {
      return const Scaffold(child: Center(child: CircularProgressIndicator()));
    }

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
          title: Text(
            _kdbxService.currentAccount != null
                ? "${_kdbxService.currentAccount!.name}'s Vault"
                : 'Password Vault',
          ),
          trailing: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'import':
                    _importCsv();
                    break;
                  case 'export':
                    _exportCsv();
                    break;
                }
              },
              itemBuilder: (context) {
                final theme = Theme.of(context);
                return [
                  PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(
                          Icons.file_download,
                          size: 20,
                          color: theme.colorScheme.foreground,
                        ),
                        const SizedBox(width: 12),
                        const Text('Import CSV'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(
                          Icons.file_upload,
                          size: 20,
                          color: theme.colorScheme.foreground,
                        ),
                        const SizedBox(width: 12),
                        const Text('Export CSV'),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${filteredEntries.length} Passwords',
                    style: theme.typography.large,
                  ),
                ),
                PrimaryButton(
                  onPressed: _showAddPasswordDialog,
                  child: const Text('Add Password'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _searchController)),
              ],
            ),
          ),
          if (availableTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: selectedTag == null,
                      onSelected: (selected) {
                        setState(() {
                          selectedTag = null;
                          _filterEntries();
                        });
                      },
                    ),
                  ),
                  ...availableTags.map((tag) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(tag),
                        selected: selectedTag == tag,
                        onSelected: (selected) {
                          setState(() {
                            selectedTag = selected ? tag : null;
                            _filterEntries();
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(),
          Expanded(
            child: filteredEntries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          entries.isEmpty
                              ? 'No passwords yet'
                              : 'No passwords found',
                          style: theme.typography.large,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entries.isEmpty
                              ? 'Add your first password to get started'
                              : 'Try a different search term',
                          style: theme.typography.small.copyWith(
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      final title =
                          entry.getString(KdbxKeyCommon.TITLE)?.getText() ??
                          'Untitled';
                      final username =
                          entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ??
                          '';
                      final url =
                          entry.getString(KdbxKeyCommon.URL)?.getText() ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Card(
                          child: InkWell(
                            onTap: () => _showEditPasswordDialog(entry),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (username.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          const Icon(Icons.person, size: 11),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              username,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                        if (url.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          const Icon(Icons.link, size: 11),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              url,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 18),
                                    onPressed: () => _deleteEntry(entry),
                                    variance: ButtonVariance.ghost,
                                    density: ButtonDensity.compact,
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
      ),
    );
  }
}
