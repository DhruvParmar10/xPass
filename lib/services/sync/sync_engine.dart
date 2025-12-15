import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kdbx/kdbx.dart';
import 'package:uuid/uuid.dart';
import '../../models/sync/sync_models.dart';
import '../kdbx_service.dart';

/// Represents a single entry for sync comparison
class SyncEntryData {
  final String uuid;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String tags;
  final DateTime lastModified;
  final bool isDeleted;

  const SyncEntryData({
    required this.uuid,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    required this.tags,
    required this.lastModified,
    this.isDeleted = false,
  });

  factory SyncEntryData.fromKdbxEntry(KdbxEntry entry) {
    return SyncEntryData(
      uuid: entry.uuid.toString(),
      title: entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '',
      username: entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '',
      password: entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '',
      url: entry.getString(KdbxKeyCommon.URL)?.getText() ?? '',
      notes: entry.getString(KdbxKey('Notes'))?.getText() ?? '',
      tags: entry.getString(KdbxKey('Tags'))?.getText() ?? '',
      lastModified: (entry.times.lastModificationTime.get() ?? DateTime.now())
          .toUtc(),
      isDeleted: entry.getString(KdbxKey('Deleted'))?.getText() == 'true',
    );
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
    'tags': tags,
    'lastModified': lastModified.toIso8601String(),
    'isDeleted': isDeleted,
  };

