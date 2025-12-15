import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../models/sync/sync_models.dart';
import 'network_monitor.dart';
import 'sync_manager.dart';

/// Pairing states for UI
enum PairingState {
  idle,
  generatingQR,
  waitingForScan,
  connecting,
  exchangingKeys,
  confirmingAccounts,
  completed,
  failed,
}

/// Result of a pairing attempt
class PairingResult {
  final bool success;
  final PairedDevice? device;
  final String? errorMessage;
  final List<AccountMatch>? accountMatches;

  const PairingResult({
    required this.success,
    this.device,
    this.errorMessage,
    this.accountMatches,
  });

  factory PairingResult.success(
    PairedDevice device, {
    List<AccountMatch>? accountMatches,
  }) {
    return PairingResult(
      success: true,
      device: device,
      accountMatches: accountMatches,
    );
  }

  factory PairingResult.failure(String message) {
    return PairingResult(success: false, errorMessage: message);
  }
}

/// Represents account matching between devices
class AccountMatch {
  final String accountName;
  final bool existsOnBoth;
  final bool existsOnlyLocal;
  final bool existsOnlyRemote;
  bool shouldSync;
  bool shouldCreate;

  AccountMatch({
    required this.accountName,
    this.existsOnBoth = false,
    this.existsOnlyLocal = false,
    this.existsOnlyRemote = false,
    this.shouldSync = true,
    this.shouldCreate = false,
  });
}

/// Service for handling device pairing via QR code
class PairingService extends ChangeNotifier {
  static final PairingService _instance = PairingService._internal();
  factory PairingService() => _instance;
  PairingService._internal();

  final NetworkMonitor _networkMonitor = NetworkMonitor();

  /// Current pairing state
  PairingState _state = PairingState.idle;
  PairingState get state => _state;

  /// Current pairing data (when showing QR)
  PairingData? _currentPairingData;
  PairingData? get currentPairingData => _currentPairingData;

  /// Server socket for pairing connections
  ServerSocket? _pairingServer;

  /// Active pairing token (for validation)
  String? _activePairingToken;

  /// Completer for pairing response
  Completer<PairingResult>? _pairingCompleter;

  /// Generate a secure pairing token
  String _generatePairingToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Generate a simple public key (for now, just a random string)
  /// In production, you'd use proper asymmetric encryption
  String _generatePublicKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Generate QR code data for pairing
  /// Returns the pairing data that should be encoded into a QR code
  Future<PairingData?> generatePairingQR() async {
    if (_state != PairingState.idle) {
      print('Cannot generate QR: pairing already in progress');
      return null;
    }

    _state = PairingState.generatingQR;
    notifyListeners();

    try {
      // Get current IP address
      final ipAddress = await _networkMonitor.getCurrentIP();
      if (ipAddress == null) {
        print('Cannot generate QR: no network connection');
        _state = PairingState.idle;
        notifyListeners();
        return null;
      }

      // Start pairing server
      _pairingServer = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = _pairingServer!.port;

      print('Pairing server started on port $port');

      // Listen for connections
      _pairingServer!.listen(_handlePairingConnection);

      // Get device info from SyncManager
      final syncManager = SyncManager();
      final deviceId = syncManager.deviceId ?? const Uuid().v4();
      final deviceName = syncManager.deviceName ?? 'Unknown Device';

      // Generate security tokens
      _activePairingToken = _generatePairingToken();
      final publicKey = _generatePublicKey();

      // Create pairing data
      _currentPairingData = PairingData(
        deviceId: deviceId,
        deviceName: deviceName,
        publicKey: publicKey,
        ipAddress: ipAddress,
        port: port,
        generatedAt: DateTime.now(),
        pairingToken: _activePairingToken!,
      );

      _state = PairingState.waitingForScan;
      notifyListeners();

      print('Generated pairing QR: ${_currentPairingData!.deviceName}');
      return _currentPairingData;
    } catch (e) {
      print('Error generating pairing QR: $e');
      _state = PairingState.failed;
      notifyListeners();
      await cancelPairing();
      return null;
    }
  }

