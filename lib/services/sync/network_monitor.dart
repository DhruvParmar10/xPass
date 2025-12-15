import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/sync/sync_models.dart';

/// Service for monitoring network state and managing trusted networks
class NetworkMonitor extends ChangeNotifier {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  final NetworkInfo _networkInfo = NetworkInfo();

  /// Method channel for native WiFi access on macOS
  static const _wifiChannel = MethodChannel('com.xpass/wifi');

  /// Whether location permission has been granted
  bool _hasLocationPermission = false;
  bool get hasLocationPermission => _hasLocationPermission;

  /// Request location permission (required for WiFi SSID on Android/macOS/iOS)
  Future<bool> requestLocationPermission() async {
    if (Platform.isMacOS) {
      // macOS: Use native method channel to request location permission
      try {
        final granted = await _wifiChannel.invokeMethod<bool>(
          'requestLocationPermission',
        );
        _hasLocationPermission = granted ?? false;
        if (_hasLocationPermission) {
          await _checkCurrentNetwork();
          notifyListeners();
        }
        return _hasLocationPermission;
      } catch (e) {
        print('Error requesting macOS location permission: $e');
        return false;
      }
    } else if (Platform.isIOS || Platform.isAndroid) {
      try {
        final status = await Permission.location.request();
        _hasLocationPermission = status.isGranted;
        if (_hasLocationPermission) {
          await _checkCurrentNetwork();
          notifyListeners();
        }
        return _hasLocationPermission;
      } catch (e) {
        print('Error requesting location permission: $e');
        return false;
      }
    }
    return true; // Other platforms don't need location for WiFi
  }

  /// Check if location permission is granted
  Future<bool> checkLocationPermission() async {
    if (Platform.isMacOS) {
      try {
        final status = await _wifiChannel.invokeMethod<String>(
          'checkLocationPermission',
        );
        _hasLocationPermission =
            status == 'granted' || status == 'authorizedAlways';
        return _hasLocationPermission;
      } catch (e) {
        print('Error checking macOS location permission: $e');
        return false;
      }
    } else if (Platform.isIOS || Platform.isAndroid) {
      try {
        final status = await Permission.location.status;
        _hasLocationPermission = status.isGranted;
        return _hasLocationPermission;
      } catch (e) {
        print('Error checking location permission: $e');
        return false;
      }
    }
    return true;
  }

