import 'dart:convert';

/// Data exchanged during QR code pairing
class PairingData {
  /// Device ID of the device showing the QR code
  final String deviceId;

  /// Device name (e.g., "Dhruv's iPhone 15")
  final String deviceName;

  /// Public key for secure communication
  final String publicKey;

  /// IP address of the device
  final String ipAddress;

  /// Port for the sync service
  final int port;

  /// Timestamp when QR was generated (for expiry)
  final DateTime generatedAt;

  /// One-time pairing token for security
  final String pairingToken;

  PairingData({
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
    required this.ipAddress,
    required this.port,
    required this.generatedAt,
    required this.pairingToken,
  });

  /// Check if pairing data has expired (valid for 5 minutes)
  bool get isExpired {
    final expiryTime = generatedAt.add(const Duration(minutes: 5));
    return DateTime.now().isAfter(expiryTime);
  }

  factory PairingData.fromJson(Map<String, dynamic> json) {
    return PairingData(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      publicKey: json['publicKey'] as String,
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      pairingToken: json['pairingToken'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'publicKey': publicKey,
      'ipAddress': ipAddress,
      'port': port,
      'generatedAt': generatedAt.toIso8601String(),
      'pairingToken': pairingToken,
    };
  }

  /// Serialize to JSON string (for QR code)
  String toQRString() => jsonEncode(toJson());

  /// Deserialize from QR code string
  factory PairingData.fromQRString(String qrString) {
    return PairingData.fromJson(jsonDecode(qrString) as Map<String, dynamic>);
  }

  @override
  String toString() {
    return 'PairingData(deviceId: $deviceId, deviceName: $deviceName, ip: $ipAddress:$port)';
  }
}

/// Response sent back after scanning QR code
class PairingResponse {
  /// Device ID of the scanning device
  final String deviceId;

  /// Device name of the scanning device
  final String deviceName;

  /// Public key of the scanning device
  final String publicKey;

  /// The pairing token from the QR code (for verification)
  final String pairingToken;

  /// Whether pairing was accepted
  final bool accepted;

  PairingResponse({
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
    required this.pairingToken,
    required this.accepted,
  });

  factory PairingResponse.fromJson(Map<String, dynamic> json) {
    return PairingResponse(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      publicKey: json['publicKey'] as String,
      pairingToken: json['pairingToken'] as String,
      accepted: json['accepted'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'publicKey': publicKey,
      'pairingToken': pairingToken,
      'accepted': accepted,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory PairingResponse.fromJsonString(String jsonString) {
    return PairingResponse.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }
}
