import 'dart:convert';

/// Actions that can occur during sync
enum SyncAction { added, modified, deleted }

/// Represents an item that was synced
class SyncedItem {
  /// Title of the password entry (e.g., "Gmail")
  final String entryTitle;

  /// What action was performed
  final SyncAction action;

  /// Which device this change came from
  final String sourceDevice;

  SyncedItem({
    required this.entryTitle,
    required this.action,
    required this.sourceDevice,
  });

  factory SyncedItem.fromJson(Map<String, dynamic> json) {
    return SyncedItem(
      entryTitle: json['entryTitle'] as String,
      action: SyncAction.values.byName(json['action'] as String),
      sourceDevice: json['sourceDevice'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entryTitle': entryTitle,
      'action': action.name,
      'sourceDevice': sourceDevice,
    };
  }

  /// Human-readable description of this sync item
  String get description {
    switch (action) {
      case SyncAction.added:
        return 'Added "$entryTitle" from $sourceDevice';
      case SyncAction.modified:
        return 'Updated "$entryTitle" from $sourceDevice';
      case SyncAction.deleted:
        return 'Deleted "$entryTitle" from $sourceDevice';
    }
  }
}

/// Represents a sync session log entry
class SyncLogEntry {
  /// Unique identifier for this log entry
  final String id;

  /// When the sync occurred
  final DateTime timestamp;

  /// ID of the device synced with
  final String deviceId;

  /// Name of the device synced with
  final String deviceName;

  /// Name of the account that was synced
  final String accountName;

  /// List of items that were synced
  final List<SyncedItem> items;

  /// Whether sync was successful
  final bool success;

  /// Error message if sync failed
  final String? errorMessage;

  SyncLogEntry({
    required this.id,
    required this.timestamp,
    required this.deviceId,
    required this.deviceName,
    required this.accountName,
    required this.items,
    required this.success,
    this.errorMessage,
  });

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) {
    return SyncLogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      accountName: json['accountName'] as String,
      items: (json['items'] as List<dynamic>)
          .map((item) => SyncedItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'deviceId': deviceId,
      'deviceName': deviceName,
      'accountName': accountName,
      'items': items.map((item) => item.toJson()).toList(),
      'success': success,
      'errorMessage': errorMessage,
    };
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory SyncLogEntry.fromJsonString(String jsonString) {
    return SyncLogEntry.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Summary of this sync session
  String get summary {
    if (!success) {
      return 'Sync failed: ${errorMessage ?? "Unknown error"}';
    }

    final addedCount = items.where((i) => i.action == SyncAction.added).length;
    final modifiedCount = items
        .where((i) => i.action == SyncAction.modified)
        .length;
    final deletedCount = items
        .where((i) => i.action == SyncAction.deleted)
        .length;

    final parts = <String>[];
    if (addedCount > 0) parts.add('$addedCount added');
    if (modifiedCount > 0) parts.add('$modifiedCount modified');
    if (deletedCount > 0) parts.add('$deletedCount deleted');

    if (parts.isEmpty) return 'No changes';
    return parts.join(', ');
  }

  @override
  String toString() {
    return 'SyncLogEntry(id: $id, device: $deviceName, success: $success, items: ${items.length})';
  }
}
