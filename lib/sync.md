Now I want to add a feature where when i get home or on my private network the app should sync the passwords in same account.

Tell me the options to implement it.
ASK Questions if not sure DONT assume anything

The feature will make sure the privacy yet keeping the devices in sync and protected.

Ok workflow will go in this way,
It will only require pairing for the first time for example we will pair throught QR scanner, only the first time during pairing now whenever both the device are on private network set by them they will automatically start sync

Tell me the options to implement it.
ASK Questions if not sure DONT assume anything
Reccomendations are preffered but dont assume.

lib/
├── main.dart
├── services/
│ ├── account_service.dart # Existing
│ ├── kdbx_service.dart # Existing (modify for timestamps)
│ ├── theme_service.dart # Existing
│ └── sync/
│ ├── sync_manager.dart # Main orchestrator
│ ├── network_monitor.dart # Trusted network detection
│ ├── discovery_service.dart # mDNS discovery
│ ├── pairing_service.dart # QR code pairing
│ ├── transfer_service.dart # TLS P2P transfer
│ ├── merge_service.dart # Entry merging logic
│ └── sync_log_service.dart # Sync history
│
├── models/
│ ├── sync/
│ │ ├── paired_device.dart # Device info & keys
│ │ ├── trusted_network.dart # WiFi SSID storage
│ │ ├── sync_session.dart # Active sync state
│ │ └── sync_log_entry.dart # History records
│
├── screens/
│ ├── home_screen.dart # Existing
│ ├── vault_screen.dart # Existing (add sync indicator)
│ ├── account_management_screen.dart # Existing
│ └── sync/
│ ├── sync_settings_screen.dart # Main sync settings
│ ├── trusted_networks_screen.dart
│ ├── paired_devices_screen.dart
│ ├── pair_qr_screen.dart # Show/Scan QR
│ ├── account_match_screen.dart # Handle unmatched accounts
│ └── sync_logs_screen.dart
│
└── widgets/
└── sync/
├── sync_status_badge.dart # Shows sync state
├── qr_code_widget.dart
├── qr_scanner_widget.dart
└── device_tile.dart

┌─────────────────────────────────────────────────────────────────────────┐
│ XPASS SYNC SYSTEM │
├─────────────────────────────────────────────────────────────────────────┤
│ │
│ ┌─────────────┐ Trusted Network ┌─────────────┐ │
│ │ Device A │◄──────────────────────────────► │ Device B │ │
│ │ │ mDNS Discovery │ │ │
│ │ - Personal │ TLS Connection │ - Personal │ │
│ │ - Work │ KDBX Transfer │ - Family │ │
│ └─────────────┘ └─────────────┘ │
│ │ │ │
│ │ ┌─────────────┐ │ │
│ └─────────────►│ Device C │◄─────────────────┘ │
│ │ │ │
│ Mesh Sync │ - Personal │ All devices sync │
│ │ - Work │ with all others │
│ └─────────────┘ │
│ │
└─────────────────────────────────────────────────────────────────────────┘

Requirement Decision
Master Password - Same password for same account across devices
Account Matching - Match by account name
Unmatched Accounts - Ask user what to do
Sync Failure - Rollback, wait for next trigger
Device Naming - Auto-generate + allow editing
Web Platform Remove entirely from project
