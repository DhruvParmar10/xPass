/// Overall sync system state
enum SyncState {
  /// Sync is idle, not doing anything
  idle,

  /// Looking for devices on the network
  discovering,

  /// Currently syncing with one or more devices
  syncing,

  /// Sync is paused (user preference or background)
  paused,

  /// An error occurred during sync
  error,
}

/// Result of a sync operation
enum SyncResult {
  /// Sync completed successfully
  success,

  /// No paired devices found online
  noDevicesFound,

  /// Not on a trusted network
  notOnTrustedNetwork,

  /// No vault is currently open
  noVaultLoaded,

  /// Network error during sync
  networkError,

  /// Sync was cancelled by user
  cancelled,

  /// Sync failed due to conflict
  conflictError,

  /// Unknown error
  unknownError,
}

/// Data being transferred during sync
class SyncProgress {
  /// Current phase of sync
  final String phase;

  /// Progress percentage (0-100)
  final int progress;

  /// Device currently syncing with
  final String? currentDevice;

  /// Current entry being synced
  final String? currentEntry;

  const SyncProgress({
    required this.phase,
    required this.progress,
    this.currentDevice,
    this.currentEntry,
  });

  static const SyncProgress initial = SyncProgress(
    phase: 'Initializing',
    progress: 0,
  );

  SyncProgress copyWith({
    String? phase,
    int? progress,
    String? currentDevice,
    String? currentEntry,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      currentDevice: currentDevice ?? this.currentDevice,
      currentEntry: currentEntry ?? this.currentEntry,
    );
  }

  @override
  String toString() {
    return 'SyncProgress(phase: $phase, progress: $progress%)';
  }
}