  /// Handle incoming pairing connection
  void _handlePairingConnection(Socket socket) async {
    print('Incoming pairing connection from ${socket.remoteAddress.address}');

    try {
      // Create a stream iterator for safe reading
      final lineStream = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final streamIterator = StreamIterator(lineStream);

      // Read pairing response from scanner
      final hasData = await streamIterator.moveNext().timeout(
        const Duration(seconds: 30),
      );
      if (!hasData) {
        print('No pairing data received');
        await streamIterator.cancel();
        await socket.close();
        return;
      }
      final jsonString = streamIterator.current;
      final response = PairingResponse.fromJsonString(jsonString);

      print('Received pairing response from: ${response.deviceName}');

      // Validate pairing token
      if (response.pairingToken != _activePairingToken) {
        print('Invalid pairing token');
        socket.write(
          '${jsonEncode({'success': false, 'error': 'Invalid token'})}\n',
        );
        await socket.flush();
        await streamIterator.cancel();
        await socket.close();
        return;
      }

      // Create paired device
      final pairedDevice = PairedDevice(
        id: response.deviceId,
        name: response.deviceName,
        publicKey: response.publicKey,
        pairedAt: DateTime.now(),
        lastSeen: DateTime.now(),
      );

      // Send confirmation
      final confirmation = jsonEncode({
        'success': true,
        'deviceId': _currentPairingData!.deviceId,
        'deviceName': _currentPairingData!.deviceName,
      });
      socket.write('$confirmation\n');
      await socket.flush();
      await streamIterator.cancel();
      await socket.close();

      // Add to paired devices
      final syncManager = SyncManager();
      await syncManager.addPairedDevice(pairedDevice);

      _state = PairingState.completed;
      notifyListeners();

      // Complete the pairing completer if waiting
      _pairingCompleter?.complete(PairingResult.success(pairedDevice));

      print('Pairing completed with: ${pairedDevice.name}');
    } catch (e) {
      print('Error handling pairing connection: $e');
      _state = PairingState.failed;
      notifyListeners();
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  /// Wait for a device to scan the QR code and complete pairing
  Future<PairingResult> waitForPairing({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (_state != PairingState.waitingForScan) {
      return PairingResult.failure('Not waiting for scan');
    }

    _pairingCompleter = Completer<PairingResult>();

    // Set timeout
    Timer(timeout, () {
      if (!_pairingCompleter!.isCompleted) {
        _pairingCompleter!.complete(PairingResult.failure('Pairing timeout'));
        cancelPairing();
      }
    });

    return _pairingCompleter!.future;
  }

  /// Process scanned QR code and initiate pairing
  Future<PairingResult> processPairingQR(String qrData) async {
    if (_state != PairingState.idle) {
      return PairingResult.failure('Pairing already in progress');
    }

    _state = PairingState.connecting;
    notifyListeners();

    Socket? socket;
    StreamIterator<String>? streamIterator;

    try {
      // Parse QR data
      final pairingData = PairingData.fromQRString(qrData);

      // Check if expired
      if (pairingData.isExpired) {
        _state = PairingState.failed;
        notifyListeners();
        return PairingResult.failure('QR code has expired');
      }

      print(
        'Connecting to ${pairingData.deviceName} at ${pairingData.ipAddress}:${pairingData.port}',
      );

      _state = PairingState.exchangingKeys;
      notifyListeners();

      // Connect to the device showing QR
      socket = await Socket.connect(
        pairingData.ipAddress,
        pairingData.port,
        timeout: const Duration(seconds: 10),
      );

      // Create a stream iterator for safe reading
      final lineStream = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      streamIterator = StreamIterator(lineStream);

      try {
        // Get our device info
        final syncManager = SyncManager();
        final deviceId = syncManager.deviceId ?? const Uuid().v4();
        final deviceName = syncManager.deviceName ?? 'Unknown Device';
        final publicKey = _generatePublicKey();

        // Send pairing response
        final response = PairingResponse(
          deviceId: deviceId,
          deviceName: deviceName,
          publicKey: publicKey,
          pairingToken: pairingData.pairingToken,
          accepted: true,
        );

        socket.write('${response.toJsonString()}\n');
        await socket.flush();

        // Wait for confirmation
        final hasData = await streamIterator.moveNext().timeout(
          const Duration(seconds: 30),
        );
        if (!hasData) {
          throw Exception('No confirmation received');
        }
        final confirmationJson =
            jsonDecode(streamIterator.current) as Map<String, dynamic>;

        if (confirmationJson['success'] != true) {
          _state = PairingState.failed;
          notifyListeners();
          return PairingResult.failure(
            confirmationJson['error'] ?? 'Pairing rejected',
          );
        }

        // Create paired device from the QR data
        final pairedDevice = PairedDevice(
          id: pairingData.deviceId,
          name: pairingData.deviceName,
          publicKey: pairingData.publicKey,
          pairedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        );

        // Add to paired devices
        await syncManager.addPairedDevice(pairedDevice);

        _state = PairingState.completed;
        notifyListeners();

        print('Pairing completed with: ${pairedDevice.name}');
        return PairingResult.success(pairedDevice);
      } finally {
        await streamIterator.cancel();
        await socket.close();
      }
    } catch (e) {
      print('Error processing pairing QR: $e');
      try {
        await streamIterator?.cancel();
        await socket?.close();
      } catch (_) {}
      _state = PairingState.failed;
      notifyListeners();
      return PairingResult.failure('Connection failed: $e');
    }
  }

  /// Cancel ongoing pairing
  Future<void> cancelPairing() async {
    print('Cancelling pairing...');

    await _pairingServer?.close();
    _pairingServer = null;

    _currentPairingData = null;
    _activePairingToken = null;

    if (_pairingCompleter != null && !_pairingCompleter!.isCompleted) {
      _pairingCompleter!.complete(PairingResult.failure('Cancelled'));
    }
    _pairingCompleter = null;

    _state = PairingState.idle;
    notifyListeners();
  }

  /// Reset state after pairing (success or failure)
  void resetState() {
    _state = PairingState.idle;
    _currentPairingData = null;
    _activePairingToken = null;
    _pairingCompleter = null;
    notifyListeners();
  }

  /// Check if currently in a pairing operation
  bool get isPairing => _state != PairingState.idle;

  @override
  void dispose() {
    cancelPairing();
    super.dispose();
  }
}