  /// Get macOS WiFi SSID using system command
  Future<String?> _getMacOSWifiSSID() async {
    try {
      // First try native CoreWLAN via method channel (most reliable)
      try {
        final ssid = await _wifiChannel.invokeMethod<String>('getWifiSSID');
        if (ssid != null && ssid.isNotEmpty && !_isRedactedOrUnknown(ssid)) {
          return ssid;
        }
      } catch (e) {
        print('Method channel error: $e');
      }

      // Fallback: try the network_info_plus package
      final pluginSsid = await _networkInfo.getWifiName();
      if (pluginSsid != null &&
          pluginSsid.isNotEmpty &&
          !_isRedactedOrUnknown(pluginSsid)) {
        return pluginSsid.replaceAll('"', '');
      }

      // Fallback 2: Use networksetup (requires sandbox exception)
      final result = await Process.run('networksetup', [
        '-getairportnetwork',
        'en0',
      ]);

      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        // Output is like "Current Wi-Fi Network: NetworkName"
        if (output.contains(': ') && !output.contains('not associated')) {
          final ssid = output.split(': ').last.trim();
          if (ssid.isNotEmpty && !_isRedactedOrUnknown(ssid)) {
            return ssid;
          }
        }
      }

      // Fallback 3: try system_profiler and parse manually
      final result2 = await Process.run('system_profiler', [
        'SPAirPortDataType',
      ]);
      if (result2.exitCode == 0) {
        final output = result2.stdout as String;
        final lines = output.split('\n');
        bool foundCurrentNetwork = false;
        for (final line in lines) {
          if (line.contains('Current Network Information:')) {
            foundCurrentNetwork = true;
            continue;
          }
          if (foundCurrentNetwork) {
            // The next non-empty line after "Current Network Information:" contains the SSID
            final trimmed = line.trim();
            if (trimmed.isNotEmpty && trimmed.endsWith(':')) {
              // Remove the trailing colon
              final ssid = trimmed.substring(0, trimmed.length - 1);
              if (!_isRedactedOrUnknown(ssid)) {
                return ssid;
              }
            }
          }
        }
      }

      return null;
    } catch (e) {
      print('Error getting macOS WiFi SSID: $e');
      return null;
    }
  }

  /// Check if SSID value is redacted, unknown, or an interface name
  bool _isRedactedOrUnknown(String ssid) {
    final lower = ssid.toLowerCase();
    // Filter out redacted/unknown values
    if (ssid.contains('<redacted>') ||
        ssid.contains('<unknown') ||
        lower == 'unknown' ||
        lower == 'redacted' ||
        lower.contains('other local') ||
        ssid.isEmpty) {
      return true;
    }
    // Filter out network interface names (not SSIDs)
    final interfacePattern = RegExp(
      r'^(en|awdl|llw|utun|lo|bridge|p2p|ap)\d*$',
    );
    if (interfacePattern.hasMatch(lower)) {
      return true;
    }
    return false;
  }

  /// Stream controller for network change events
  final _networkController = StreamController<String?>.broadcast();

  /// Stream of network SSID changes
  Stream<String?> get onNetworkChange => _networkController.stream;

  /// List of trusted networks
  List<TrustedNetwork> _trustedNetworks = [];
  List<TrustedNetwork> get trustedNetworks =>
      List.unmodifiable(_trustedNetworks);

  /// Current WiFi SSID
  String? _currentSSID;
  String? get currentSSID => _currentSSID;

  /// Whether we're currently on a trusted network
  bool _isOnTrustedNetwork = false;
  bool get isOnTrustedNetwork => _isOnTrustedNetwork;

  /// Timer for periodic network checks
  Timer? _networkCheckTimer;

  /// Storage key for trusted networks
  static const String _trustedNetworksKey = 'trusted_networks';

  /// Initialize the network monitor
  Future<void> initialize() async {
    await _loadTrustedNetworks();
    // Check location permission on Android/iOS/macOS for WiFi SSID
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      await checkLocationPermission();
      // Don't auto-request on macOS - let user click the button
      if (!_hasLocationPermission && !Platform.isMacOS) {
        // Request permission automatically on first launch for mobile
        await requestLocationPermission();
      }
    }
    await _checkCurrentNetwork();
    _startPeriodicCheck();
  }

  /// Start periodic network checking
  void _startPeriodicCheck() {
    _networkCheckTimer?.cancel();
    _networkCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkCurrentNetwork(),
    );
  }

  /// Dispose resources and cancel timers
  @override
  void dispose() {
    _networkCheckTimer?.cancel();
    _networkCheckTimer = null;
    _networkController.close();
    super.dispose();
  }

  /// Check current network and update state
  Future<void> _checkCurrentNetwork() async {
    final previousSSID = _currentSSID;
    _currentSSID = await getCurrentSSID();

    if (_currentSSID != previousSSID) {
      print('Network changed: $previousSSID -> $_currentSSID');
      _networkController.add(_currentSSID);
    }

    final previousTrustedState = _isOnTrustedNetwork;
    _isOnTrustedNetwork =
        _currentSSID != null && isTrustedNetwork(_currentSSID!);

    // Update isCurrentNetwork flag on all networks
    for (final network in _trustedNetworks) {
      network.isCurrentNetwork = network.ssid == _currentSSID;
    }

    if (_isOnTrustedNetwork != previousTrustedState) {
      notifyListeners();
    }
  }

  /// Get the current WiFi SSID
  Future<String?> getCurrentSSID() async {
    try {
      String? ssid;

      if (Platform.isMacOS) {
        // Use native macOS command for reliable WiFi detection
        ssid = await _getMacOSWifiSSID();
      } else if (Platform.isAndroid || Platform.isIOS) {
        ssid = await _networkInfo.getWifiName();
      } else if (Platform.isLinux || Platform.isWindows) {
        // For other desktop platforms, try network_info_plus
        ssid = await _networkInfo.getWifiName();
      }

      // Remove quotes if present (Android sometimes adds them)
      ssid = ssid?.replaceAll('"', '');

      // Some platforms return "<unknown ssid>" when permission denied
      if (ssid == '<unknown ssid>' || ssid == 'unknown') {
        return null;
      }

      return ssid;
    } catch (e) {
      print('Error getting WiFi SSID: $e');
      return null;
    }
  }

  /// Get current WiFi IP address
  Future<String?> getCurrentIP() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      print('Error getting WiFi IP: $e');
      return null;
    }
  }

  /// Check if a network SSID is in the trusted list
  bool isTrustedNetwork(String ssid) {
    return _trustedNetworks.any((network) => network.ssid == ssid);
  }

  /// Check if currently connected to a trusted network
  Future<bool> checkTrustedNetworkStatus() async {
    await _checkCurrentNetwork();
    return _isOnTrustedNetwork;
  }

  /// Add current network to trusted list
  Future<bool> addCurrentNetworkAsTrusted() async {
    final ssid = await getCurrentSSID();
    if (ssid == null || ssid.isEmpty) {
      print('Cannot add trusted network: no WiFi connection');
      return false;
    }

    return await addTrustedNetwork(ssid);
  }

  /// Add a network to the trusted list
  Future<bool> addTrustedNetwork(String ssid) async {
    if (isTrustedNetwork(ssid)) {
      print('Network "$ssid" is already trusted');
      return true;
    }

    final network = TrustedNetwork(
      ssid: ssid,
      addedAt: DateTime.now(),
      isCurrentNetwork: ssid == _currentSSID,
    );

    _trustedNetworks.add(network);
    await _saveTrustedNetworks();

    // Update trusted network status
    _isOnTrustedNetwork =
        _currentSSID != null && isTrustedNetwork(_currentSSID!);

    notifyListeners();
    print('Added "$ssid" to trusted networks');
    return true;
  }

  /// Remove a network from the trusted list
  Future<void> removeTrustedNetwork(String ssid) async {
    _trustedNetworks.removeWhere((network) => network.ssid == ssid);
    await _saveTrustedNetworks();

    // Update trusted network status
    _isOnTrustedNetwork =
        _currentSSID != null && isTrustedNetwork(_currentSSID!);

    notifyListeners();
    print('Removed "$ssid" from trusted networks');
  }

  /// Load trusted networks from persistent storage
  Future<void> _loadTrustedNetworks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_trustedNetworksKey) ?? [];

      _trustedNetworks = jsonList.map((jsonString) {
        return TrustedNetwork.fromJsonString(jsonString);
      }).toList();

      print('Loaded ${_trustedNetworks.length} trusted networks');
    } catch (e) {
      print('Error loading trusted networks: $e');
      _trustedNetworks = [];
    }
  }

  /// Save trusted networks to persistent storage
  Future<void> _saveTrustedNetworks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _trustedNetworks.map((network) {
        return network.toJsonString();
      }).toList();

      await prefs.setStringList(_trustedNetworksKey, jsonList);
      print('Saved ${_trustedNetworks.length} trusted networks');
    } catch (e) {
      print('Error saving trusted networks: $e');
    }
  }

  /// Force refresh network status
  Future<void> refresh() async {
    await _checkCurrentNetwork();
  }
}
