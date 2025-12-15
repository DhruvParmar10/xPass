import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../../models/sync/sync_models.dart';
import '../kdbx_service.dart';
import 'network_monitor.dart';
import 'discovery_service.dart';
import 'sync_engine.dart';

/// Main service for managing sync operations
class SyncManager extends ChangeNotifier {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  /// Sub-services
  final NetworkMonitor _networkMonitor = NetworkMonitor();
  final DiscoveryService _discoveryService = DiscoveryService();
  final KdbxService _kdbxService = KdbxService();

  /// Current sync state
  SyncState _state = SyncState.idle;
  SyncState get state => _state;

  /// Current sync progress
  SyncProgress _progress = SyncProgress.initial;
  SyncProgress get progress => _progress;

  /// Last sync result
  SyncResult? _lastResult;
  SyncResult? get lastResult => _lastResult;

  /// List of paired devices
  List<PairedDevice> _pairedDevices = [];
  List<PairedDevice> get pairedDevices => List.unmodifiable(_pairedDevices);

  /// Currently online devices
  List<PairedDevice> _onlineDevices = [];
  List<PairedDevice> get onlineDevices => List.unmodifiable(_onlineDevices);

  /// Sync history log
  List<SyncLogEntry> _syncLogs = [];
  List<SyncLogEntry> get syncLogs => List.unmodifiable(_syncLogs);

  /// Settings
  bool _autoSyncEnabled = true;
  bool get autoSyncEnabled => _autoSyncEnabled;

  bool _backgroundSyncEnabled = false;
  bool get backgroundSyncEnabled => _backgroundSyncEnabled;

  /// This device's unique ID
  String? _deviceId;
  String? get deviceId => _deviceId;

  /// This device's name
  String? _deviceName;
  String? get deviceName => _deviceName;

  /// Storage keys
  static const String _deviceIdKey = 'sync_device_id';
  static const String _deviceNameKey = 'sync_device_name';
  static const String _pairedDevicesKey = 'sync_paired_devices';
  static const String _syncLogsKey = 'sync_logs';
  static const String _autoSyncKey = 'sync_auto_enabled';
  static const String _backgroundSyncKey = 'sync_background_enabled';

  /// Network change subscription
  StreamSubscription<String?>? _networkSubscription;

  /// Discovery status subscription
  StreamSubscription<bool>? _discoverySubscription;

  /// Timer for periodic device discovery refresh
  Timer? _discoveryRefreshTimer;

  /// Network monitor access
  NetworkMonitor get networkMonitor => _networkMonitor;

  /// Discovery service access
  DiscoveryService get discoveryService => _discoveryService;

  /// Whether initialized
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize the sync system
  Future<void> initialize() async {
    if (_isInitialized) {
      print('SyncManager already initialized');
      return;
    }

    print('Initializing SyncManager...');

    // Load device identity
    await _loadOrCreateDeviceId();
    await _loadDeviceName();

    // Load settings and data
    await _loadSettings();
    await _loadPairedDevices();
    await _loadSyncLogs();

    // Initialize network monitor
    await _networkMonitor.initialize();

    // Listen for network changes
    _networkSubscription = _networkMonitor.onNetworkChange.listen((ssid) {
      _onNetworkChanged(ssid);
    });

    // Listen for discovery changes
    _discoverySubscription = _discoveryService.onDiscoveryStatusChanged.listen((
      _,
    ) {
      _refreshOnlineDevices();
    });

    // Also listen to discovery service for immediate updates
    _discoveryService.addListener(() {
      _refreshOnlineDevices();
    });

    // Set up callback for incoming sync
    _discoveryService.onSyncCompleted = (syncLog) {
      addSyncLog(syncLog);
      _refreshOnlineDevices();
    };

    print(
      'Network status: isOnTrustedNetwork=${_networkMonitor.isOnTrustedNetwork}',
    );
    print('Current SSID: ${_networkMonitor.currentSSID}');
    print(
      'Trusted networks: ${_networkMonitor.trustedNetworks.map((n) => n.ssid).toList()}',
    );

    // Register mDNS service if on trusted network
    // Note: We register even if vault is locked - the sync flow will auto-load using stored password
    if (_networkMonitor.isOnTrustedNetwork &&
        _deviceId != null &&
        _deviceName != null) {
      print(
        'On trusted network, registering discovery service for background sync...',
      );
      await _registerDiscoveryService();
      _startPeriodicDiscoveryRefresh();
    } else {
      print(
        'Not on trusted network or device info missing - skipping registration',
      );
      print('  - isOnTrustedNetwork: ${_networkMonitor.isOnTrustedNetwork}');
      print('  - deviceId: $_deviceId');
      print('  - deviceName: $_deviceName');
    }

    _isInitialized = true;

    print(
      'SyncManager initialized: deviceId=$_deviceId, deviceName=$_deviceName',
    );
    notifyListeners();
  }

