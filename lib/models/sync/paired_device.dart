import 'dart:convert';

/// Represents a device that has been paired for syncing
class PairedDevice {
  /// Unique identifier for this device
  final String id;

  /// Display name (e.g., "Dhruv's iPhone 15")
  String name;

  /// Public key for secure communication
  final String publicKey;

  /// When the device was first paired
  final DateTime pairedAt;

  /// Last time this device was seen on the network
  DateTime lastSeen;

  /// Last successful sync time
  DateTime? lastSyncAt;

  /// Whether device is currently online on trusted network
  bool isOnline;

  /// IP address when discovered (not persisted)
  String? ipAddress;

  /// Port for sync service (not persisted)
  int? port;

  PairedDevice({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.pairedAt,
    required this.lastSeen,
    this.lastSyncAt,
    this.isOnline = false,
    this.ipAddress,
    this.port,
  });

  /// Create from JSON (for persistence)
  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      publicKey: json['publicKey'] as String,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      lastSyncAt: json['lastSyncAt'] != null
          ? DateTime.parse(json['lastSyncAt'] as String)
          : null,
    );
  }

  /// Convert to JSON (for persistence)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
      'pairedAt': pairedAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'lastSyncAt': lastSyncAt?.toIso8601String(),
    };
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory PairedDevice.fromJsonString(String jsonString) {
    return PairedDevice.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Create a copy with updated fields
  PairedDevice copyWith({
    String? id,
    String? name,
    String? publicKey,
    DateTime? pairedAt,
    DateTime? lastSeen,
    DateTime? lastSyncAt,
    bool? isOnline,
    String? ipAddress,
    int? port,
  }) {
    return PairedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isOnline: isOnline ?? this.isOnline,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
    );
  }

  @override
  String toString() {
    return 'PairedDevice(id: $id, name: $name, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PairedDevice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
