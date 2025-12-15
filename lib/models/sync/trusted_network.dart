import 'dart:convert';

/// Represents a WiFi network that is trusted for automatic sync
class TrustedNetwork {
  /// WiFi SSID (network name)
  final String ssid;

  /// When this network was added to trusted list
  final DateTime addedAt;

  /// Whether this is the currently connected network (runtime only)
  bool isCurrentNetwork;

  TrustedNetwork({
    required this.ssid,
    required this.addedAt,
    this.isCurrentNetwork = false,
  });

  /// Create from JSON (for persistence)
  factory TrustedNetwork.fromJson(Map<String, dynamic> json) {
    return TrustedNetwork(
      ssid: json['ssid'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  /// Convert to JSON (for persistence)
  Map<String, dynamic> toJson() {
    return {'ssid': ssid, 'addedAt': addedAt.toIso8601String()};
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory TrustedNetwork.fromJsonString(String jsonString) {
    return TrustedNetwork.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Create a copy with updated fields
  TrustedNetwork copyWith({
    String? ssid,
    DateTime? addedAt,
    bool? isCurrentNetwork,
  }) {
    return TrustedNetwork(
      ssid: ssid ?? this.ssid,
      addedAt: addedAt ?? this.addedAt,
      isCurrentNetwork: isCurrentNetwork ?? this.isCurrentNetwork,
    );
  }

  @override
  String toString() {
    return 'TrustedNetwork(ssid: $ssid, isCurrentNetwork: $isCurrentNetwork)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrustedNetwork && other.ssid == ssid;
  }

  @override
  int get hashCode => ssid.hashCode;
}
