import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';
import '../../models/sync/sync_models.dart';
import '../kdbx_service.dart';
import 'sync_engine.dart';

/// Service for mDNS-based device discovery
/// Allows xPass devices to find each other on the local network
class DiscoveryService extends ChangeNotifier {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  /// Service type for xPass sync (must end with ._tcp or ._udp)
  static const String serviceType = '_xpass-sync._tcp';

  /// Service name prefix
  static const String serviceNamePrefix = 'xpass';

  /// Default port for sync service
  static const int defaultPort = 52849;

  /// Current discovery instance
  Discovery? _discovery;

  /// Current registration instance
  Registration? _registration;

  /// Whether this device's service is registered
  bool _isRegistered = false;
  bool get isRegistered => _isRegistered;

  /// Whether discovery is currently running
  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  /// Discovered xPass services on the network
  final Map<String, Service> _discoveredServices = {};
  List<Service> get discoveredServices => _discoveredServices.values.toList();

  /// Stream controller for discovered devices
  final _discoveredDevicesController =
      StreamController<List<PairedDevice>>.broadcast();
  Stream<List<PairedDevice>> get onDevicesDiscovered =>
      _discoveredDevicesController.stream;

  /// Stream controller for discovery status changes
  final _discoveryStatusController = StreamController<bool>.broadcast();
  Stream<bool> get onDiscoveryStatusChanged =>
      _discoveryStatusController.stream;

  /// This device's ID (set during registration)
  String? _deviceId;

  /// This device's name (set during registration)
  String? _deviceName;

  /// Current account name for sync
  String? _currentAccountName;

  /// Server socket for receiving connections
  ServerSocket? _serverSocket;

  /// Current port the service is running on
  int? _currentPort;
  int? get currentPort => _currentPort;

  /// Callback for when a sync is completed via incoming connection
  Function(SyncLogEntry)? onSyncCompleted;

  /// Register this device on the network for discovery
  Future<bool> registerService({
    required String deviceId,
    required String deviceName,
    int? port,
    String? accountName,
  }) async {
    if (_isRegistered) {
      print('Service already registered');
      return true;
    }

    _deviceId = deviceId;
    _deviceName = deviceName;
    _currentAccountName = accountName;

    try {
      // Start a server socket to get an available port
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _currentPort = _serverSocket!.port;

      print('Started sync server on port $_currentPort');

      // Handle incoming connections
      _serverSocket!.listen((socket) {
        _handleIncomingConnection(socket);
      });

      // Create service name with device ID for identification
      final serviceName = '$serviceNamePrefix-$deviceId';

      // Register the service with mDNS
      // TXT records must be Uint8List, so we encode strings
      _registration = await register(
        Service(
          name: serviceName,
          type: serviceType,
          port: _currentPort!,
          txt: {
            'deviceName': Uint8List.fromList(utf8.encode(deviceName)),
            'deviceId': Uint8List.fromList(utf8.encode(deviceId)),
            'version': Uint8List.fromList(utf8.encode('1')),
          },
        ),
      );

      _isRegistered = true;
      notifyListeners();

      print('Registered mDNS service: $serviceName on port $_currentPort');

      // Start continuous discovery after registration
      await startDiscoveryService();

      return true;
    } catch (e) {
      print('Error registering mDNS service: $e');
      await _cleanup();
      return false;
    }
  }

  /// Handle incoming socket connection for sync
  void _handleIncomingConnection(Socket socket) async {
    print(
      'Incoming sync connection from ${socket.remoteAddress.address}:${socket.remotePort}',
    );

    try {
      // Try to ensure vault is loaded for sync (auto-load if needed)
      final kdbxService = KdbxService();

      if (!kdbxService.isVaultLoaded) {
        print(
          'Vault not loaded, attempting to auto-load for background sync...',
        );
        final loaded = await kdbxService.ensureVaultLoadedForSync();

        if (!loaded) {
          print('=== SYNC ERROR: Cannot load vault for sync ===');
          print(
            'No stored password available. User must unlock vault at least once.',
          );

          // Send error message to the sender
          final errorMsg = SyncMessage(
            type: SyncMessageType.error,
            deviceId: _deviceId ?? 'unknown',
            data: {
              'message':
                  'Cannot auto-load vault on receiving device. Please unlock the vault at least once to enable background sync.',
            },
          );
          socket.write('${errorMsg.toJsonString()}\n');
          await socket.flush();
          await socket.close();

          // Notify about failed sync
          if (onSyncCompleted != null) {
            onSyncCompleted!(
              SyncLogEntry(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                timestamp: DateTime.now(),
                deviceId: 'unknown',
                deviceName: 'Unknown',
                accountName: _currentAccountName ?? 'Unknown',
                items: [],
                success: false,
                errorMessage:
                    'Cannot auto-load vault - unlock vault at least once',
              ),
            );
          }
          return;
        }
        print('Vault auto-loaded successfully for background sync');
      }

      // Import sync engine here to handle the sync
      final syncEngine = SyncEngine();

      if (_deviceId == null || _deviceName == null) {
        print('Cannot handle sync: device info not set');
        socket.close();
        return;
      }

      final syncLog = await syncEngine.handleIncomingSync(
        socket,
        _deviceId!,
        _deviceName!,
        _currentAccountName ?? 'Unknown',
      );

      // Notify about completed sync
      if (onSyncCompleted != null) {
        onSyncCompleted!(syncLog);
      }

      print(
        'Incoming sync completed: ${syncLog.success ? "success" : "failed"}',
      );
    } catch (e) {
      print('Error handling incoming connection: $e');
      try {
        socket.close();
      } catch (_) {}
    }
  }

