import 'dart:io';
import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/sync/sync_services.dart';
import '../../models/sync/sync_models.dart';

/// Main sync settings and status screen
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final SyncManager _syncManager = SyncManager();
  final NetworkMonitor _networkMonitor = NetworkMonitor();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _syncManager.addListener(_onSyncStateChanged);
    _networkMonitor.addListener(_onNetworkChanged);
    _syncManager.discoveryService.addListener(_onDiscoveryChanged);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _networkMonitor.initialize();
    await _syncManager.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _syncManager.removeListener(_onSyncStateChanged);
    _networkMonitor.removeListener(_onNetworkChanged);
    _syncManager.discoveryService.removeListener(_onDiscoveryChanged);
    super.dispose();
  }

  void _onSyncStateChanged() {
    if (mounted) setState(() {});
  }

  void _onNetworkChanged() {
    if (mounted) setState(() {});
  }

  void _onDiscoveryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isInitialized) {
      return Scaffold(
        headers: [
          AppBar(
            title: const Text('Sync Settings'),
            leading: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
                variance: ButtonVariance.ghost,
              ),
            ],
          ),
        ],
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Sync Settings'),
          leading: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              variance: ButtonVariance.ghost,
            ),
          ],
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Network Status Card
            _buildNetworkStatusCard(theme),
            const SizedBox(height: 16),

            // Sync Status Card
            _buildSyncStatusCard(theme),
            const SizedBox(height: 16),

            // Paired Devices Section
            _buildPairedDevicesSection(theme),
            const SizedBox(height: 16),

            // Trusted Networks Section
            _buildTrustedNetworksSection(theme),
            const SizedBox(height: 16),

            // Settings Section
            _buildSettingsSection(theme),
            const SizedBox(height: 16),

            // Actions Section
            _buildActionsSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkStatusCard(ThemeData theme) {
    final currentSSID = _networkMonitor.currentSSID;
    final isConnected = currentSSID != null && currentSSID.isNotEmpty;
    final isTrusted = _networkMonitor.isOnTrustedNetwork;
    final needsPermission =
        (Platform.isMacOS || Platform.isIOS || Platform.isAndroid) &&
        !isConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected
                      ? (isTrusted
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF97316))
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Network Status', style: theme.typography.semiBold),
                      const SizedBox(height: 4),
                      Text(
                        isConnected
                            ? 'Connected to $currentSSID'
                            : 'WiFi name unavailable',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isConnected && !isTrusted)
                  OutlineButton(
                    onPressed: () => _markCurrentNetworkTrusted(),
                    size: ButtonSize.small,
                    child: const Text('Trust'),
                  ),
              ],
            ),
            if (needsPermission && Platform.isAndroid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 20,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location permission is required to detect WiFi network name on Android',
                            style: theme.typography.small.copyWith(
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      onPressed: () async {
                        final granted = await _networkMonitor
                            .requestLocationPermission();
                        if (granted) {
                          await _networkMonitor.refresh();
                          setState(() {});
                        }
                      },
                      size: ButtonSize.small,
                      child: const Text('Grant Permission'),
                    ),
                  ],
                ),
              ),
            ],
            if (needsPermission && Platform.isMacOS) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 20,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location permission is required to detect WiFi network name',
                            style: theme.typography.small.copyWith(
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      onPressed: () async {
                        final granted = await _networkMonitor
                            .requestLocationPermission();
                        if (granted) {
                          await _networkMonitor.refresh();
                          setState(() {});
                        }
                      },
                      size: ButtonSize.small,
                      child: const Text('Grant Location Permission'),
                    ),
                  ],
                ),
              ),
            ],
            if (isTrusted) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '✓ Trusted Network - Sync Enabled',
                  style: theme.typography.small.copyWith(
                    color: const Color(0xFF22C55E),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard(ThemeData theme) {
    final state = _syncManager.state;
    final progress = _syncManager.progress;
    final lastSync = _syncManager.lastSyncTime;
    final lastResult = _syncManager.lastResult;
    final discoveryService = _syncManager.discoveryService;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (state) {
      case SyncState.idle:
        if (lastResult == SyncResult.notOnTrustedNetwork) {
          statusText = 'Not on trusted network';
          statusColor = const Color(0xFFF97316);
          statusIcon = Icons.wifi_off;
        } else if (lastResult == SyncResult.noVaultLoaded) {
          statusText = 'No vault open - unlock to sync';
          statusColor = const Color(0xFFF97316);
          statusIcon = Icons.lock;
        } else if (lastResult == SyncResult.noDevicesFound) {
          statusText = 'No devices found';
          statusColor = const Color(0xFF9CA3AF);
          statusIcon = Icons.devices;
        } else {
          statusText = 'Ready';
          statusColor = const Color(0xFF22C55E);
          statusIcon = Icons.check_circle;
        }
        break;
      case SyncState.discovering:
        statusText = 'Discovering devices...';
        statusColor = const Color(0xFF3B82F6);
        statusIcon = Icons.search;
        break;
      case SyncState.syncing:
        statusText = progress.phase;
        statusColor = const Color(0xFF3B82F6);
        statusIcon = Icons.sync;
        break;
      case SyncState.error:
        statusText = 'Error occurred';
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.error;
        break;
      case SyncState.paused:
        statusText = 'Paused';
        statusColor = const Color(0xFFF97316);
        statusIcon = Icons.pause_circle;
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sync Status', style: theme.typography.semiBold),
                      const SizedBox(height: 4),
                      Text(
                        statusText,
                        style: theme.typography.small.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state == SyncState.idle)
                  PrimaryButton(
                    onPressed:
                        _networkMonitor.isOnTrustedNetwork &&
                            _syncManager.hasPairedDevices
                        ? () async {
                            final result = await _syncManager.triggerSync();
                            if (mounted) {
                              String message;
                              switch (result) {
                                case SyncResult.success:
                                  message = 'Sync completed successfully';
                                  break;
                                case SyncResult.noDevicesFound:
                                  message = 'No paired devices found online';
                                  break;
                                case SyncResult.notOnTrustedNetwork:
                                  message =
                                      'Not connected to a trusted network';
                                  break;
                                case SyncResult.noVaultLoaded:
                                  message =
                                      'Please unlock your vault first to sync';
                                  break;
                                case SyncResult.networkError:
                                  message = 'Network error during sync';
                                  break;
                                case SyncResult.cancelled:
                                  message = 'Sync was cancelled';
                                  break;
                                default:
                                  message = 'Sync completed';
                              }
                              showToast(
                                context: context,
                                builder: (context, overlay) => SurfaceCard(
                                  child: Basic(title: Text(message)),
                                ),
                              );
                            }
                          }
                        : null,
                    size: ButtonSize.small,
                    child: const Text('Sync Now'),
                  ),
              ],
            ),
            if (state == SyncState.syncing ||
                state == SyncState.discovering) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: material.LinearProgressIndicator(
                    value: progress.progress / 100,
                  ),
                ),
              ),
            ],
            if (lastSync != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last sync: ${_formatDateTime(lastSync)}',
                style: theme.typography.small.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
            // Show discovery status
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: discoveryService.isDiscovering
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF9CA3AF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    discoveryService.isDiscovering
                        ? 'Discovery active (${discoveryService.discoveredServices.length} services)'
                        : 'Discovery inactive',
                    style: theme.typography.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                if (!discoveryService.isDiscovering ||
                    discoveryService.discoveredServices.isEmpty)
                  OutlineButton(
                    onPressed: () async {
                      await _syncManager.forceStartDiscovery();
                      setState(() {});
                      showToast(
                        context: context,
                        builder: (context, overlay) => SurfaceCard(
                          child: Basic(title: Text('Discovery started')),
                        ),
                      );
                    },
                    size: ButtonSize.small,
                    child: const Text('Start Discovery'),
                  ),
              ],
            ),
            // Show device ID for debugging
            const SizedBox(height: 8),
            Text(
              'Device ID: ${_syncManager.deviceId ?? "unknown"}',
              style: theme.typography.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedDevicesSection(ThemeData theme) {
    final devices = _syncManager.pairedDevices;
    final onlineDevices = _syncManager.onlineDevices;
    final discoveryService = _syncManager.discoveryService;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Paired Devices', style: theme.typography.semiBold),
                Row(
                  children: [
                    if (devices.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          size: 20,
                          color: discoveryService.isDiscovering
                              ? theme.colorScheme.primary
                              : theme.colorScheme.mutedForeground,
                        ),
                        onPressed: () async {
                          // Force refresh device discovery
                          if (_networkMonitor.isOnTrustedNetwork) {
                            await _syncManager.discoveryService
                                .discoverPairedDevices(devices);
                            setState(() {});
                          }
                        },
                        variance: ButtonVariance.ghost,
                      ),
                    const SizedBox(width: 4),
                    OutlineButton(
                      onPressed: _navigateToPairing,
                      size: ButtonSize.small,
                      leading: const Icon(Icons.add, size: 16),
                      child: const Text('Pair'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.devices,
                        size: 48,
                        color: theme.colorScheme.mutedForeground,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No paired devices',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pair a device to start syncing',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...devices.map((device) {
                final isOnline = onlineDevices.any((d) => d.id == device.id);
                return _buildDeviceListItem(theme, device, isOnline);
              }),
            if (devices.isNotEmpty && !_networkMonitor.isOnTrustedNetwork) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connect to a trusted network to see online devices',
                        style: theme.typography.small.copyWith(
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceListItem(
    ThemeData theme,
    PairedDevice device,
    bool isOnline,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.smartphone,
              color: isOnline
                  ? const Color(0xFF22C55E)
                  : theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: theme.typography.base),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF9CA3AF),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: theme.typography.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    if (device.lastSyncAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• Last sync: ${_formatRelativeTime(device.lastSyncAt!)}',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showDeviceOptions(device),
            variance: ButtonVariance.ghost,
          ),
        ],
      ),
    );
  }

  Widget _buildTrustedNetworksSection(ThemeData theme) {
    final networks = _networkMonitor.trustedNetworks;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trusted Networks', style: theme.typography.semiBold),
            const SizedBox(height: 4),
            Text(
              'Sync will only happen on these WiFi networks',
              style: theme.typography.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            if (networks.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No trusted networks.\nConnect to WiFi and tap "Trust" above.',
                    textAlign: TextAlign.center,
                    style: theme.typography.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: networks.map((network) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.muted,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(network.ssid, style: theme.typography.small),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _removeTrustedNetwork(network),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.typography.semiBold),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto Sync', style: theme.typography.base),
                      Text(
                        'Automatically sync when on trusted network',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                Checkbox(
                  state: _syncManager.autoSyncEnabled
                      ? CheckboxState.checked
                      : CheckboxState.unchecked,
                  onChanged: (state) =>
                      _syncManager.setAutoSync(state == CheckboxState.checked),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This Device', style: theme.typography.base),
                      Text(
                        _syncManager.deviceName ?? 'Unknown',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: _editDeviceName,
                  variance: ButtonVariance.ghost,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions', style: theme.typography.semiBold),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _navigateToSyncHistory,
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sync History', style: theme.typography.base),
                        Text(
                          'View sync logs and changes',
                          style: theme.typography.small.copyWith(
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markCurrentNetworkTrusted() async {
    final ssid = _networkMonitor.currentSSID;
    if (ssid != null) {
      await _networkMonitor.addTrustedNetwork(ssid);
      setState(() {});
    }
  }

  // ignore: unused_element
  Future<void> _requestLocationPermission() async {
    final granted = await _networkMonitor.requestLocationPermission();
    if (granted) {
      // Refresh network status after permission granted
      await _networkMonitor.refresh();
      setState(() {});
    }
  }

  Future<void> _removeTrustedNetwork(TrustedNetwork network) async {
    await _networkMonitor.removeTrustedNetwork(network.ssid);
    setState(() {});
  }

  void _navigateToPairing() {
    Navigator.push(
      context,
      material.MaterialPageRoute(builder: (context) => const PairingScreen()),
    );
  }

  void _navigateToSyncHistory() {
    Navigator.push(
      context,
      material.MaterialPageRoute(
        builder: (context) => const SyncHistoryScreen(),
      ),
    );
  }

  Future<void> _showDeviceOptions(PairedDevice device) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(device.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _renameDevice(device);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.edit),
                    const SizedBox(width: 12),
                    const Text('Rename'),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _unpairDevice(device);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.delete, color: const Color(0xFFEF4444)),
                    const SizedBox(width: 12),
                    Text(
                      'Unpair',
                      style: TextStyle(color: const Color(0xFFEF4444)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDevice(PairedDevice device) async {
    final controller = TextEditingController(text: device.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(controller: controller),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _syncManager.updateDeviceName(device.id, newName);
      setState(() {});
    }
  }

  Future<void> _unpairDevice(PairedDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair Device?'),
        content: Text('Are you sure you want to unpair "${device.name}"?'),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _syncManager.removePairedDevice(device.id);
      setState(() {});
    }
  }

  Future<void> _editDeviceName() async {
    final controller = TextEditingController(text: _syncManager.deviceName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device Name'),
        content: TextField(controller: controller),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _syncManager.setDeviceName(newName);
      setState(() {});
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    return _formatDateTime(dateTime);
  }
}

/// Pairing screen - allows devices to pair via QR code or manual code
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final PairingService _pairingService = PairingService();
  int _selectedTabIndex = 0;

  // For manual code entry
  final TextEditingController _manualCodeController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pairingService.addListener(_onPairingStateChanged);
  }

  @override
  void dispose() {
    _manualCodeController.dispose();
    _pairingService.removeListener(_onPairingStateChanged);
    _pairingService.cancelPairing();
    super.dispose();
  }

  void _onPairingStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Pair Device'),
          leading: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _pairingService.cancelPairing();
                Navigator.pop(context);
              },
              variance: ButtonVariance.ghost,
            ),
          ],
        ),
      ],
      child: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.muted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTabIndex == 0
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Show QR Code',
                          textAlign: TextAlign.center,
                          style: theme.typography.small.copyWith(
                            color: _selectedTabIndex == 0
                                ? theme.colorScheme.primaryForeground
                                : theme.colorScheme.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTabIndex == 1
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Scan / Enter Code',
                          textAlign: TextAlign.center,
                          style: theme.typography.small.copyWith(
                            color: _selectedTabIndex == 1
                                ? theme.colorScheme.primaryForeground
                                : theme.colorScheme.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tab content
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [_buildShowQRTab(theme), _buildScanTab(theme)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowQRTab(ThemeData theme) {
    final pairingData = _pairingService.currentPairingData;
    final state = _pairingService.state;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (state == PairingState.idle) ...[
                    Icon(
                      Icons.qr_code_2,
                      size: 64,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    const SizedBox(height: 16),
                    Text('Generate QR Code', style: theme.typography.h4),
                    const SizedBox(height: 8),
                    Text(
                      'Generate a QR code that another device can scan to pair with this device.',
                      textAlign: TextAlign.center,
                      style: theme.typography.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      onPressed: _generateQRCode,
                      child: const Text('Generate QR Code'),
                    ),
                  ] else if (state == PairingState.generatingQR) ...[
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Generating...',
                      style: theme.typography.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ] else if (state == PairingState.waitingForScan &&
                      pairingData != null) ...[
                    // QR Code display
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: pairingData.toQRString(),
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scan this QR code with another device',
                      style: theme.typography.semiBold,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Or enter this code manually:',
                      style: theme.typography.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Manual pairing code (shortened token)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.muted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        pairingData.pairingToken.substring(0, 8).toUpperCase(),
                        style: theme.typography.mono.copyWith(
                          fontSize: 18,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Device info
                    _buildDeviceInfo(theme, pairingData),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Expires in 5 minutes',
                          style: theme.typography.small.copyWith(
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlineButton(
                      onPressed: () {
                        _pairingService.cancelPairing();
                      },
                      child: const Text('Cancel'),
                    ),
                  ] else if (state == PairingState.completed) ...[
                    Icon(
                      Icons.check_circle,
                      size: 64,
                      color: const Color(0xFF22C55E),
                    ),
                    const SizedBox(height: 16),
                    Text('Pairing Successful!', style: theme.typography.h4),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      onPressed: () {
                        _pairingService.resetState();
                        Navigator.pop(context);
                      },
                      child: const Text('Done'),
                    ),
                  ] else if (state == PairingState.failed) ...[
                    Icon(Icons.error, size: 64, color: const Color(0xFFEF4444)),
                    const SizedBox(height: 16),
                    Text('Pairing Failed', style: theme.typography.h4),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      onPressed: () {
                        _pairingService.resetState();
                      },
                      child: const Text('Try Again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo(ThemeData theme, PairingData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildInfoRow(theme, 'Device', data.deviceName),
          const Divider(height: 16),
          _buildInfoRow(theme, 'IP Address', data.ipAddress),
          const Divider(height: 16),
          _buildInfoRow(theme, 'Port', data.port.toString()),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.typography.small.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        Text(value, style: theme.typography.small),
      ],
    );
  }

  Widget _buildScanTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // QR Scanner section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan QR Code', style: theme.typography.semiBold),
                  const SizedBox(height: 8),
                  Text(
                    'Point your camera at the QR code displayed on the other device.',
                    style: theme.typography.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // QR Scanner placeholder - actual scanner requires camera
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.muted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 48,
                            color: theme.colorScheme.mutedForeground,
                          ),
                          const SizedBox(height: 8),
                          PrimaryButton(
                            onPressed: _openQRScanner,
                            child: const Text('Open Scanner'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Manual code entry
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter Code Manually', style: theme.typography.semiBold),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 8-character code shown on the other device.',
                    style: theme.typography.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualCodeController,
                          placeholder: const Text(
                            'Enter code (e.g., ABCD1234)',
                          ),
                          style: theme.typography.mono,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PrimaryButton(
                        onPressed: _isProcessing ? null : _processManualCode,
                        child: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Connect'),
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: theme.typography.small.copyWith(
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateQRCode() async {
    await _pairingService.generatePairingQR();
    if (_pairingService.state == PairingState.waitingForScan) {
      // Wait for scan in background
      _pairingService.waitForPairing().then((result) {
        if (result.success && mounted) {
          // Pairing successful
          setState(() {});
        }
      });
    }
  }

  Future<void> _openQRScanner() async {
    // Navigate to QR scanner screen
    final result = await Navigator.push<String>(
      context,
      material.MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && mounted) {
      await _processPairingData(result);
    }
  }

  Future<void> _processManualCode() async {
    final code = _manualCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a code';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Manual code entry would need to discover the device via mDNS
    // and match the pairing token prefix
    // For now, show a message that this requires the full QR scan
    setState(() {
      _isProcessing = false;
      _errorMessage =
          'Manual code entry requires both devices to be on the same network. Use QR scan for easier pairing.';
    });
  }

  Future<void> _processPairingData(String qrData) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final result = await _pairingService.processPairingQR(qrData);

    setState(() {
      _isProcessing = false;
    });

    if (result.success && mounted) {
      // Show success and go back
      Navigator.pop(context);
    } else {
      setState(() {
        _errorMessage = result.errorMessage ?? 'Pairing failed';
      });
    }
  }
}

/// QR Scanner screen for scanning pairing QR codes
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController? _controller;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.contains('deviceId')) {
        // Looks like a valid pairing QR
        _hasScanned = true;
        Navigator.pop(context, value);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Scan QR Code'),
          leading: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              variance: ButtonVariance.ghost,
            ),
          ],
          trailing: [
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller?.toggleTorch(),
              variance: ButtonVariance.ghost,
            ),
          ],
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Point the camera at the QR code on the other device',
              textAlign: TextAlign.center,
              style: theme.typography.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sync history screen - shows last 20 sync entries
class SyncHistoryScreen extends StatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  final SyncManager _syncManager = SyncManager();

  @override
  void initState() {
    super.initState();
    _syncManager.addListener(_onSyncManagerChanged);
  }

  @override
  void dispose() {
    _syncManager.removeListener(_onSyncManagerChanged);
    super.dispose();
  }

  void _onSyncManagerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Get last 20 logs, newest first
    final logs = _syncManager.syncLogs.reversed.take(20).toList();

    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Sync History'),
          leading: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              variance: ButtonVariance.ghost,
            ),
          ],
          trailing: [
            if (logs.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmClearHistory(context),
                variance: ButtonVariance.ghost,
              ),
          ],
        ),
      ],
      child: logs.isEmpty
          ? _buildEmptyState(theme)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildLogEntry(theme, logs[index]);
              },
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 16),
            Text('No Sync History', style: theme.typography.h4),
            const SizedBox(height: 8),
            Text(
              'Your sync history will appear here after you sync with other devices.',
              textAlign: TextAlign.center,
              style: theme.typography.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogEntry(ThemeData theme, SyncLogEntry log) {
    final addedCount = log.items
        .where((i) => i.action == SyncAction.added)
        .length;
    final modifiedCount = log.items
        .where((i) => i.action == SyncAction.modified)
        .length;
    final deletedCount = log.items
        .where((i) => i.action == SyncAction.deleted)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(
                  log.success ? Icons.check_circle : Icons.error,
                  color: log.success
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.deviceName, style: theme.typography.semiBold),
                      Text(
                        _formatTimestamp(log.timestamp),
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: log.success
                        ? const Color(0xFF22C55E).withAlpha(25)
                        : const Color(0xFFEF4444).withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.success ? 'Success' : 'Failed',
                    style: theme.typography.small.copyWith(
                      color: log.success
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Account info
            Row(
              children: [
                Icon(
                  Icons.account_circle,
                  size: 16,
                  color: theme.colorScheme.mutedForeground,
                ),
                const SizedBox(width: 4),
                Text(
                  log.accountName,
                  style: theme.typography.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Changes summary
            if (log.success) ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (addedCount > 0)
                    _buildChangeChip(
                      theme,
                      Icons.add,
                      '$addedCount added',
                      const Color(0xFF22C55E),
                    ),
                  if (modifiedCount > 0)
                    _buildChangeChip(
                      theme,
                      Icons.edit,
                      '$modifiedCount modified',
                      const Color(0xFF3B82F6),
                    ),
                  if (deletedCount > 0)
                    _buildChangeChip(
                      theme,
                      Icons.delete,
                      '$deletedCount deleted',
                      const Color(0xFFEF4444),
                    ),
                  if (addedCount == 0 &&
                      modifiedCount == 0 &&
                      deletedCount == 0)
                    _buildChangeChip(
                      theme,
                      Icons.check,
                      'No changes',
                      theme.colorScheme.mutedForeground,
                    ),
                ],
              ),
            ] else ...[
              Text(
                log.errorMessage ?? 'Unknown error',
                style: theme.typography.small.copyWith(
                  color: const Color(0xFFEF4444),
                ),
              ),
            ],
            // Expandable details
            if (log.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showLogDetails(context, log),
                child: Row(
                  children: [
                    Text(
                      'View details',
                      style: theme.typography.small.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChangeChip(
    ThemeData theme,
    IconData icon,
    String label,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: theme.typography.small.copyWith(color: color)),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} hours ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  void _showLogDetails(BuildContext context, SyncLogEntry log) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sync Details'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device: ${log.deviceName}', style: theme.typography.small),
              Text(
                'Account: ${log.accountName}',
                style: theme.typography.small,
              ),
              Text(
                'Time: ${_formatTimestamp(log.timestamp)}',
                style: theme.typography.small,
              ),
              const SizedBox(height: 16),
              Text('Changes:', style: theme.typography.semiBold),
              const SizedBox(height: 8),
              if (log.items.isEmpty)
                Text(
                  'No changes',
                  style: theme.typography.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: log.items.length,
                    itemBuilder: (context, index) {
                      final item = log.items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              item.action == SyncAction.added
                                  ? Icons.add
                                  : item.action == SyncAction.modified
                                  ? Icons.edit
                                  : Icons.delete,
                              size: 14,
                              color: item.action == SyncAction.added
                                  ? const Color(0xFF22C55E)
                                  : item.action == SyncAction.modified
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.entryTitle,
                                style: theme.typography.small,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          PrimaryButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Sync History?'),
        content: const Text(
          'This will permanently delete all sync history. This action cannot be undone.',
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () {
              _syncManager.clearSyncLogs();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