  factory SyncEntryData.fromJson(Map<String, dynamic> json) {
    return SyncEntryData(
      uuid: json['uuid'] as String,
      title: json['title'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      url: json['url'] as String,
      notes: json['notes'] as String? ?? '',
      tags: json['tags'] as String? ?? '',
      lastModified: DateTime.parse(json['lastModified'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  /// Get a unique identifier based on account name (title + username)
  String get accountKey =>
      '${title.toLowerCase().trim()}:${username.toLowerCase().trim()}';

  /// Check if this entry matches another by account name
  bool matchesAccount(SyncEntryData other) => accountKey == other.accountKey;

  /// Check if this entry is newer than another
  bool isNewerThan(SyncEntryData other) =>
      lastModified.isAfter(other.lastModified);
}

/// Result of comparing two vaults for sync
class SyncComparison {
  /// Entries to add locally (exist only on remote)
  final List<SyncEntryData> toAddLocally;

  /// Entries to add remotely (exist only locally)
  final List<SyncEntryData> toAddRemotely;

  /// Entries to update locally (remote is newer)
  final List<SyncEntryData> toUpdateLocally;

  /// Entries to update remotely (local is newer)
  final List<SyncEntryData> toUpdateRemotely;

  /// Entries with conflicts (same timestamp, different data)
  final List<SyncConflict> conflicts;

  /// Entries to delete locally (deleted on remote)
  final List<SyncEntryData> toDeleteLocally;

  /// Entries to delete remotely (deleted locally)
  final List<SyncEntryData> toDeleteRemotely;

  const SyncComparison({
    this.toAddLocally = const [],
    this.toAddRemotely = const [],
    this.toUpdateLocally = const [],
    this.toUpdateRemotely = const [],
    this.conflicts = const [],
    this.toDeleteLocally = const [],
    this.toDeleteRemotely = const [],
  });

  /// Check if there are any changes to sync
  bool get hasChanges =>
      toAddLocally.isNotEmpty ||
      toAddRemotely.isNotEmpty ||
      toUpdateLocally.isNotEmpty ||
      toUpdateRemotely.isNotEmpty ||
      toDeleteLocally.isNotEmpty ||
      toDeleteRemotely.isNotEmpty;

  /// Total number of changes
  int get totalChanges =>
      toAddLocally.length +
      toAddRemotely.length +
      toUpdateLocally.length +
      toUpdateRemotely.length +
      toDeleteLocally.length +
      toDeleteRemotely.length;
}

/// Represents a sync conflict
class SyncConflict {
  final SyncEntryData localEntry;
  final SyncEntryData remoteEntry;
  SyncConflictResolution resolution;

  SyncConflict({
    required this.localEntry,
    required this.remoteEntry,
    this.resolution = SyncConflictResolution.useNewer,
  });

  /// Get the winning entry based on resolution
  SyncEntryData get resolvedEntry {
    switch (resolution) {
      case SyncConflictResolution.useLocal:
        return localEntry;
      case SyncConflictResolution.useRemote:
        return remoteEntry;
      case SyncConflictResolution.useNewer:
        return localEntry.isNewerThan(remoteEntry) ? localEntry : remoteEntry;
    }
  }
}

/// Conflict resolution strategies
enum SyncConflictResolution { useLocal, useRemote, useNewer }

/// Sync protocol message types
enum SyncMessageType {
  hello, // Initial handshake
  requestSync, // Request sync data
  syncData, // Vault data for sync
  syncChanges, // Changes to apply
  syncComplete, // Sync completed
  error, // Error occurred
}

/// Message for sync protocol
class SyncMessage {
  final SyncMessageType type;
  final String deviceId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  SyncMessage({
    required this.type,
    required this.deviceId,
    this.data = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'deviceId': deviceId,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory SyncMessage.fromJson(Map<String, dynamic> json) {
    return SyncMessage(
      type: SyncMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SyncMessageType.error,
      ),
      deviceId: json['deviceId'] as String,
      data: json['data'] as Map<String, dynamic>? ?? {},
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory SyncMessage.fromJsonString(String jsonString) {
    return SyncMessage.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}

/// Service for handling vault synchronization between devices
class SyncEngine extends ChangeNotifier {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final KdbxService _kdbxService = KdbxService();

  /// Current sync progress
  double _progress = 0;
  double get progress => _progress;

  /// Current sync phase description
  String _phase = '';
  String get phase => _phase;

  /// Ensure vault is loaded for sync operations
  /// Returns true if vault is ready for sync
  Future<bool> ensureVaultReady() async {
    if (_kdbxService.isVaultLoaded) {
      return true;
    }
    print('SyncEngine: Vault not loaded, attempting auto-load...');
    return await _kdbxService.ensureVaultLoadedForSync();
  }

  /// Extract all entries from the current vault for sync
  List<SyncEntryData> extractVaultData() {
    print('=== SYNC DEBUG: extractVaultData ===');
    print('=== SYNC DEBUG: isVaultLoaded=${_kdbxService.isVaultLoaded} ===');
    if (!_kdbxService.isVaultLoaded) {
      print(
        '=== SYNC DEBUG: WARNING - Vault not loaded! Returning empty list ===',
      );
      return [];
    }
    final entries = _kdbxService.getAllEntries();
    print('=== SYNC DEBUG: Got ${entries.length} entries from kdbxService ===');
    final result = entries.map((e) => SyncEntryData.fromKdbxEntry(e)).toList();
    for (final e in result) {
      print('  - ${e.title} (${e.username}) key=${e.accountKey}');
    }
    return result;
  }

  /// Compare local and remote vault data
  SyncComparison compareVaults(
    List<SyncEntryData> localEntries,
    List<SyncEntryData> remoteEntries,
  ) {
    print('=== SYNC DEBUG: compareVaults ===');
    print('Local entries: ${localEntries.length}');
    print('Remote entries: ${remoteEntries.length}');

    final toAddLocally = <SyncEntryData>[];
    final toAddRemotely = <SyncEntryData>[];
    final toUpdateLocally = <SyncEntryData>[];
    final toUpdateRemotely = <SyncEntryData>[];
    final conflicts = <SyncConflict>[];
    final toDeleteLocally = <SyncEntryData>[];
    final toDeleteRemotely = <SyncEntryData>[];

    // Create maps for quick lookup by account key
    final localByKey = <String, SyncEntryData>{};
    final remoteByKey = <String, SyncEntryData>{};

    for (final entry in localEntries) {
      if (!entry.isDeleted) {
        localByKey[entry.accountKey] = entry;
      }
    }

    for (final entry in remoteEntries) {
      if (!entry.isDeleted) {
        remoteByKey[entry.accountKey] = entry;
      }
    }

    // Find entries that exist only on remote (need to add locally)
    for (final key in remoteByKey.keys) {
      if (!localByKey.containsKey(key)) {
        toAddLocally.add(remoteByKey[key]!);
      }
    }

    // Find entries that exist only locally (need to add remotely)
    for (final key in localByKey.keys) {
      if (!remoteByKey.containsKey(key)) {
        toAddRemotely.add(localByKey[key]!);
      }
    }

    // Compare entries that exist on both
    for (final key in localByKey.keys) {
      if (remoteByKey.containsKey(key)) {
        final localEntry = localByKey[key]!;
        final remoteEntry = remoteByKey[key]!;

        // Check if content is the same
        if (_entriesEqual(localEntry, remoteEntry)) {
          // No change needed
          continue;
        }

        // Determine which is newer
        if (localEntry.isNewerThan(remoteEntry)) {
          toUpdateRemotely.add(localEntry);
        } else if (remoteEntry.isNewerThan(localEntry)) {
          toUpdateLocally.add(remoteEntry);
        } else {
          // Same timestamp but different content - conflict
          conflicts.add(
            SyncConflict(localEntry: localEntry, remoteEntry: remoteEntry),
          );
        }
      }
    }

    // Handle deleted entries
    for (final entry in localEntries) {
      if (entry.isDeleted && remoteByKey.containsKey(entry.accountKey)) {
        toDeleteRemotely.add(entry);
      }
    }

    for (final entry in remoteEntries) {
      if (entry.isDeleted && localByKey.containsKey(entry.accountKey)) {
        toDeleteLocally.add(entry);
      }
    }

    print('=== SYNC DEBUG: Comparison result ===');
    print('toAddLocally: ${toAddLocally.length}');
    print('toAddRemotely: ${toAddRemotely.length}');
    print('toUpdateLocally: ${toUpdateLocally.length}');
    print('toUpdateRemotely: ${toUpdateRemotely.length}');
    print('conflicts: ${conflicts.length}');

    return SyncComparison(
      toAddLocally: toAddLocally,
      toAddRemotely: toAddRemotely,
      toUpdateLocally: toUpdateLocally,
      toUpdateRemotely: toUpdateRemotely,
      conflicts: conflicts,
      toDeleteLocally: toDeleteLocally,
      toDeleteRemotely: toDeleteRemotely,
    );
  }

  /// Check if two entries have the same content
  bool _entriesEqual(SyncEntryData a, SyncEntryData b) {
    return a.title == b.title &&
        a.username == b.username &&
        a.password == b.password &&
        a.url == b.url &&
        a.notes == b.notes &&
        a.tags == b.tags;
  }

  /// Apply incoming changes to the local vault
  Future<SyncLogEntry> applyRemoteChanges(
    String deviceId,
    String deviceName,
    String accountName,
    List<SyncEntryData> toAdd,
    List<SyncEntryData> toUpdate,
    List<SyncEntryData> toDelete,
  ) async {
    final syncedItems = <SyncedItem>[];
    var success = true;

    print('=== SYNC DEBUG: applyRemoteChanges ===');
    print('toAdd: ${toAdd.length} entries');
    print('toUpdate: ${toUpdate.length} entries');
    print('toDelete: ${toDelete.length} entries');
    for (final e in toAdd) {
      print('  - Adding: ${e.title} (${e.username})');
    }

    _phase = 'Applying changes...';
    _progress = 0;
    notifyListeners();

    final total = toAdd.length + toUpdate.length + toDelete.length;
    var processed = 0;

    if (total == 0) {
      print('=== SYNC DEBUG: No changes to apply ===');
      return SyncLogEntry(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        deviceId: deviceId,
        deviceName: deviceName,
        accountName: accountName,
        items: [],
        success: true,
      );
    }

    try {
      // Add new entries
      for (final entry in toAdd) {
        print('=== SYNC DEBUG: Adding entry: ${entry.title} ===');
        final added = await _kdbxService.addEntry(
          title: entry.title,
          username: entry.username,
          password: entry.password,
          url: entry.url,
          notes: entry.notes,
          tags: entry.tags,
        );
        print('=== SYNC DEBUG: Add result: $added ===');

        if (added) {
          syncedItems.add(
            SyncedItem(
              entryTitle: entry.title,
              action: SyncAction.added,
              sourceDevice: deviceName,
            ),
          );
        } else {
          print('=== SYNC DEBUG: Failed to add entry ${entry.title} ===');
        }

        processed++;
        _progress = processed / total;
        notifyListeners();
      }

      // Update existing entries
      for (final entry in toUpdate) {
        final localEntries = _kdbxService.getAllEntries();
        final localEntry = localEntries.firstWhere((e) {
          final syncData = SyncEntryData.fromKdbxEntry(e);
          return syncData.accountKey == entry.accountKey;
        }, orElse: () => throw Exception('Entry not found: ${entry.title}'));

        final updated = await _kdbxService.updateEntry(
          entry: localEntry,
          title: entry.title,
          username: entry.username,
          password: entry.password,
          url: entry.url,
          notes: entry.notes,
          tags: entry.tags,
        );

        if (updated) {
          syncedItems.add(
            SyncedItem(
              entryTitle: entry.title,
              action: SyncAction.modified,
              sourceDevice: deviceName,
            ),
          );
        }

        processed++;
        _progress = processed / total;
        notifyListeners();
      }

      // Delete entries
      for (final entry in toDelete) {
        final localEntries = _kdbxService.getAllEntries();
        try {
          final localEntry = localEntries.firstWhere((e) {
            final syncData = SyncEntryData.fromKdbxEntry(e);
            return syncData.accountKey == entry.accountKey;
          });

          final deleted = await _kdbxService.deleteEntry(localEntry);
          if (deleted) {
            syncedItems.add(
              SyncedItem(
                entryTitle: entry.title,
                action: SyncAction.deleted,
                sourceDevice: deviceName,
              ),
            );
          }
        } catch (e) {
          // Entry already deleted, skip
        }

        processed++;
        _progress = processed / total;
        notifyListeners();
      }

      _phase = 'Complete';
      _progress = 1;
      notifyListeners();
    } catch (e) {
      print('Error applying remote changes: $e');
      success = false;
    }

    return SyncLogEntry(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      deviceId: deviceId,
      deviceName: deviceName,
      accountName: accountName,
      items: syncedItems,
      success: success,
      errorMessage: success ? null : 'Failed to apply some changes',
    );
  }

  /// Read a complete line-delimited message from the socket stream
  Future<String?> _readMessage(
    StreamIterator<String> iterator, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final hasData = await iterator.moveNext().timeout(timeout);
      if (!hasData) return null;
      return iterator.current;
    } catch (e) {
      print('Error reading message: $e');
      return null;
    }
  }

  /// Perform sync with a connected device
  Future<SyncLogEntry> syncWithDevice(
    Socket socket,
    String remoteDeviceId,
    String remoteDeviceName,
    String localDeviceId,
    String localDeviceName,
    String accountName,
  ) async {
    _phase = 'Initiating sync...';
    _progress = 0;
    notifyListeners();

    // Ensure vault is loaded before syncing
    if (!await ensureVaultReady()) {
      return SyncLogEntry(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        deviceId: remoteDeviceId,
        deviceName: remoteDeviceName,
        accountName: accountName,
        items: [],
        success: false,
        errorMessage:
            'Cannot load vault for sync. Please unlock vault at least once.',
      );
    }

    // Create a stream iterator to properly handle multiple reads from the socket
    // First decode bytes to string, then split by lines
    // This fixes the "Stream has already been listened to" error
    final lineStream = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final streamIterator = StreamIterator(lineStream);

    try {
      // Send hello message
      final hello = SyncMessage(
        type: SyncMessageType.hello,
        deviceId: localDeviceId,
        data: {'deviceName': localDeviceName},
      );
      socket.write('${hello.toJsonString()}\n');
      await socket.flush();

      _phase = 'Exchanging data...';
      _progress = 0.2;
      notifyListeners();

      // Send local vault data
      print('=== SYNC DEBUG [syncWithDevice]: Extracting local entries ===');
      final localEntries = extractVaultData();
      print(
        '=== SYNC DEBUG [syncWithDevice]: Sending ${localEntries.length} entries ===',
      );
      final syncData = SyncMessage(
        type: SyncMessageType.syncData,
        deviceId: localDeviceId,
        data: {'entries': localEntries.map((e) => e.toJson()).toList()},
      );
      socket.write('${syncData.toJsonString()}\n');
      await socket.flush();

      _phase = 'Receiving remote data...';
      _progress = 0.4;
      notifyListeners();

      // Read remote response with sync data
      final responseString = await _readMessage(streamIterator);
      if (responseString == null) {
        throw Exception('No response from remote device');
      }
      final responseMessage = SyncMessage.fromJsonString(responseString);

      if (responseMessage.type == SyncMessageType.error) {
        throw Exception(responseMessage.data['message'] ?? 'Unknown error');
      }

      if (responseMessage.type != SyncMessageType.syncData) {
        throw Exception('Unexpected response type: ${responseMessage.type}');
      }

      // Parse remote entries
      final remoteEntriesJson = responseMessage.data['entries'] as List;
      print(
        '=== SYNC DEBUG [syncWithDevice]: Received ${remoteEntriesJson.length} remote entries ===',
      );
      final remoteEntries = remoteEntriesJson
          .map((e) => SyncEntryData.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final e in remoteEntries) {
        print('  - Remote: ${e.title} (${e.username})');
      }

      _phase = 'Comparing vaults...';
      _progress = 0.6;
      notifyListeners();

      // Compare vaults
      final comparison = compareVaults(localEntries, remoteEntries);

      if (!comparison.hasChanges) {
        // No changes to sync
        socket.write(
          '${SyncMessage(type: SyncMessageType.syncComplete, deviceId: localDeviceId, data: {'changesApplied': 0}).toJsonString()}\n',
        );
        await socket.flush();
        await streamIterator.cancel();
        await socket.close();

        return SyncLogEntry(
          id: const Uuid().v4(),
          timestamp: DateTime.now(),
          deviceId: remoteDeviceId,
          deviceName: remoteDeviceName,
          accountName: accountName,
          items: [],
          success: true,
        );
      }

      _phase = 'Applying changes...';
      _progress = 0.8;
      notifyListeners();

      // Apply incoming changes
      final syncLog = await applyRemoteChanges(
        remoteDeviceId,
        remoteDeviceName,
        accountName,
        comparison.toAddLocally,
        comparison.toUpdateLocally,
        comparison.toDeleteLocally,
      );

      // Send changes for remote to apply
      final changesToSend = SyncMessage(
        type: SyncMessageType.syncChanges,
        deviceId: localDeviceId,
        data: {
          'toAdd': comparison.toAddRemotely.map((e) => e.toJson()).toList(),
          'toUpdate': comparison.toUpdateRemotely
              .map((e) => e.toJson())
              .toList(),
          'toDelete': comparison.toDeleteRemotely
              .map((e) => e.toJson())
              .toList(),
        },
      );
      socket.write('${changesToSend.toJsonString()}\n');
      await socket.flush();

      // Send complete message
      socket.write(
        '${SyncMessage(type: SyncMessageType.syncComplete, deviceId: localDeviceId, data: {'changesApplied': comparison.totalChanges}).toJsonString()}\n',
      );
      await socket.flush();

      await streamIterator.cancel();
      await socket.close();

      _phase = 'Complete';
      _progress = 1;
      notifyListeners();

      return syncLog;
    } catch (e) {
      print('Error syncing with device: $e');
      try {
        await streamIterator.cancel();
        await socket.close();
      } catch (_) {}
      return SyncLogEntry(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        deviceId: remoteDeviceId,
        deviceName: remoteDeviceName,
        accountName: accountName,
        items: [],
        success: false,
        errorMessage: 'Sync failed: $e',
      );
    }
  }

  /// Handle incoming sync request from another device
  Future<SyncLogEntry> handleIncomingSync(
    Socket socket,
    String localDeviceId,
    String localDeviceName,
    String accountName,
  ) async {
    _phase = 'Receiving sync request...';
    _progress = 0;
    notifyListeners();

    // Ensure vault is loaded before handling sync
    if (!await ensureVaultReady()) {
      return SyncLogEntry(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        deviceId: 'unknown',
        deviceName: 'Unknown',
        accountName: accountName,
        items: [],
        success: false,
        errorMessage:
            'Cannot load vault for sync. Please unlock vault at least once.',
      );
    }

    String remoteDeviceId = '';
    String remoteDeviceName = '';

    // Create a stream iterator to properly handle multiple reads from the socket
    // This fixes the "Stream has already been listened to" error
    final lineStream = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final streamIterator = StreamIterator(lineStream);

    try {
      // Read hello message
      final helloString = await _readMessage(streamIterator);
      if (helloString == null) {
        throw Exception('No hello message received');
      }
      final helloMessage = SyncMessage.fromJsonString(helloString);

      if (helloMessage.type != SyncMessageType.hello) {
        throw Exception('Expected hello message');
      }

      remoteDeviceId = helloMessage.deviceId;
      remoteDeviceName = helloMessage.data['deviceName'] ?? 'Unknown';

      _phase = 'Receiving remote data...';
      _progress = 0.2;
      notifyListeners();

      // Read sync data
      final syncDataString = await _readMessage(streamIterator);
      if (syncDataString == null) {
        throw Exception('No sync data received');
      }
      final syncDataMessage = SyncMessage.fromJsonString(syncDataString);

      if (syncDataMessage.type != SyncMessageType.syncData) {
        throw Exception('Expected sync data message');
      }

      // Parse remote entries (not used directly, but validates data)
      final _ = syncDataMessage.data['entries'] as List;

      _phase = 'Sending local data...';
      _progress = 0.4;
      notifyListeners();

      // Send our local data
      final localEntries = extractVaultData();
      final response = SyncMessage(
        type: SyncMessageType.syncData,
        deviceId: localDeviceId,
        data: {'entries': localEntries.map((e) => e.toJson()).toList()},
      );
      socket.write('${response.toJsonString()}\n');
      await socket.flush();

      _phase = 'Receiving changes...';
      _progress = 0.6;
      notifyListeners();

      // Read changes to apply
      final changesString = await _readMessage(streamIterator);
      if (changesString == null) {
        throw Exception('No changes message received');
      }
      final changesMessage = SyncMessage.fromJsonString(changesString);

      if (changesMessage.type == SyncMessageType.syncComplete) {
        // No changes to apply
        await streamIterator.cancel();
        return SyncLogEntry(
          id: const Uuid().v4(),
          timestamp: DateTime.now(),
          deviceId: remoteDeviceId,
          deviceName: remoteDeviceName,
          accountName: accountName,
          items: [],
          success: true,
        );
      }

      if (changesMessage.type != SyncMessageType.syncChanges) {
        throw Exception('Expected sync changes message');
      }

      print(
        '=== SYNC DEBUG [handleIncomingSync]: Received changes message ===',
      );
      print('Changes data: ${changesMessage.data}');

      _phase = 'Applying changes...';
      _progress = 0.8;
      notifyListeners();

      // Parse and apply changes
      final toAdd =
          (changesMessage.data['toAdd'] as List?)
              ?.map((e) => SyncEntryData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final toUpdate =
          (changesMessage.data['toUpdate'] as List?)
              ?.map((e) => SyncEntryData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final toDelete =
          (changesMessage.data['toDelete'] as List?)
              ?.map((e) => SyncEntryData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      print('=== SYNC DEBUG [handleIncomingSync]: Parsed changes ===');
      print('toAdd: ${toAdd.length} entries');
      print('toUpdate: ${toUpdate.length} entries');
      print('toDelete: ${toDelete.length} entries');
      for (final e in toAdd) {
        print('  - To add: ${e.title} (${e.username})');
      }

      final syncLog = await applyRemoteChanges(
        remoteDeviceId,
        remoteDeviceName,
        accountName,
        toAdd,
        toUpdate,
        toDelete,
      );

      // Read complete message (optional, may not arrive if connection closed)
      try {
        await _readMessage(streamIterator, timeout: const Duration(seconds: 5));
      } catch (_) {
        // Ignore timeout on final message
      }

      await streamIterator.cancel();

      _phase = 'Complete';
      _progress = 1;
      notifyListeners();

      return syncLog;
    } catch (e) {
      print('Error handling incoming sync: $e');
      try {
        await streamIterator.cancel();
      } catch (_) {}
      return SyncLogEntry(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        deviceId: remoteDeviceId,
        deviceName: remoteDeviceName,
        accountName: accountName,
        items: [],
        success: false,
        errorMessage: 'Sync failed: $e',
      );
    }
  }

  /// Reset sync state
  void reset() {
    _progress = 0;
    _phase = '';
    notifyListeners();
  }
}