  /// Unregister this device from the network
  Future<void> unregisterService() async {
    if (!_isRegistered) return;

    try {
      if (_registration != null) {
        await unregister(_registration!);
        _registration = null;
      }

      await _cleanup();

      _isRegistered = false;
      notifyListeners();

      print('Unregistered mDNS service');
    } catch (e) {
      print('Error unregistering mDNS service: $e');
    }
  }

  /// Cleanup server socket
  Future<void> _cleanup() async {
    await _serverSocket?.close();
    _serverSocket = null;
    _currentPort = null;
  }

  /// Start discovering xPass devices on the network
  Future<void> startDiscoveryService() async {
    if (_isDiscovering) {
      print('Discovery already running');
      return;
    }

    try {
      _isDiscovering = true;
      _discoveredServices.clear();
      _discoveryStatusController.add(true);
      notifyListeners();

      print('Starting mDNS discovery for $serviceType...');

      _discovery = await startDiscovery(serviceType);

      _discovery!.addServiceListener((service, status) {
        _onServiceDiscovered(service, status);
      });

      print('mDNS discovery started successfully');
    } catch (e) {
      print('Error starting mDNS discovery: $e');
      _isDiscovering = false;
      _discoveryStatusController.add(false);
      notifyListeners();
    }
  }

  /// Handle discovered service
  void _onServiceDiscovered(Service service, ServiceStatus status) {
    final serviceName = service.name ?? '';

    print('Service event: $serviceName, status: $status');
    print(
      '  Full service: name=${service.name}, host=${service.host}, port=${service.port}',
    );

    // Ignore our own service
    if (_deviceId != null && serviceName.contains(_deviceId!)) {
      print('Ignoring own service: $serviceName');
      return;
    }

    // Check if this is an xPass service
    if (!serviceName.startsWith(serviceNamePrefix)) {
      print('Ignoring non-xpass service: $serviceName');
      return;
    }

    if (status == ServiceStatus.found) {
      print('Discovered xPass service: $serviceName');
      print('  Host: ${service.host}');
      print('  Port: ${service.port}');
      print('  TXT: ${service.txt}');

      // Store the service - we'll resolve the host later if needed
      _discoveredServices[serviceName] = service;

      // Notify about discovery change
      _notifyDiscoveryChange();
    } else if (status == ServiceStatus.lost) {
      print('Lost xPass service: $serviceName');
      _discoveredServices.remove(serviceName);

      // Notify about discovery change
      _notifyDiscoveryChange();
    }

    notifyListeners();
  }

  /// Notify listeners about discovered devices
  void _notifyDiscoveryChange() {
    // Extract device IDs from discovered services
    final discoveredDeviceIds = <String>[];
    for (final service in _discoveredServices.values) {
      final serviceName = service.name ?? '';
      if (serviceName.startsWith('$serviceNamePrefix-')) {
        final deviceId = serviceName.replaceFirst('$serviceNamePrefix-', '');
        discoveredDeviceIds.add(deviceId);
      }
    }
    print('Currently discovered device IDs: $discoveredDeviceIds');
  }

  /// Stop discovering devices
  Future<void> stopDiscoveryService() async {
    if (!_isDiscovering) return;

    try {
      if (_discovery != null) {
        await stopDiscovery(_discovery!);
        _discovery = null;
      }

      _isDiscovering = false;
      _discoveryStatusController.add(false);
      notifyListeners();

      print('mDNS discovery stopped');
    } catch (e) {
      print('Error stopping mDNS discovery: $e');
    }
  }

