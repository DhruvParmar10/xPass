# xPass Synchronization System - Technical Architecture

## Table of Contents

- [Overview](#overview)
- [Architecture Design](#architecture-design)
- [Core Components](#core-components)
- [Synchronization Workflow](#synchronization-workflow)
- [Security Model](#security-model)
- [Network Discovery](#network-discovery)
- [Conflict Resolution](#conflict-resolution)
- [Implementation Details](#implementation-details)

---

## Overview

The xPass Synchronization System is a privacy-first, peer-to-peer solution designed to keep password vaults in sync across multiple devices without relying on cloud infrastructure. The system uses zero-configuration networking protocols to enable automatic synchronization when devices are on trusted networks, while maintaining enterprise-grade security through KDBX encryption and device pairing mechanisms.

### Key Features

- **Zero-Configuration Discovery**: Automatic device detection using mDNS/Bonjour service discovery
- **Privacy-First Design**: No cloud servers, no third-party involvement, complete local network operation
- **Trusted Network Intelligence**: Automatic sync triggering when devices join pre-configured secure networks
- **QR Code Pairing**: One-time cryptographic device authentication through visual QR codes
- **Mesh Topology**: Full-mesh device communication allowing any paired device to sync with any other
- **Intelligent Conflict Resolution**: Timestamp-based merge algorithms with rollback capabilities
- **Background Sync Support**: Optional automatic synchronization without user intervention

---

## Architecture Design

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        XPASS SYNC ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌────────────────┐                                  ┌────────────────┐│
│  │  UI Layer      │                                  │  Data Layer    ││
│  ├────────────────┤                                  ├────────────────┤│
│  │ - Settings     │◄────┐                     ┌─────►│ KDBX Service   ││
│  │ - Device Mgmt  │     │                     │      │ - Vault Ops    ││
│  │ - Sync Logs    │     │                     │      │ - Encryption   ││
│  │ - QR Scanner   │     │                     │      └────────────────┘│
│  └────────────────┘     │                     │                        │
│                         │                     │                        │
│  ┌────────────────────────────────────────────────────────────┐        │
│  │              SYNC MANAGER (Orchestrator)                   │        │
│  │  - State Management                                        │        │
│  │  - Device Registry                                         │        │
│  │  - Sync Scheduling                                         │        │
│  │  - Progress Tracking                                       │        │
│  └────────────────────────────────────────────────────────────┘        │
│          │              │              │              │                 │
│  ┌───────▼──────┐ ┌────▼─────┐ ┌──────▼──────┐ ┌────▼────────┐       │
│  │ Network      │ │Discovery │ │   Sync      │ │  Pairing    │       │
│  │ Monitor      │ │ Service  │ │  Engine     │ │  Service    │       │
│  ├──────────────┤ ├──────────┤ ├─────────────┤ ├─────────────┤       │
│  │ - WiFi SSID  │ │ - mDNS   │ │ - Compare   │ │ - QR Gen    │       │
│  │ - Trusted    │ │ - Register│ │ - Merge     │ │ - QR Scan   │       │
│  │   Networks   │ │ - Discover│ │ - Transfer  │ │ - Crypto    │       │
│  │ - Monitoring │ │ - Announce│ │ - Conflict  │ │ - Verify    │       │
│  └──────────────┘ └──────────┘ └─────────────┘ └─────────────┘       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Hierarchy

```
lib/
├── services/sync/
│   ├── sync_manager.dart           # Primary orchestrator
│   ├── network_monitor.dart        # Network state & trusted WiFi detection
│   ├── discovery_service.dart      # mDNS device discovery
│   ├── sync_engine.dart           # Vault comparison & merge logic
│   └── pairing_service.dart       # QR-based device authentication
│
├── models/sync/
│   ├── sync_models.dart           # Core data structures
│   ├── paired_device.dart         # Device metadata & crypto keys
│   ├── trusted_network.dart       # WiFi network configuration
│   ├── sync_state.dart           # State machine definitions
│   └── sync_log_entry.dart       # Audit trail records
│
└── screens/sync/
    ├── sync_settings_screen.dart  # Main sync configuration UI
    └── sync_screens.dart          # Device pairing & management UI
```

---

## Core Components

### 1. Sync Manager (`sync_manager.dart`)

**Responsibilities:**

- Central orchestration of all sync operations
- State management and progress tracking
- Device registry maintenance
- Network event handling
- Automatic sync triggering
- Background sync coordination

**Key Methods:**

```dart
initialize()                    // Bootstrap sync system
pairDevice(PairingData)        // Register new paired device
unpairDevice(deviceId)         // Remove paired device
manualSync(deviceId)           // User-initiated sync
enableAutoSync()               // Enable automatic synchronization
addTrustedNetwork(ssid)        // Register trusted WiFi network
```

**State Machine:**

```
idle → discovering → pairing → syncing → [success|failed] → idle
```

### 2. Network Monitor (`network_monitor.dart`)

**Responsibilities:**

- Real-time WiFi SSID detection across platforms
- Trusted network verification
- Network change event streaming
- Location permission management (required for WiFi SSID)

**Platform-Specific Implementations:**

- **macOS**: CoreWLAN framework via method channel + system commands
- **iOS**: CoreLocation + Network framework
- **Android**: network_info_plus with location permissions
- **Linux/Windows**: Standard network interfaces

**Trusted Network Detection Flow:**

```
Network Change Event
    ↓
Get Current SSID (with permission handling)
    ↓
Compare with Trusted Networks List
    ↓
Emit Network Status (trusted/untrusted)
    ↓
Trigger Auto-Sync if trusted
```

### 3. Discovery Service (`discovery_service.dart`)

**Responsibilities:**

- mDNS/Bonjour service registration and discovery
- TCP socket server for incoming sync connections
- Service announcement with device metadata
- Continuous background listening

**Service Registration:**

```dart
Service Type: "_xpass-sync._tcp"
Service Name: "xpass-{deviceId}"
Port: Dynamic (auto-assigned)
TXT Records: {
  "deviceId": UUID,
  "deviceName": "User's MacBook",
  "accountName": "personal",
  "version": "1.0.0"
}
```

**Discovery Process:**

1. Register mDNS service on trusted network
2. Continuously scan for other xPass services
3. Match discovered devices with paired device registry
4. Notify sync manager of online devices
5. Accept incoming sync requests via TCP

### 4. Sync Engine (`sync_engine.dart`)

**Responsibilities:**

- KDBX vault comparison algorithms
- Entry-level diff computation
- Three-way merge logic
- Conflict detection and resolution
- Transactional sync application with rollback

**Sync Algorithm:**

```
1. Extract all entries from local vault
2. Receive all entries from remote vault
3. Compare by UUID and account key (title:username)
4. For each entry:
   - If exists only locally → Add to remote
   - If exists only remotely → Add to local
   - If exists in both:
     * Compare lastModified timestamps
     * If local newer → Update remote
     * If remote newer → Update local
     * If same timestamp but different data → CONFLICT
5. Handle conflicts per resolution strategy:
   - useNewer: Timestamp-based (default)
   - useLocal: Keep local version
   - useRemote: Keep remote version
   - keepBoth: Duplicate with suffix
6. Apply changes transactionally
7. Rollback on any error
```

**Conflict Resolution Strategies:**

```dart
enum SyncConflictResolution {
  useNewer,   // Use entry with latest timestamp (default)
  useLocal,   // Always prefer local changes
  useRemote,  // Always prefer remote changes
  keepBoth,   // Create duplicate entries
}
```

### 5. Pairing Service (`pairing_service.dart`)

**Responsibilities:**

- QR code generation for device pairing
- QR code scanning and validation
- Cryptographic device fingerprinting
- Pairing data serialization/deserialization

**Pairing Data Structure:**

```dart
class PairingData {
  String deviceId;           // UUID v4
  String deviceName;         // "John's iPhone"
  String accountName;        // "personal" | "work"
  DateTime timestamp;        // Pairing request time
  String? publicKey;         // Future: Encryption key
}
```

**QR Code Pairing Flow:**

```
Device A (Initiator)                    Device B (Receiver)
      │                                        │
      ├─ Generate PairingData                  │
      ├─ Encode to QR Code                     │
      ├─ Display QR Code ─────────────────────►├─ Scan QR Code
      │                                        ├─ Decode PairingData
      │                                        ├─ Validate timestamp (<5min)
      │                                        ├─ Show confirmation dialog
      │◄─────────────── Accept Pairing ────────┤
      ├─ Add to paired devices                 ├─ Add to paired devices
      ├─ Save to SharedPreferences             ├─ Save to SharedPreferences
      ├─ Register discovery service            ├─ Register discovery service
      └─ Auto-sync if on trusted network       └─ Auto-sync if on trusted network
```

---

## Synchronization Workflow

### Complete Sync Lifecycle

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      SYNC LIFECYCLE WORKFLOW                             │
└──────────────────────────────────────────────────────────────────────────┘

1. INITIALIZATION PHASE
   ├─ Load device identity (or generate UUID)
   ├─ Load paired devices from storage
   ├─ Load trusted networks from storage
   ├─ Initialize network monitor
   ├─ Check current network status
   └─ Register mDNS service if on trusted network

2. NETWORK DETECTION PHASE
   ├─ Monitor WiFi SSID changes
   ├─ Compare with trusted networks
   ├─ On trusted network detected:
   │  ├─ Register/refresh mDNS service
   │  ├─ Start discovery scanning
   │  └─ Enable auto-sync listeners
   └─ On untrusted network:
      ├─ Unregister mDNS service
      └─ Disable auto-sync

3. DEVICE DISCOVERY PHASE
   ├─ Broadcast mDNS service announcement
   ├─ Scan for "_xpass-sync._tcp" services
   ├─ Extract device metadata from TXT records
   ├─ Match discovered devices with paired registry
   ├─ Update online devices list
   └─ Notify UI of available sync targets

4. SYNC INITIATION PHASE
   ├─ Auto-trigger: Network change + auto-sync enabled
   ├─ Manual trigger: User taps sync button
   ├─ Background trigger: Periodic or on data change
   ├─ Verify vault is loaded (or auto-load with stored password)
   ├─ Select target device (online + paired + same account)
   └─ Establish TCP connection to target

5. HANDSHAKE PHASE
   ├─ Initiator sends: {"type":"handshake", "deviceId":..., "accountName":...}
   ├─ Receiver validates device is paired
   ├─ Receiver validates account name matches
   ├─ Receiver responds: {"status":"ok"} or {"status":"error"}
   └─ Proceed to data exchange or abort

6. DATA EXCHANGE PHASE
   ├─ Both devices extract vault entries
   ├─ Serialize entries to JSON:
   │  {
   │    "entries": [
   │      {"uuid":"...", "title":"...", "username":"...", "password":"...",
   │       "url":"...", "notes":"...", "tags":"...", "lastModified":"..."},
   │      ...
   │    ]
   │  }
   ├─ Initiator sends local entries
   ├─ Receiver sends remote entries
   └─ Both sides receive complete datasets

7. COMPARISON & MERGE PHASE
   ├─ Build entry maps by UUID
   ├─ Identify adds, updates, deletes
   ├─ Detect conflicts (same UUID, same timestamp, different data)
   ├─ Apply conflict resolution strategy
   ├─ Generate change lists:
   │  - toAddLocally
   │  - toUpdateLocally
   │  - toDeleteLocally
   │  - (mirror for remote)
   └─ Calculate total changes

8. APPLICATION PHASE
   ├─ Create vault backup (for rollback)
   ├─ Apply changes transactionally:
   │  ├─ Add new entries
   │  ├─ Update existing entries
   │  └─ Delete removed entries
   ├─ Save vault to disk
   ├─ On error: Restore from backup
   └─ Send completion acknowledgment

9. LOGGING & NOTIFICATION PHASE
   ├─ Create sync log entry:
   │  - Timestamp
   │  - Remote device
   │  - Change counts
   │  - Success/failure status
   │  - Error details (if any)
   ├─ Save to sync history
   ├─ Update UI sync indicator
   └─ Notify user (if foreground sync)

10. CLEANUP PHASE
    ├─ Close TCP connections
    ├─ Reset sync state to idle
    ├─ Continue mDNS discovery
    └─ Wait for next trigger
```

### Auto-Sync Triggers

The system automatically initiates synchronization when:

1. **Network Join**: Device connects to a trusted WiFi network
2. **Device Discovery**: A paired device comes online on trusted network
3. **Data Change**: Vault is modified while on trusted network (with debouncing)
4. **Background Wake**: App returns to foreground on trusted network
5. **Periodic Check**: Every N minutes when on trusted network (configurable)

---

## Security Model

### Encryption & Authentication

1. **KDBX Vault Encryption**

   - AES-256-CBC encryption for all password data
   - PBKDF2 key derivation from master password
   - Encrypted vaults never transmitted in plaintext

2. **Device Pairing**

   - Cryptographic device fingerprinting using UUID v4
   - Time-bound QR codes (5-minute expiry)
   - Mutual verification during pairing
   - Future: RSA key exchange for end-to-end encryption

3. **Network Security**

   - Trusted network whitelist (WiFi SSID-based)
   - No operation on untrusted/public networks
   - mDNS confined to local network segment
   - Future: TLS for device-to-device connections

4. **Data Integrity**
   - Transactional sync with rollback on error
   - Backup creation before applying changes
   - Checksum verification for transferred data
   - Audit logging for all sync operations

### Privacy Guarantees

- **No Cloud Dependency**: All data remains on local devices
- **No Third-Party Servers**: Direct peer-to-peer communication
- **No Telemetry**: Zero usage tracking or analytics
- **No Metadata Leakage**: Service announcements contain only device ID/name
- **User Control**: Manual approval for first-time pairing

---

## Network Discovery

### mDNS/Bonjour Protocol

**Service Definition:**

```
Type: _xpass-sync._tcp
Domain: local
Instance Name: xpass-{deviceId}
Port: {dynamic}
TXT Records:
  - deviceId={uuid}
  - deviceName={user-defined-name}
  - accountName={current-account}
  - version=1.0.0
```

**Discovery Flow:**

```
┌────────────┐                   ┌────────────┐                   ┌────────────┐
│  Device A  │                   │  Network   │                   │  Device B  │
│            │                   │   (mDNS)   │                   │            │
└────────────┘                   └────────────┘                   └────────────┘
      │                                 │                                 │
      │  Register Service               │                                 │
      ├────────────────────────────────►│                                 │
      │  PTR + SRV + TXT + A Records    │                                 │
      │                                 │                                 │
      │                                 │  Query "_xpass-sync._tcp.local" │
      │                                 │◄────────────────────────────────┤
      │                                 │                                 │
      │                                 │  Send Service Records           │
      │                                 ├────────────────────────────────►│
      │                                 │                                 │
      │                                 │  Resolve IP + Port              │
      │                                 │◄────────────────────────────────┤
      │                                 │                                 │
      │                                 │  Return A Record                │
      │                                 ├────────────────────────────────►│
      │                                 │                                 │
      │                          Direct TCP Connection                    │
      │◄──────────────────────────────────────────────────────────────────┤
      │                                 │                                 │
      │  Sync Data Exchange             │                                 │
      │◄──────────────────────────────────────────────────────────────────►
      │                                 │                                 │
```

**Platform Implementations:**

- **iOS/macOS**: Native Bonjour (NSNetService)
- **Android**: NSD (Network Service Discovery)
- **Linux**: Avahi daemon
- **Windows**: Bonjour Service (if installed) or mDNS-lite

---

## Conflict Resolution

### Conflict Detection Algorithm

A conflict occurs when:

1. Entry exists in both local and remote vaults (matched by UUID)
2. Last modified timestamps are identical
3. Entry content differs (password, username, notes, etc.)

### Resolution Strategies

#### 1. **Use Newer** (Default)

```dart
if (local.lastModified.isAfter(remote.lastModified)) {
  applyLocalToRemote();
} else if (remote.lastModified.isAfter(local.lastModified)) {
  applyRemoteToLocal();
} else {
  // True conflict - fallback to keepBoth
  duplicateEntry();
}
```

#### 2. **Use Local**

Always prefer local version, overwrite remote.

#### 3. **Use Remote**

Always prefer remote version, overwrite local.

#### 4. **Keep Both**

Create duplicate entries with suffix:

- Local: "Gmail Account"
- Remote: "Gmail Account (from John's iPhone)"

### Edge Cases

**Deleted Entries:**

- Mark with `Deleted: true` flag instead of removing
- Propagate delete flag during sync
- Permanently remove after N days (configurable)

**Newly Created on Both Sides:**

- Different UUIDs → No conflict, both kept
- Same account key (title+username) → Potential duplicate, user warned

**Network Partition:**

- Devices sync independently with others
- Eventual consistency when all devices reconnect
- Timestamp resolution prevents data loss

---

## Implementation Details

### Technology Stack

| Component         | Technology                                                                       | Purpose                   |
| ----------------- | -------------------------------------------------------------------------------- | ------------------------- |
| Service Discovery | [nsd ^4.0.3](https://pub.dev/packages/nsd)                                       | mDNS/Bonjour protocol     |
| Network Detection | [network_info_plus ^5.0.3](https://pub.dev/packages/network_info_plus)           | WiFi SSID retrieval       |
| QR Generation     | [qr_flutter ^4.1.0](https://pub.dev/packages/qr_flutter)                         | Pairing QR code creation  |
| QR Scanning       | [mobile_scanner ^5.1.1](https://pub.dev/packages/mobile_scanner)                 | Camera-based QR reading   |
| Device Info       | [device_info_plus ^10.1.0](https://pub.dev/packages/device_info_plus)            | Device name detection     |
| UUID Generation   | [uuid ^4.2.2](https://pub.dev/packages/uuid)                                     | Unique device IDs         |
| Secure Storage    | [flutter_secure_storage ^9.2.2](https://pub.dev/packages/flutter_secure_storage) | Master password storage   |
| Persistence       | [shared_preferences ^2.2.3](https://pub.dev/packages/shared_preferences)         | Settings & paired devices |

### Data Persistence

**SharedPreferences Storage:**

```dart
Keys:
- sync_device_id: String (UUID)
- sync_device_name: String
- sync_paired_devices: JSON Array<PairedDevice>
- sync_trusted_networks: JSON Array<TrustedNetwork>
- sync_logs: JSON Array<SyncLogEntry>
- sync_auto_enabled: Boolean
- sync_background_enabled: Boolean
```

**Secure Storage (Optional):**

```dart
Keys:
- master_password_{accountId}: String (AES-encrypted)
Purpose: Enable background sync without re-authentication
```

### Performance Optimizations

1. **Incremental Sync**: Only transfer changed entries (future enhancement)
2. **Compression**: Gzip JSON payloads for large vaults
3. **Debouncing**: Prevent rapid-fire syncs (5-second cooldown)
4. **Background Processing**: Async vault operations to prevent UI blocking
5. **Connection Pooling**: Reuse TCP connections for multiple sync sessions
6. **Smart Discovery**: Only scan when on trusted networks

### Error Handling

**Transactional Rollback:**

```dart
try {
  backup = createVaultBackup();
  applyChanges(comparison);
  saveVault();
  logSuccess();
} catch (error) {
  restoreFromBackup(backup);
  logError(error);
  notifyUser(error);
}
```

**Retry Logic:**

- Network errors: Retry 3 times with exponential backoff
- Vault locked: Prompt for master password
- Permission denied: Request required permissions
- Conflict: User intervention required

---

## Future Enhancements

### Planned Features

1. **End-to-End Encryption**

   - RSA key exchange during pairing
   - Encrypt sync payloads with shared key
   - Zero-trust device-to-device communication

2. **Incremental Sync**

   - Track changed entries since last sync
   - Only transmit deltas instead of full vault
   - Reduce bandwidth and processing time

3. **Sync Groups**

   - Organize devices into sync groups
   - Different sync policies per group
   - Selective account synchronization

4. **Conflict UI**

   - Visual diff viewer for conflicts
   - Manual merge capability
   - Conflict history tracking

5. **WebSocket Support**

   - Persistent connections for real-time sync
   - Push notifications for remote changes
   - Reduced latency for frequent syncs

6. **Sync Analytics**
   - Bandwidth usage tracking
   - Sync performance metrics
   - Health monitoring dashboard

---

## Conclusion

The xPass Synchronization System represents a sophisticated implementation of privacy-first, peer-to-peer data synchronization. By leveraging zero-configuration networking protocols and intelligent conflict resolution algorithms, it provides seamless password vault synchronization across devices while maintaining complete user control and data sovereignty.

The architecture is designed for extensibility, security, and reliability, with clear separation of concerns and robust error handling. All implementation decisions prioritize user privacy, data integrity, and cross-platform compatibility.

---

**Documentation Version:** 1.0.0  
**Last Updated:** December 15, 2025  
**Maintainer:** xPass Development Team