  /// Register this device for mDNS discovery
  Future<void> _registerDiscoveryService() async {
    if (_deviceId == null || _deviceName == null) return;

    final accountName = _kdbxService.currentAccount?.name;

    print(
      'Registering mDNS service: deviceId=$_deviceId, deviceName=$_deviceName',
    );

    await _discoveryService.registerService(
      deviceId: _deviceId!,
      deviceName: _deviceName!,
      accountName: accountName,
    );
  }

  /// Force start discovery and registration (for manual triggering)
  Future<void> forceStartDiscovery() async {
    print('Force starting discovery...');

    if (_deviceId == null || _deviceName == null) {
      print('Cannot start discovery: device info not set');
      return;
    }

    // Unregister first if already registered
    if (_discoveryService.isRegistered) {
      print('Already registered, refreshing...');
      await _discoveryService.refreshDiscovery();
    } else {
      await _registerDiscoveryService();
    }

    _startPeriodicDiscoveryRefresh();

    // Wait a bit then refresh
    await Future.delayed(const Duration(seconds: 3));
    _refreshOnlineDevices();
  }

  /// Unregister from mDNS discovery
  Future<void> _unregisterDiscoveryService() async {
    await _discoveryService.unregisterService();
    _stopPeriodicDiscoveryRefresh();
  }

  /// Called when the vault is unlocked - trigger immediate sync if on trusted network
  /// Note: Registration now happens automatically when on trusted network
  Future<void> onVaultUnlocked() async {
    print('SyncManager: Vault unlocked notification received');

    if (!_isInitialized) {
      print('SyncManager not initialized yet, skipping...');
      return;
    }

    // Trigger immediate sync if on trusted network and auto-sync is enabled
    if (_networkMonitor.isOnTrustedNetwork &&
        _autoSyncEnabled &&
        _pairedDevices.isNotEmpty) {
      print('Vault unlocked on trusted network, triggering immediate sync...');
      Future.delayed(const Duration(seconds: 2), () {
        discoverAndSync();
      });
    }
  }

  /// Called when the vault is locked - no need to unregister since background sync can auto-load
  Future<void> onVaultLocked() async {
    print('SyncManager: Vault locked notification received');
    // No need to unregister - background sync will auto-load the vault using stored password
  }

  /// Start periodic refresh of online devices
  void _startPeriodicDiscoveryRefresh() {
    _stopPeriodicDiscoveryRefresh();

    // Refresh every 10 seconds
    _discoveryRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshOnlineDevices(),
    );