  /// Helper to decode TXT record value
  String? _decodeTxtValue(Uint8List? bytes) {
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  /// Discover devices and match against paired devices list
  /// Returns only paired devices that are currently online
  Future<List<PairedDevice>> discoverPairedDevices(
    List<PairedDevice> pairedDevices, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (pairedDevices.isEmpty) {
      print('No paired devices to discover');
      return [];
    }

    print(
      'Starting device discovery for ${pairedDevices.length} paired devices...',
    );

    // Start discovery if not already running
    if (!_isDiscovering) {
      await startDiscoveryService();
      // Wait for discovery to find devices
      print('Waiting $timeout for mDNS discovery...');
      await Future.delayed(timeout);
    } else {
      // If already discovering, just wait a bit for any new services
      print('Discovery already running, waiting for updates...');
      await Future.delayed(const Duration(seconds: 2));
    }

    // Match discovered services with paired devices
    final onlineDevices = <PairedDevice>[];

    print(
      'Checking ${_discoveredServices.length} discovered services against ${pairedDevices.length} paired devices',
    );

    // Debug: print all discovered services
    for (final entry in _discoveredServices.entries) {
      print(
        '  Service: ${entry.key} -> host=${entry.value.host}, port=${entry.value.port}',
      );
    }

    for (final service in _discoveredServices.values) {
      final serviceName = service.name ?? '';
      final txt = service.txt ?? {};

      // Extract device ID from service name or TXT record
      String? discoveredDeviceId;
      if (serviceName.startsWith('$serviceNamePrefix-')) {
        discoveredDeviceId = serviceName.replaceFirst(
          '$serviceNamePrefix-',
          '',
        );
      } else if (txt.containsKey('deviceId')) {
        discoveredDeviceId = _decodeTxtValue(txt['deviceId']);
      }

      if (discoveredDeviceId == null) {
        print('Could not extract device ID from service: $serviceName');
        continue;
      }

      // Get host - might need to resolve it
      String? host = service.host;
      int? port = service.port;

      // Try to get host from TXT record if not available
      if (host == null || host.isEmpty) {
        // Try to resolve the service
        print('Host is null for $serviceName, trying to resolve...');
        try {
          final resolved = await resolve(service);
          host = resolved.host;
          port = resolved.port;
          print('Resolved $serviceName to $host:$port');
        } catch (e) {
          print('Failed to resolve $serviceName: $e');
          continue;
        }
      }

      print(
        'Discovered device ID: $discoveredDeviceId, host: $host, port: $port',
      );

      // Check if this device is in our paired list
      for (final pairedDevice in pairedDevices) {
        if (pairedDevice.id == discoveredDeviceId) {
          // Found a paired device that's online!
          final onlineDevice = pairedDevice.copyWith(
            isOnline: true,
            ipAddress: host,
            port: port,
          );
          onlineDevice.lastSeen = DateTime.now();
          onlineDevices.add(onlineDevice);
          print(
            'Found online paired device: ${pairedDevice.name} at $host:$port',
          );
          break;
        }
      }
    }

    print(
      'Discovery complete: found ${onlineDevices.length} online paired devices',
    );

    // Notify listeners about discovered devices
    _discoveredDevicesController.add(onlineDevices);

    return onlineDevices;
  }

  /// Get the list of currently discovered paired devices (without waiting)
  List<PairedDevice> getOnlinePairedDevices(List<PairedDevice> pairedDevices) {
    final onlineDevices = <PairedDevice>[];

    for (final service in _discoveredServices.values) {
      final serviceName = service.name ?? '';

      String? discoveredDeviceId;
      if (serviceName.startsWith('$serviceNamePrefix-')) {
        discoveredDeviceId = serviceName.replaceFirst(
          '$serviceNamePrefix-',
          '',
        );
      }

      if (discoveredDeviceId == null) continue;

      for (final pairedDevice in pairedDevices) {
        if (pairedDevice.id == discoveredDeviceId) {
          // Use cached host/port from service
          final host = service.host;
          final port = service.port;

          final onlineDevice = pairedDevice.copyWith(
            isOnline: true,
            ipAddress: host,
            port: port,
          );
          onlineDevice.lastSeen = DateTime.now();
          onlineDevices.add(onlineDevice);
          break;
        }
      }
    }

    return onlineDevices;
  }

  /// Force refresh discovery - stop and restart
  Future<void> refreshDiscovery() async {
    print('Refreshing mDNS discovery...');
    await stopDiscoveryService();
    _discoveredServices.clear();
    await Future.delayed(const Duration(milliseconds: 500));
    await startDiscoveryService();
  }

  /// Get connection info for a discovered service
  Future<(String host, int port)?> getServiceConnectionInfo(
    String deviceId,
  ) async {
    final serviceName = '$serviceNamePrefix-$deviceId';
    final service = _discoveredServices[serviceName];

    if (service == null) {
      print('Service not found for device: $deviceId');
      return null;
    }

    final host = service.host;
    final port = service.port;

    if (host == null || port == null) {
      print('Service missing host or port: $deviceId');
      return null;
    }

    return (host, port);
  }

  /// Clean up resources
  @override
  void dispose() {
    stopDiscoveryService();
    unregisterService();
    _discoveredDevicesController.close();
    _discoveryStatusController.close();
    super.dispose();
  }
}