    // Do an immediate refresh
    _refreshOnlineDevices();
  }

  /// Stop periodic refresh
  void _stopPeriodicDiscoveryRefresh() {
    _discoveryRefreshTimer?.cancel();
    _discoveryRefreshTimer = null;
  }

  /// Refresh the list of online devices
  void _refreshOnlineDevices() {
    if (_pairedDevices.isEmpty) {
      _onlineDevices = [];
      notifyListeners();
      return;
    }

    // Get currently online devices from discovery service
    _onlineDevices = _discoveryService.getOnlinePairedDevices(_pairedDevices);
    print(
      'Refreshed online devices: ${_onlineDevices.length} online out of ${_pairedDevices.length} paired',
    );
    notifyListeners();
  }

  /// Called when network changes
  void _onNetworkChanged(String? ssid) {
    print('Network changed to: $ssid');

    if (ssid == null) {
      // Disconnected from WiFi
      _onlineDevices = [];
      _unregisterDiscoveryService();
      notifyListeners();
      return;
    }

    if (_networkMonitor.isTrustedNetwork(ssid)) {
      // Connected to trusted network - register for background sync
      // The sync flow will auto-load vault using stored password if needed
      print(
        'On trusted network, registering discovery service for background sync...',
      );
      _registerDiscoveryService();
      _startPeriodicDiscoveryRefresh();

      if (_autoSyncEnabled && _pairedDevices.isNotEmpty) {
        // Trigger discovery and sync after a short delay
        print('Connected to trusted network "$ssid", triggering sync...');
        Future.delayed(const Duration(seconds: 3), () {
          discoverAndSync();
        });
      }
    } else {
      // Not on trusted network, unregister
      _unregisterDiscoveryService();
      _onlineDevices = [];
      notifyListeners();
    }
  }

  /// Load or create unique device ID
  Future<void> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
      print('Created new device ID: $_deviceId');
    } else {
      print('Loaded existing device ID: $_deviceId');
    }
  }

  /// Load device name from platform
  Future<void> _loadDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceName = prefs.getString(_deviceNameKey);

    if (_deviceName == null) {
      _deviceName = await _getDefaultDeviceName();
      await prefs.setString(_deviceNameKey, _deviceName!);
      print('Set default device name: $_deviceName');
    }
  }

  /// Get default device name from platform
  Future<String> _getDefaultDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.name;
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        return info.computerName;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        return info.computerName;
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        return info.prettyName;
      }
    } catch (e) {
      print('Error getting device name: $e');
    }

    return 'Unknown Device';
  }

  /// Update device name
  Future<void> setDeviceName(String name) async {
    _deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceNameKey, name);
    notifyListeners();
  }

  /// Load sync settings
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = prefs.getBool(_autoSyncKey) ?? true;
    _backgroundSyncEnabled = prefs.getBool(_backgroundSyncKey) ?? false;
  }

  /// Save sync settings
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, _autoSyncEnabled);
    await prefs.setBool(_backgroundSyncKey, _backgroundSyncEnabled);
  }

  /// Toggle auto sync
  Future<void> setAutoSync(bool enabled) async {
    _autoSyncEnabled = enabled;
    await _saveSettings();
    notifyListeners();
  }

  /// Toggle background sync
  Future<void> setBackgroundSync(bool enabled) async {
    _backgroundSyncEnabled = enabled;
    await _saveSettings();
    // TODO: Register/unregister background tasks
    notifyListeners();
  }

  /// Load paired devices from storage
  Future<void> _loadPairedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_pairedDevicesKey) ?? [];

      _pairedDevices = jsonList.map((jsonString) {
        return PairedDevice.fromJsonString(jsonString);
      }).toList();

      print('Loaded ${_pairedDevices.length} paired devices');
    } catch (e) {
      print('Error loading paired devices: $e');
      _pairedDevices = [];
    }
  }

  /// Save paired devices to storage
  Future<void> _savePairedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _pairedDevices.map((device) {
        return device.toJsonString();
      }).toList();

      await prefs.setStringList(_pairedDevicesKey, jsonList);
      print('Saved ${_pairedDevices.length} paired devices');
    } catch (e) {
      print('Error saving paired devices: $e');
    }
  }

  /// Add a newly paired device
  Future<void> addPairedDevice(PairedDevice device) async {
    // Check if already paired
    if (_pairedDevices.any((d) => d.id == device.id)) {
      print('Device ${device.id} is already paired');
      return;
    }

    _pairedDevices.add(device);
    await _savePairedDevices();
    notifyListeners();
    print('Added paired device: ${device.name}');
  }

  /// Remove a paired device
  Future<void> removePairedDevice(String deviceId) async {
    _pairedDevices.removeWhere((device) => device.id == deviceId);
    _onlineDevices.removeWhere((device) => device.id == deviceId);
    await _savePairedDevices();
    notifyListeners();
    print('Removed paired device: $deviceId');
  }

  /// Update paired device name
  Future<void> updateDeviceName(String deviceId, String newName) async {
    final index = _pairedDevices.indexWhere((d) => d.id == deviceId);
    if (index >= 0) {
      _pairedDevices[index].name = newName;
      await _savePairedDevices();
      notifyListeners();
    }
  }

  /// Get a paired device by ID
  PairedDevice? getPairedDevice(String deviceId) {
    try {
      return _pairedDevices.firstWhere((d) => d.id == deviceId);
    } catch (e) {
      return null;
    }
  }

  /// Load sync logs from storage
  Future<void> _loadSyncLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_syncLogsKey) ?? [];

      _syncLogs = jsonList.map((jsonString) {
        return SyncLogEntry.fromJsonString(jsonString);
      }).toList();

      // Keep only last 20 logs
      if (_syncLogs.length > 20) {
        _syncLogs = _syncLogs.sublist(_syncLogs.length - 20);
        await _saveSyncLogs();
      }

      print('Loaded ${_syncLogs.length} sync logs');
    } catch (e) {
      print('Error loading sync logs: $e');
      _syncLogs = [];
    }
  }

  /// Save sync logs to storage
  Future<void> _saveSyncLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _syncLogs.map((log) {
        return log.toJsonString();
      }).toList();

      await prefs.setStringList(_syncLogsKey, jsonList);
    } catch (e) {
      print('Error saving sync logs: $e');
    }
  }

  /// Add a sync log entry
  Future<void> addSyncLog(SyncLogEntry log) async {
    _syncLogs.add(log);

    // Keep only last 20 logs
    if (_syncLogs.length > 20) {
      _syncLogs = _syncLogs.sublist(_syncLogs.length - 20);
    }

    await _saveSyncLogs();
    notifyListeners();
  }

  /// Clear all sync logs
  Future<void> clearSyncLogs() async {
    _syncLogs.clear();
    await _saveSyncLogs();
    notifyListeners();
  }

  /// Discover paired devices on the network and sync
  Future<SyncResult> discoverAndSync() async {
    if (_state == SyncState.syncing || _state == SyncState.discovering) {
      print('Sync already in progress');
      return SyncResult.cancelled;
    }

    if (!_networkMonitor.isOnTrustedNetwork) {
      print('Not on trusted network, skipping sync');
      print('Current SSID: ${_networkMonitor.currentSSID}');
      print(
        'Trusted networks: ${_networkMonitor.trustedNetworks.map((n) => n.ssid).toList()}',
      );
      _lastResult = SyncResult.notOnTrustedNetwork;
      notifyListeners();
      return SyncResult.notOnTrustedNetwork;
    }

    if (_pairedDevices.isEmpty) {
      print('No paired devices, skipping sync');
      _lastResult = SyncResult.noDevicesFound;
      notifyListeners();
      return SyncResult.noDevicesFound;
    }

    // Note: We don't check if vault is loaded here anymore
    // The sync will exchange encrypted vault data between paired devices
    // Authentication happens via the pairing process, not vault unlock

    _state = SyncState.discovering;
    _progress = const SyncProgress(
      phase: 'Discovering devices...',
      progress: 10,
    );
    notifyListeners();

    try {
      // Make sure discovery service is registered
      if (!_discoveryService.isRegistered &&
          _deviceId != null &&
          _deviceName != null) {
        print('Registering discovery service before sync...');
        await _registerDiscoveryService();
      }

      // Use discovery service to find paired devices
      print(
        'Discovering paired devices... (${_pairedDevices.length} paired devices)',
      );
      _onlineDevices = await _discoveryService.discoverPairedDevices(
        _pairedDevices,
        timeout: const Duration(seconds: 5),
      );

      if (_onlineDevices.isEmpty) {
        print('No paired devices found online after discovery');
        print(
          'Discovered services: ${_discoveryService.discoveredServices.length}',
        );
        _state = SyncState.idle;
        _lastResult = SyncResult.noDevicesFound;
        notifyListeners();
        return SyncResult.noDevicesFound;
      }

      print('Found ${_onlineDevices.length} paired device(s) online');

      // Update progress
      _progress = SyncProgress(
        phase: 'Found ${_onlineDevices.length} device(s)',
        progress: 30,
      );
      notifyListeners();

      // Sync with each online device
      _state = SyncState.syncing;
      final syncEngine = SyncEngine();
      final accountName = _kdbxService.currentAccount?.name ?? 'Unknown';
      var syncedAny = false;

      for (int i = 0; i < _onlineDevices.length; i++) {
        final device = _onlineDevices[i];

        _progress = SyncProgress(
          phase: 'Syncing with ${device.name}...',
          progress: 30 + (60 * (i + 1) / _onlineDevices.length).round(),
        );
        notifyListeners();

        try {
          // Connect to the device's sync port
          // The port is stored in port field, discovered via mDNS
          final syncPort = device.port ?? 45678;
          final deviceIP = device.ipAddress ?? '';

          if (deviceIP.isEmpty) {
            print('No IP address for ${device.name}, skipping');
            continue;
          }

          print('Connecting to ${device.name} at $deviceIP:$syncPort...');

          final socket = await Socket.connect(
            deviceIP,
            syncPort,
            timeout: const Duration(seconds: 10),
          );

          print('Connected to ${device.name}, starting sync...');

          // Perform sync
          final syncLog = await syncEngine.syncWithDevice(
            socket,
            device.id,
            device.name,
            _deviceId!,
            _deviceName!,
            accountName,
          );

          // Log the sync
          await addSyncLog(syncLog);

          // Update device last seen
          device.lastSeen = DateTime.now();
          device.lastSyncAt = DateTime.now();
          await _savePairedDevices();

          syncedAny = true;
          print(
            'Sync with ${device.name} completed: ${syncLog.success ? "success" : "failed"}',
          );
        } catch (e) {
          print('Error syncing with ${device.name}: $e');
          // Continue with other devices
        }
      }

      _state = SyncState.idle;
      _progress = const SyncProgress(phase: 'Complete', progress: 100);
      _lastResult = syncedAny ? SyncResult.success : SyncResult.networkError;
      notifyListeners();

      return syncedAny ? SyncResult.success : SyncResult.networkError;
    } catch (e) {
      print('Error during discovery/sync: $e');
      _state = SyncState.error;
      _lastResult = SyncResult.networkError;
      notifyListeners();
      return SyncResult.networkError;
    }
  }

  /// Manually trigger sync
  Future<SyncResult> triggerSync() async {
    return await discoverAndSync();
  }

  /// Cancel ongoing sync
  void cancelSync() {
    if (_state == SyncState.syncing || _state == SyncState.discovering) {
      _state = SyncState.idle;
      _lastResult = SyncResult.cancelled;
      notifyListeners();
    }
  }

  /// Get last sync time for any device
  DateTime? get lastSyncTime {
    if (_syncLogs.isEmpty) return null;

    final successfulLogs = _syncLogs.where((log) => log.success);
    if (successfulLogs.isEmpty) return null;

    return successfulLogs.last.timestamp;
  }

  /// Check if there are any paired devices
  bool get hasPairedDevices => _pairedDevices.isNotEmpty;

  /// Check if there are any online devices
  bool get hasOnlineDevices => _onlineDevices.isNotEmpty;

  /// Clean up resources
  @override
  void dispose() {
    _networkSubscription?.cancel();
    _discoverySubscription?.cancel();
    _stopPeriodicDiscoveryRefresh();
    _discoveryService.dispose();
    _networkMonitor.dispose();
    super.dispose();
  }
}
