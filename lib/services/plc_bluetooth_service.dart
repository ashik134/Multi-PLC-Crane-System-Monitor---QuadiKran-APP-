import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutterblue;

import 'package:rev4_quadikran_monitoring/models/plc_data.dart';
import 'package:rev4_quadikran_monitoring/services/ble_foreground_task_handler.dart';

enum BleEventType {
  connected,
  disconnected,
  connectionFailed,

  /// Emitted when the user explicitly cancels an in-progress connection attempt.
  connectionCancelled,
  reconnecting,
  unstableConnection,
  poorSignal,

  /// Emitted when a safety-critical CCCD (e.g. char 10 = emergency relay)
  /// could not be registered after all retries during Phase 1 setup.
  /// Emergency alert monitoring may be inactive for this PLC slot.
  cccdRegistrationFailed,
}

class BleEvent {
  final BleEventType type;
  final String plcId;
  final String deviceName;

  final String? error;
  final int? rssi;

  final int? reconnectAttempt;
  final int? maxAttempts;

  final bool isAutoReconnect;

  const BleEvent({
    required this.type,
    required this.plcId,
    required this.deviceName,
    this.error,
    this.reconnectAttempt,
    this.maxAttempts,
    this.rssi,
    this.isAutoReconnect = false,
  });
}

class ScannedDevice {
  final flutterblue.BluetoothDevice device;
  flutterblue.AdvertisementData advertisementData;
  final String name;
  final String id;

  int rssi;
  bool isConnected;

  String? assignedPlcId;
  String? customName;

  DateTime lastSeen;

  String get displayName => customName ?? name;

  ScannedDevice({
    required this.device,
    required this.advertisementData,
    required this.name,
    required this.id,
    required this.rssi,
    this.isConnected = false,
    this.assignedPlcId,
    this.customName,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

class ConnectedDeviceHistory {
  final String deviceId;
  final String deviceName;
  final String plcId;
  final DateTime connectedAt;

  ConnectedDeviceHistory({
    required this.deviceId,
    required this.deviceName,
    required this.plcId,
    required this.connectedAt,
  });

  String toStorageString() =>
      '$deviceId|$deviceName|$plcId|${connectedAt.millisecondsSinceEpoch}';

  static ConnectedDeviceHistory? fromStorageString(String s) {
    final parts = s.split('|');
    if (parts.length != 4) return null;
    final ts = int.tryParse(parts[3]);
    if (ts == null) return null;
    return ConnectedDeviceHistory(
      deviceId: parts[0],
      deviceName: parts[1],
      plcId: parts[2],
      connectedAt: DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }
}

class CrashDetector {
  final Map<String, List<DateTime>> _history = {};
  final int threshold;
  final Duration window;
  final Duration pauseDuration;

  CrashDetector({
    this.threshold = 3,
    this.window = const Duration(minutes: 5),
    this.pauseDuration = const Duration(minutes: 2),
  });

  bool record(String plcId) {
    final now = DateTime.now();
    _history.putIfAbsent(plcId, () => []).add(now);

    _history[plcId] = _history[plcId]!
        .where((t) => t.isAfter(now.subtract(window)))
        .toList();

    if (_history[plcId]!.length >= threshold) {
      debugPrint('⚠️ CRASH LOOP detected for $plcId');
      Future.delayed(pauseDuration, () => _history.remove(plcId));
      return true;
    }
    return false;
  }

  void clear(String plcId) => _history.remove(plcId);
}

final _crashDetector = CrashDetector();

/// Serialises GATT ATT operations for a single BLE device and automatically
/// retries on transient GATT error 133 with exponential back-off.
///
/// Uses a "tail-future" chain so each [run] call waits for the previous one
/// to settle before starting — no fixed delays required.
class _GattQueue {
  static const int _maxRetries = 3;
  static const List<Duration> _retryDelays = [
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
  ];

  Future<void> _tail = Future.value();

  /// Enqueues [operation] to run after any in-progress operations complete.
  ///
  /// If the operation throws a GATT 133 error it is retried up to
  /// [_maxRetries] times with increasing delays. Any other error — or a
  /// GATT 133 that still fails after all retries — is rethrown to the caller.
  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final prev = _tail;
    _tail = Future<void>(() async {
      // Wait for the previous operation; swallow its error so a single
      // GATT failure never stalls the rest of the queue.
      await prev.catchError((_) {});
      int attempt = 0;
      while (true) {
        try {
          completer.complete(await operation());
          return;
        } catch (e, st) {
          attempt++;
          final errStr = e.toString();
          final isGatt133 =
              errStr.contains('133') || errStr.toUpperCase().contains('GATT');
          if (attempt >= _maxRetries || !isGatt133) {
            completer.completeError(e, st);
            return;
          }
          final delay =
              _retryDelays[(attempt - 1).clamp(0, _retryDelays.length - 1)];
          debugPrint(
            'GattQueue: GATT 133 (attempt $attempt/$_maxRetries), '
            'retrying in ${delay.inMilliseconds} ms…',
          );
          await Future.delayed(delay);
        }
      }
    });
    return completer.future;
  }
}

class PLCBluetoothService extends ChangeNotifier {
  final Map<String, ScannedDevice> _scannedDevices = {};
  final Map<String, DateTime> _lastSeenAdvertising = {};
  final Set<String> _nonAdvertisingDevices = {};
  static const Duration _advertisingTimeout = Duration(seconds: 30);
  Timer? _staleDeviceCleanupTimer;

  bool _isScanning = false;
  bool _isContinuousScanning = false;
  bool _isBluetoothOn = false;
  bool _disposed = false;
  StreamSubscription<bool>? _scanningStateSubscription;
  Timer? _autoStopTimer;
  Timer? _scanCycleTimer;
  Timer? _uiThrottleTimer;
  bool _scanCycleInProgress = false;
  static const Duration _uiThrottleDuration = Duration(milliseconds: 50);

  // --- Auto-reconnect state ---
  /// Remembers the scanned-device ID last used for each PLC slot.
  final Map<String, String> _deviceIdForPlc = {};

  /// Number of reconnect attempts already made for each PLC.
  final Map<String, int> _reconnectAttempts = {};

  /// Pending reconnect timers.
  final Map<String, Timer> _reconnectTimers = {};

  /// PLCs that the user explicitly disconnected — do NOT auto-reconnect.
  final Set<String> _manuallyDisconnected = {};

  /// Connection attempts that the user has explicitly cancelled.
  /// Used to suppress spurious connectionFailed events.
  final Set<String> _cancelledConnections = {};

  /// Custom device names stored locally (MAC address → custom label).
  final Map<String, String> _customNames = {};
  SharedPreferences? _prefs;

  /// Devices that disconnected because they stopped advertising.
  /// Key = deviceId, Value = plcId that was assigned. When the device
  /// re-advertises and the slot is still free, auto-reconnect is attempted.
  final Map<String, String> _awaitingReAdvertise = {};

  /// PLCs currently in an automatic reconnection attempt (timer-based or
  /// re-advertise). Used to stamp [BleEvent.isAutoReconnect].
  final Set<String> _autoReconnectingPlcs = {};

  /// Persistent log of every successful connection (most-recent first).
  final List<ConnectedDeviceHistory> _connectionHistory = [];

  bool _foregroundServiceRunning = false;
  Timer? _notificationRefreshTimer;

  /// User-controlled setting: show persistent notification while BLE is active.
  bool _notificationEnabled = true;

  /// User-controlled setting: auto-restart the foreground service on device boot.
  bool _autoStartOnBoot = false;

  bool get notificationEnabled => _notificationEnabled;
  bool get autoStartOnBoot => _autoStartOnBoot;

  /// Broadcast stream for connection lifecycle events (connect / disconnect /
  /// failure). The UI subscribes to this to show snackbars without polling.
  final StreamController<BleEvent> _bleEventController =
      StreamController<BleEvent>.broadcast();
  Stream<BleEvent> get bleEvents => _bleEventController.stream;

  /// Tracks the most-recent GATT-level exception string per plcId.
  /// Populated when `setNotifyValue` or `char.read` throws with status 133;
  /// consumed (and cleared) by [_handleDisconnect] to annotate the event.
  final Map<String, String> _lastGattError = {};

  /// Per-PLC GATT operation queues used during characteristic setup (Phase 1).
  /// Each queue serialises CCCD writes and retries on GATT 133 automatically.
  final Map<String, _GattQueue> _gattQueues = {};

  /// Characteristic indices considered safety-critical.
  /// A permanent CCCD failure on any of these emits [BleEventType.cccdRegistrationFailed].
  /// Index 10 = outputPINRelay (drives EmergencyAlertService).
  static const Set<int> _criticalCharIndices = {10};

  /// Per-PLC set of char indices where CCCD registration permanently failed
  /// (after Phase 1 + Phase 1b retries).  Cleared on disconnect.
  final Map<String, Set<int>> _failedCcds = {};

  StreamSubscription<List<flutterblue.ScanResult>>? _scanSubscription;
  StreamSubscription<flutterblue.BluetoothAdapterState>?
  _adapterStateSubscription;

  final Map<String, ScannedDevice> _connectedDevices = {};
  final Map<String, PLCData> _plcDataMap = {};

  /// Hardware-level connection state — only ever `.connected` or `.disconnected`.
  /// Source of truth comes from the BLE GATT callback.
  final Map<String, flutterblue.BluetoothConnectionState> _connectionStates = {
    'PLC1': flutterblue.BluetoothConnectionState.disconnected,
    'PLC2': flutterblue.BluetoothConnectionState.disconnected,
    'PLC3': flutterblue.BluetoothConnectionState.disconnected,
    'PLC4': flutterblue.BluetoothConnectionState.disconnected,
  };

  /// PLCs currently mid-connection (app initiated, hardware not yet confirmed).
  final Set<String> _connectingPlcs = {};

  /// PLCs currently mid-disconnection (app initiated, teardown in progress).
  final Set<String> _disconnectingPlcs = {};

  final Map<String, List<flutterblue.BluetoothService>> _discoveredServices =
      {};
  final Map<String, flutterblue.BluetoothService?> _plcServices = {};
  // 26-slot characteristic list per PLC; index matches pChar[] in ble_broadcast.cpp.
  // 0-9: bool diagnostics, 10-14: output pins, 15-18: crane floats,
  // 19-21: anticollision load floats (kg), 22-23: anticollision bypass bools.
  static const String _bleServiceUuid = '6e410001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _packetCharUuid = '6e410002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Setup order for characteristic registration and seed reads.
  /// Float measurements are processed before boolean diagnostics so that
  /// Crane 2/3 and load monitoring values appear on screen first.
  static const List<int> _setupOrder = [
    15, 16, 17, 18, // Crane 1-4 distances  (float32 LE)
    19, 20, 21, // H1 / H2 / Total load (float32 LE)
    22, 23, // Anticollision bypass  (bool)
    0, 1, 2, 3, 4, 5, 6, 7,
    8, 9, 10, 11, 12, 13, 14, // Status / diagnostic bools
    24, 25, // C4 comm + Node4 DAT bools
  ];
  final Map<String, List<flutterblue.BluetoothCharacteristic?>> _chars = {};
  final Map<String, flutterblue.BluetoothCharacteristic> _packetCharByPlc = {};

  final Map<String, StreamSubscription<flutterblue.BluetoothConnectionState>>
  _connectionStateSubscriptions = {};

  List<ScannedDevice> get scannedDevices =>
      _scannedDevices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  List<ScannedDevice> get availableDevices {
    // Exclude devices that are already connected OR currently mid-connect
    // (isConnected is set to true immediately when connectDeviceToPlc is
    // called, so they vanish from this list until the attempt resolves).
    final connectingIds = _connectingPlcs
        .map((plcId) => _deviceIdForPlc[plcId])
        .whereType<String>()
        .toSet();

    final now = DateTime.now();

    return _scannedDevices.values.where((d) {
      // Don't show connected devices
      if (d.isConnected) return false;

      // Don't show devices that are currently connecting
      if (connectingIds.contains(d.id)) return false;

      // While scanning: only include devices that are currently advertising
      // (seen within the advertising timeout window).
      // When scanning is stopped the list freezes — no timeout filtering applied.
      if (_isScanning) {
        final wasSeenRecently =
            now.difference(d.lastSeen) <= _advertisingTimeout;
        if (!wasSeenRecently) {
          if (!_nonAdvertisingDevices.contains(d.id)) {
            _nonAdvertisingDevices.add(d.id);
          }
          return false;
        }
      }

      return true;
    }).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  bool isContinuousScanning() {
    return _isContinuousScanning;
  }

  /// Start periodic cleanup of stale devices
  void _startStaleDeviceCleanup() {
    _staleDeviceCleanupTimer?.cancel();
    _staleDeviceCleanupTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _cleanupStaleDevices();
    });
  }

  /// Remove devices that haven't been seen for too long
  void _cleanupStaleDevices() {
    final now = DateTime.now();
    bool hasChanges = false;
    final devicesToRemove = <String>[];

    for (final entry in _scannedDevices.entries) {
      final deviceId = entry.key;
      final device = entry.value;

      // Skip connected devices
      if (device.isConnected) continue;

      // Remove if not seen for more than timeout
      if (now.difference(device.lastSeen) > _advertisingTimeout) {
        if (!_nonAdvertisingDevices.contains(deviceId)) {
          _nonAdvertisingDevices.add(deviceId);
          hasChanges = true;
        }

        // Remove after being stale for twice the timeout (30 seconds)
        if (now.difference(device.lastSeen) > _advertisingTimeout * 2) {
          devicesToRemove.add(deviceId);
          debugPrint(' Removing stale device: ${device.name} ($deviceId)');
          hasChanges = true;
        }
      }
    }

    // Remove stale devices
    for (final deviceId in devicesToRemove) {
      _scannedDevices.remove(deviceId);
      _nonAdvertisingDevices.remove(deviceId);
      _lastSeenAdvertising.remove(deviceId);
    }

    if (hasChanges) {
      notifyListeners();
    }
  }

  Map<String, ScannedDevice> connectedDevices() {
    // Only return slots that are truly connected — prevents stale ghost entries
    // from appearing in the UI after an unexpected disconnect or slot reassignment.
    return Map.fromEntries(
      _connectedDevices.entries.where(
        (e) =>
            _connectionStates[e.key] ==
            flutterblue.BluetoothConnectionState.connected,
      ),
    );
  }

  /// Returns a map of plcId → ScannedDevice for every PLC slot currently
  /// mid-connection (connecting boolean flag is set).
  Map<String, ScannedDevice> connectingDevices() {
    final result = <String, ScannedDevice>{};
    for (final plcId in _connectingPlcs) {
      final deviceId = _deviceIdForPlc[plcId];
      if (deviceId != null) {
        final device = _scannedDevices[deviceId];
        if (device != null) result[plcId] = device;
      }
    }
    return result;
  }

  Future<void> initBluetooth() async {
    // Notification permission is requested exclusively by HomeScreen after
    // the user logs in. Requesting it here races with permission_handler and
    // causes "A request for permissions is already running" on first launch.
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadCustomNames();
      _loadConnectionHistory();
      _loadPlcAssignments();
      _notificationEnabled = _prefs?.getBool('notification_enabled') ?? true;
      _autoStartOnBoot = _prefs?.getBool('auto_start_on_boot') ?? false;
      if (Platform.isAndroid) {
        _initForegroundTask();
        FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      }

      final initialState = await flutterblue.FlutterBluePlus.adapterState.first;
      _isBluetoothOn = initialState == flutterblue.BluetoothAdapterState.on;

      debugPrint('Initial Bluetooth state: ${_isBluetoothOn ? "ON" : "OFF"}');

      _adapterStateSubscription = flutterblue.FlutterBluePlus.adapterState
          .listen((state) {
            if (_disposed) return;

            debugPrint('Bluetooth adapter state: $state');
            _isBluetoothOn = state == flutterblue.BluetoothAdapterState.on;

            if (!_isBluetoothOn) {
              _isScanning = false;
              _scannedDevices.clear();

              stopScanning().catchError((e) {
                debugPrint('Error stopping scan during Bluetooth off: $e');
              });
              disconnectAllPlcs().catchError((e) {
                debugPrint('Error disconnecting PLCs during Bluetooth off: $e');
              });
            } else {
              debugPrint('Bluetooth turned on - ready to scan');
              // Re-start scanning so persisted devices auto-reconnect.
              if (_awaitingReAdvertise.isNotEmpty) {
                startScanning(
                  continuous: true,
                ).catchError((e) => debugPrint('Auto-scan on BT-on error: $e'));
              }
            }
            notifyListeners();
          });

      // BT was already on when the app launched — kick off a scan immediately.
      if (_isBluetoothOn && _awaitingReAdvertise.isNotEmpty) {
        startScanning(
          continuous: true,
        ).catchError((e) => debugPrint('Auto-scan on startup error: $e'));
      }
    } catch (error) {
      debugPrint('Error initializing Bluetooth: $error');
    }
  }

  /// Checks whether all required BLE permissions are already granted.
  /// Does NOT prompt the user — permission requesting is handled by the UI.
  Future<bool> _areBlePermissionsGranted() async {
    if (Platform.isAndroid) {
      return (await Permission.bluetoothScan.status).isGranted &&
          (await Permission.bluetoothConnect.status).isGranted &&
          (await Permission.locationWhenInUse.status).isGranted;
    } else if (Platform.isIOS) {
      return (await Permission.bluetooth.status).isGranted &&
          (await Permission.locationWhenInUse.status).isGranted;
    }
    return false;
  }

  Future<void> startScanning({bool continuous = false}) async {
    if (_isScanning) {
      debugPrint('Already scanning');
      return;
    }

    if (!await _areBlePermissionsGranted()) {
      debugPrint(
        'Bluetooth & Location permissions not granted — request from UI first',
      );
      return;
    }

    if (!_isBluetoothOn) {
      debugPrint('Please turn on Bluetooth first');
      return;
    }

    final isSupported = await flutterblue.FlutterBluePlus.isSupported;
    if (!isSupported) {
      debugPrint("Bluetooth not supported");
      return;
    }

    debugPrint('Starting BLE scan (continuous: $continuous)');

    // IMPORTANT: Don't clear devices on every scan start
    //_scannedDevices.clear(); // it cause flickering

    _isContinuousScanning = continuous;
    _isScanning = true;
    _startStaleDeviceCleanup();
    notifyListeners();

    try {
      // Cancel old subscription properly
      await _scanSubscription?.cancel();

      // Set up scan results listener with INSTANT processing
      _scanSubscription = flutterblue.FlutterBluePlus.scanResults.listen(
        _handleScanResults, // No debounce wrapper!
        onError: (error) {
          debugPrint('Scan stream error: $error');
          _restartScan();
        },
      );

      // Stop any ongoing scan
      await flutterblue.FlutterBluePlus.stopScan();

      // Start the first scan cycle IMMEDIATELY
      await _startScanCycle();

      // Set up continuous timer for subsequent scans
      _scanCycleTimer?.cancel();
      _scanCycleTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!_isScanning || _disposed) {
          timer.cancel();
          return;
        }
        // Skip this cycle while any PLC is connected. Restarting the BLE
        // scanner (stopScan → startScan) while a GATT link is active can
        // cause spurious disconnections on many Android devices.

        _startScanCycle().catchError((e) {
          debugPrint('Scan cycle error: $e');
        });
      });

      // Auto-stop for continuous mode
      if (continuous) {
        _autoStopTimer?.cancel();
        _autoStopTimer = Timer(const Duration(minutes: 2), () {
          debugPrint('Auto-stopping continuous scan after 2 minutes');
          stopScanning();
        });
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      await stopScanning();
    }
  }

  void _handleScanResults(List<flutterblue.ScanResult> results) {
    if (_disposed || !_isScanning) return;

    bool hasChanges = false;
    final now = DateTime.now();
    debugPrint('Scan callback: Found ${results.length} devices');

    // Process ALL results immediately
    for (final result in results) {
      final deviceId = result.device.remoteId.toString();

      _lastSeenAdvertising[deviceId] = now;

      if (_nonAdvertisingDevices.contains(deviceId)) {
        _nonAdvertisingDevices.remove(deviceId);
        hasChanges = true;
        debugPrint('Device $deviceId is advertising again');
        // If this device was waiting to re-advertise for a PLC reconnect,
        // kick off the auto-reconnect attempt now.
        _checkReAdvertiseReconnect(deviceId);
      }

      if (_scannedDevices.containsKey(deviceId)) {
        // Update existing device
        final device = _scannedDevices[deviceId]!;
        device.lastSeen = now;
        // Only update if RSSI changed significantly (prevents excessive updates)
        if ((device.rssi - result.rssi).abs() > 3) {
          device.rssi = result.rssi;
          device.advertisementData = result.advertisementData;
          hasChanges = true;
        }
      } else {
        // Add new device INSTANTLY
        _scannedDevices[deviceId] = ScannedDevice(
          device: result.device,
          advertisementData: result.advertisementData,
          name: _getDeviceName(result),
          id: deviceId,
          isConnected: false,
          rssi: result.rssi,
          customName: _customNames[deviceId],
          lastSeen: now,
        );
        hasChanges = true;

        // Log first discovery for debugging
        debugPrint(' New device found: ${_getDeviceName(result)}');
        // Device may have been removed from scan cache after a long absence.
        // Check if it was awaiting re-advertise for an auto-reconnect.
        _checkReAdvertiseReconnect(deviceId);
      }
    }

    // Throttle UI updates for smooth performance
    if (hasChanges) {
      _throttledNotify();
    }
  }

  /// Throttled UI updates (max 20fps)
  void _throttledNotify() {
    _uiThrottleTimer?.cancel();
    _uiThrottleTimer = Timer(_uiThrottleDuration, () {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  Future<void> _startScanCycle() async {
    if (_scanCycleInProgress) return;

    _scanCycleInProgress = true;
    try {
      // Stop any ongoing scan (required before starting new one)
      await flutterblue.FlutterBluePlus.stopScan();

      // Start scan with a long enough window to detect devices reliably.
      // lowLatency drains battery and causes rapid stop/start to leak Android
      // scanner registrations (SCAN_FAILED_APPLICATION_REGISTRATION_FAILED).
      await flutterblue.FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 3),
        androidUsesFineLocation: true,
        androidScanMode: flutterblue.AndroidScanMode.balanced,
      );

      debugPrint(' Scan cycle completed');
    } catch (e) {
      debugPrint(' Scan cycle error: $e');
    } finally {
      _scanCycleInProgress = false;
    }
  }

  /// Restart scan if it fails
  Future<void> _restartScan() async {
    if (!_isScanning || _disposed) return;

    debugPrint(' Restarting scan...');

    try {
      await flutterblue.FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 50));
      await _startScanCycle();
    } catch (e) {
      debugPrint('Restart failed: $e');
    }
  }

  /// CLEAR DEVICES - keeps connected and named devices
  void clearDeviceList() {
    // Keep devices that are connected or have custom names
    final devicesToKeep = <String, ScannedDevice>{};

    _scannedDevices.forEach((id, device) {
      if (device.isConnected || _customNames.containsKey(id)) {
        devicesToKeep[id] = device;
      }
    });

    _scannedDevices.clear();
    _scannedDevices.addAll(devicesToKeep);

    notifyListeners();
    debugPrint(' Cleared device list, kept ${devicesToKeep.length} devices');
  }

  void forceClearAllDevices() {
    _scannedDevices.clear();
    notifyListeners();
    debugPrint(' Force cleared all devices');
  }

  /// FORCE CLEAR - use when user explicitly wants to clear everything

  Future<void> stopScanning() async {
    debugPrint(' Stopping scan');

    _staleDeviceCleanupTimer?.cancel();
    _staleDeviceCleanupTimer = null;

    // Cancel all timers FIRST
    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;

    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    _uiThrottleTimer?.cancel();
    _uiThrottleTimer = null;

    // Stop scan
    try {
      await flutterblue.FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }

    // Cancel subscription
    try {
      await _scanSubscription?.cancel();
    } catch (e) {
      debugPrint('Error canceling subscription: $e');
    }
    _scanSubscription = null;

    _scanCycleInProgress = false;
    _isScanning = false;
    _isContinuousScanning = false;

    notifyListeners();

    debugPrint(' Scan stopped. Found ${_scannedDevices.length} devices');
  }

  String _getDeviceName(flutterblue.ScanResult result) {
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    } else if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    return 'Unknown Device';
  }

  // ---------- Custom Device Names ----------------------------------------

  /// Returns the display name for [deviceId]: custom name if saved, else the
  /// scanned BLE advertisement name, else 'Unknown Device'.
  String getDisplayName(String deviceId) {
    if (_customNames.containsKey(deviceId)) return _customNames[deviceId]!;
    final scanned = _scannedDevices[deviceId];
    if (scanned != null) return scanned.name;
    for (final sd in _connectedDevices.values) {
      if (sd.id == deviceId) return sd.name;
    }
    return 'Unknown Device';
  }

  /// Persists a custom display name for [deviceId] and updates all in-memory
  /// references immediately.
  Future<void> setCustomDeviceName(String deviceId, String name) async {
    _customNames[deviceId] = name;
    await _prefs?.setString('device_name_$deviceId', name);
    _scannedDevices[deviceId]?.customName = name;
    for (final sd in _connectedDevices.values) {
      if (sd.id == deviceId) sd.customName = name;
    }
    notifyListeners();
  }

  // ---------- Cancel Reconnect / Connection --------------------------------

  /// Cancels any pending auto-reconnect timer for [plcId]. The PLC remains
  /// disconnected and will not reconnect automatically.
  void cancelReconnect(String plcId) {
    _manuallyDisconnected.add(plcId);
    _awaitingReAdvertise.removeWhere((k, v) => v == plcId);
    _reconnectTimers[plcId]?.cancel();
    _reconnectTimers.remove(plcId);
    _reconnectAttempts.remove(plcId);
    notifyListeners();
  }

  /// Aborts an in-progress BLE connection attempt for [plcId].
  Future<void> cancelConnectionAttempt(String plcId) async {
    // Guard clause - fast check
    if (!_connectingPlcs.contains(plcId)) return;

    debugPrint('🔴 Cancelling connection attempt for $plcId');

    // STEP 1: IMMEDIATE UI FEEDBACK (all synchronous operations)
    _cancelledConnections.add(plcId);
    _manuallyDisconnected.add(plcId);
    _awaitingReAdvertise.removeWhere((k, v) => v == plcId);
    _autoReconnectingPlcs.remove(plcId);
    _connectionStates[plcId] =
        flutterblue.BluetoothConnectionState.disconnected;

    // Cancel all timers immediately
    _reconnectTimers[plcId]?.cancel();
    _reconnectTimers.remove(plcId);
    _reconnectAttempts.remove(plcId);

    // Remove from connecting list (UI will show as disconnected/disconnecting)
    _connectingPlcs.remove(plcId);

    // Cancel the connection-state subscription NOW so no late 'connected'
    // hardware event can slip through while the guard is still in place.
    _connectionStateSubscriptions[plcId]?.cancel();
    _connectionStateSubscriptions.remove(plcId);

    // 🟢 NOTIFY UI IMMEDIATELY - Button should respond NOW
    notifyListeners();

    // Emit cancellation event for snackbar feedback.
    final deviceName =
        _scannedDevices[_deviceIdForPlc[plcId]]?.displayName ?? plcId;
    _bleEventController.add(
      BleEvent(
        type: BleEventType.connectionCancelled,
        plcId: plcId,
        deviceName: deviceName,
      ),
    );

    // STEP 2: Background cleanup (slow operations)
    await _performBackgroundCleanup(plcId);
  }

  Future<void> _performBackgroundCleanup(String plcId) async {
    try {
      final deviceId = _deviceIdForPlc[plcId];
      if (deviceId == null) {
        _finalizeCancel(plcId);
        return;
      }

      final sd = _scannedDevices[deviceId];
      if (sd == null) {
        _finalizeCancel(plcId);
        return;
      }

      // Attempt disconnect with timeout.
      // 5 s gives the GATT stack enough time to cancel an in-progress connect
      // on most Android devices without hanging the background cleanup forever.
      try {
        await sd.device.disconnect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Disconnect timeout for $plcId');
            // Continue with cleanup even if timeout
          },
        );
      } catch (e) {
        debugPrint('⚠️ Disconnect error for $plcId: $e');
        // Continue with cleanup
      }

      // Update device state
      sd.isConnected = false;
      sd.assignedPlcId = null;
    } finally {
      _finalizeCancel(plcId);
    }
  }

  void _finalizeCancel(String plcId) {
    // Cancel any remaining subscriptions
    _connectionStateSubscriptions[plcId]?.cancel();
    _connectionStateSubscriptions.remove(plcId);

    // Remove from any remaining lists
    _disconnectingPlcs.remove(plcId);

    // Set final disconnected state
    _connectionStates[plcId] =
        flutterblue.BluetoothConnectionState.disconnected;

    // Final UI update
    notifyListeners();
    _updateForegroundService();

    debugPrint('✅ Cancel complete for $plcId');
  }

  // ---------- Connecting device info --------------------------------------

  /// Returns the display name of the device currently connecting to [plcId],
  /// or null if [plcId] is not in the connecting state.
  String? getConnectingDeviceName(String plcId) {
    if (!_connectingPlcs.contains(plcId)) return null;
    final deviceId = _deviceIdForPlc[plcId];
    if (deviceId == null) return null;
    return _scannedDevices[deviceId]?.displayName;
  }

  Map<String, PLCData> get plcDataMap => _plcDataMap;

  bool get isScanning => _isScanning;

  bool get isBluetoothOn => _isBluetoothOn;

  List<ConnectedDeviceHistory> get connectionHistory =>
      List.unmodifiable(_connectionHistory);

  /// Returns the hardware-level BLE connection state (.connected / .disconnected).
  flutterblue.BluetoothConnectionState getConnectionState(String plcId) {
    return _connectionStates[plcId] ??
        flutterblue.BluetoothConnectionState.disconnected;
  }

  /// True while the app has initiated a connection but the hardware has not
  /// yet confirmed it (transitional state not provided by the BLE stack).
  bool isConnecting(String plcId) => _connectingPlcs.contains(plcId);

  /// True while the app has initiated a disconnection but teardown is still
  /// in progress (transitional state not provided by the BLE stack).
  bool isDisconnecting(String plcId) => _disconnectingPlcs.contains(plcId);

  /// True while a reconnect back-off timer is pending for [plcId].
  bool isReconnecting(String plcId) => _reconnectTimers.containsKey(plcId);

  /// The current reconnect attempt number for [plcId] (0 if none in progress).
  int getReconnectAttempt(String plcId) => _reconnectAttempts[plcId] ?? 0;

  ScannedDevice? getDeviceForPlc(String plcId) => _connectedDevices[plcId];

  List<flutterblue.BluetoothService>? getDiscoveredServices(String plcId) {
    return _discoveredServices[plcId];
  }

  flutterblue.BluetoothService? getPlcService(String plcId) {
    return _plcServices[plcId];
  }

  bool hasPlcService(String plcId) {
    return _plcServices.containsKey(plcId) && _plcServices[plcId] != null;
  }

  /// Returns the characteristic for [plcId] at [index] (0–18).
  flutterblue.BluetoothCharacteristic? getChar(String plcId, int index) {
    final list = _chars[plcId];
    if (index < 0 || index >= 26) return null;
    final direct = (list != null && index < list.length) ? list[index] : null;
    if (direct != null) return direct;

    // Packet-mode firmware exposes a single characteristic containing all
    // 26 values. When individual slots are absent, return that packet char so
    // index-aware widgets can extract their own field.
    return _packetCharByPlc[plcId];
  }

  /// Returns an unmodifiable snapshot of the 26-slot characteristic array.
  /// Used by BleDiagnosticScreen to inspect raw BLE state per slot.
  List<flutterblue.BluetoothCharacteristic?> getCharList(String plcId) {
    return List.unmodifiable(_chars[plcId] ?? List.filled(26, null));
  }

  /// Returns `true` if the CCCD for characteristic [index] on [plcId] was
  /// successfully registered during Phase 1/1b setup.  Returns `true` when
  /// no failure data exists (not yet connected, or no failures recorded).
  /// `EmergencyAlertService` uses this to warn when char 10 is degraded.
  bool isCccdRegistered(String plcId, int index) {
    final failed = _failedCcds[plcId];
    return failed == null || !failed.contains(index);
  }

  PLCBluetoothService() {
    initBluetooth();
  }

  void _loadCustomNames() {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('device_name_')) {
        final deviceId = key.substring('device_name_'.length);
        _customNames[deviceId] = prefs.getString(key)!;
      }
    }
  }

  void _loadConnectionHistory() {
    final raw = _prefs?.getStringList('conn_history') ?? [];
    for (final s in raw) {
      final entry = ConnectedDeviceHistory.fromStorageString(s);
      if (entry != null) _connectionHistory.add(entry);
    }
  }

  /// Persists the current plcId → deviceId assignments so they survive app restarts.
  Future<void> _savePlcAssignments() async {
    final entries = _deviceIdForPlc.entries
        .map((e) => '${e.key}|${e.value}')
        .toList();
    await _prefs?.setStringList('plc_assignments', entries);
  }

  /// Loads persisted assignments on startup and primes [_awaitingReAdvertise]
  /// so that when BLE scanning starts each saved device auto-connects.
  void _loadPlcAssignments() {
    final raw = _prefs?.getStringList('plc_assignments') ?? [];
    for (final s in raw) {
      final idx = s.indexOf('|');
      if (idx < 1) continue;
      final plcId = s.substring(0, idx);
      final deviceId = s.substring(idx + 1);
      _deviceIdForPlc[plcId] = deviceId;
      // Prime the re-advertise queue so the device auto-connects the moment
      // it appears in scan results — identical to the mid-session flow.
      _awaitingReAdvertise[deviceId] = plcId;
    }
  }

  Future<void> _saveConnectionHistory() async {
    await _prefs?.setStringList(
      'conn_history',
      _connectionHistory.map((e) => e.toStorageString()).toList(),
    );
  }

  /// Records a successful connection in the persistent history (most-recent
  /// first). Deduplicated per device+plc pair; capped at 20 entries.
  void _recordConnectionHistory(
    String plcId,
    String deviceName,
    String deviceId,
  ) {
    _connectionHistory.removeWhere(
      (e) => e.deviceId == deviceId && e.plcId == plcId,
    );
    _connectionHistory.insert(
      0,
      ConnectedDeviceHistory(
        deviceId: deviceId,
        deviceName: deviceName,
        plcId: plcId,
        connectedAt: DateTime.now(),
      ),
    );
    if (_connectionHistory.length > 20) {
      _connectionHistory.removeRange(20, _connectionHistory.length);
    }
    _saveConnectionHistory(); // fire-and-forget
    _savePlcAssignments(); // persist so next app launch auto-reconnects
    notifyListeners();
  }

  Future<void> clearConnectionHistory() async {
    _connectionHistory.clear();
    await _prefs?.remove('conn_history');
    notifyListeners();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ble_connection_v2',
        channelName: 'BLE Connection Service',
        channelDescription:
            'Keeps Bluetooth connections alive in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.DEFAULT,
        enableVibration: true,
        showWhen: true,
        playSound: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: _autoStartOnBoot,
        allowWakeLock: true,
        stopWithTask: true,
      ),
    );
  }

  /// The persistent "Disconnect All" button shown in the notification.
  static const List<NotificationButton> _notificationButtons = [
    NotificationButton(id: 'stop_service', text: 'Disconnect All'),
  ];

  /// Builds the notification title and body from current BLE + PLC state.
  (String title, String text) _buildNotificationContent() {
    final connectedPlcs = _connectionStates.entries
        .where((e) => e.value == flutterblue.BluetoothConnectionState.connected)
        .map((e) => e.key)
        .toSet();
    final totalConnected = connectedPlcs.length;

    final title = 'PLC Monitor  $totalConnected/4 Connected';

    // Build a concise per-PLC status segment for all 4 slots.
    final segments = <String>[];
    for (final plcId in ['PLC1', 'PLC2', 'PLC3', 'PLC4']) {
      if (connectedPlcs.contains(plcId)) {
        final data = _plcDataMap[plcId];
        final sb = StringBuffer('$plcId ●');
        if (data != null) {
          final cranes = [
            data.crane1Value,
            data.crane2Value,
            data.crane3Value,
            data.crane4Value,
          ];
          final ci = cranes.indexWhere((v) => v > 0);
          if (ci >= 0) {
            sb.write(' C${ci + 1}=${(cranes[ci] / 1000).toStringAsFixed(1)}m');
          }
          if (data.totalLoadKg > 0) {
            sb.write(' ${data.totalLoadKg.toStringAsFixed(0)}kg');
          }
          if (data.dataStopped1Sec) sb.write(' ⚠');
        }
        segments.add(sb.toString());
      } else if (_connectingPlcs.contains(plcId)) {
        segments.add('$plcId ◌');
      } else {
        segments.add('$plcId ○');
      }
    }

    return (title, segments.join('  '));
  }

  /// Pushes fresh content to the Android foreground-service notification.
  void _refreshNotification() async {
    if (!_foregroundServiceRunning || _disposed || !Platform.isAndroid) return;

    final (title, text) = _buildNotificationContent();

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
        notificationButtons: _notificationButtons,
      );
    } catch (e) {
      debugPrint('Notification update error: $e');
    }
  }

  /// Starts a periodic timer that refreshes the notification every 5 seconds
  /// while the foreground service is active.
  void _startNotificationRefreshTimer() {
    _notificationRefreshTimer?.cancel();
    _notificationRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_foregroundServiceRunning || _disposed) {
        _notificationRefreshTimer?.cancel();
        _notificationRefreshTimer = null;
        return;
      }
      _refreshNotification();
    });
  }

  void _updateForegroundService() {
    if (!Platform.isAndroid) return;
    final anyActive =
        _connectionStates.values.any(
          (s) => s == flutterblue.BluetoothConnectionState.connected,
        ) ||
        _connectingPlcs.isNotEmpty;

    // If the user has disabled the persistent notification, stop the service
    // (or never start it) regardless of BLE state.
    if (!_notificationEnabled) {
      if (_foregroundServiceRunning) {
        _foregroundServiceRunning = false;
        _notificationRefreshTimer?.cancel();
        _notificationRefreshTimer = null;
        FlutterForegroundTask.stopService();
      }
      return;
    }

    if (anyActive && !_foregroundServiceRunning) {
      _foregroundServiceRunning = true;
      final (title, text) = _buildNotificationContent();
      FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: title,
        notificationText: text,
        notificationButtons: _notificationButtons,
        callback: bleTaskEntryPoint,
      );
      _startNotificationRefreshTimer();
    } else if (anyActive && _foregroundServiceRunning) {
      // Service already running — refresh the notification content immediately.
      _refreshNotification();
    } else if (!anyActive && _foregroundServiceRunning) {
      _foregroundServiceRunning = false;
      _notificationRefreshTimer?.cancel();
      _notificationRefreshTimer = null;
      FlutterForegroundTask.stopService();
    }
  }

  // ─────────────────────── Notification settings ──────────────────────────

  /// Enable or disable the persistent BLE notification.
  /// Persisted to SharedPreferences and applied immediately.
  Future<void> setNotificationEnabled(bool enabled) async {
    if (_notificationEnabled == enabled) return;
    _notificationEnabled = enabled;
    await _prefs?.setBool('notification_enabled', enabled);
    if (Platform.isAndroid) _updateForegroundService();
    notifyListeners();
  }

  /// Enable or disable auto-start of the foreground service on device boot.
  /// Persisted to SharedPreferences; re-inits the foreground task config.
  Future<void> setAutoStartOnBoot(bool enabled) async {
    if (_autoStartOnBoot == enabled) return;
    _autoStartOnBoot = enabled;
    await _prefs?.setBool('auto_start_on_boot', enabled);
    if (Platform.isAndroid) _initForegroundTask();
    notifyListeners();
  }

  /// Requests the system to exempt this app from battery optimisation.
  /// Shows the system dialog; no-op on non-Android or if already exempted.
  Future<void> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      final ignored =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!ignored) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('Battery optimisation request error: $e');
    }
  }

  /// Returns whether battery optimisation is already ignored for this app.
  Future<bool> get isBatteryOptimizationIgnored async {
    if (!Platform.isAndroid) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Handles messages sent from the [BleForegroundTaskHandler] running in the
  /// service isolate (e.g. user pressed the notification "Disconnect All" button).
  void _onTaskData(Object data) async {
    if (_disposed) return;
    if (data is Map && data['action'] == 'ble_force_stop') {
      debugPrint(
        '📵 Notification stop button pressed — disconnecting all PLCs',
      );
      await disconnectAllPlcs();
      // _updateForegroundService will stop the service now that all connections
      // have been torn down and _connectingPlcs is empty.
    }
  }

  // void _showbleSnackBar({

  //   required String message,
  //   required Color background,
  //   required IconData icon,
  //   Duration duration = const Duration(seconds: 3),
  // }) {
  //   // if (!mounted) return;

  //   Fluttertoast.showToast(
  //     msg: message,
  //     toastLength: _convertDuration(duration),
  //     gravity: ToastGravity.TOP,
  //     backgroundColor: background,
  //     textColor: Colors.white,
  //     fontSize: 14.0,
  //     webShowClose: true,
  //     webPosition: 'right',

  //   );
  // }

  // Helper to convert Duration to Toast length
  // Toast _convertDuration(Duration duration) {
  //   if (duration.inSeconds <= 2) return Toast.LENGTH_SHORT;
  //   return Toast.LENGTH_LONG;
  // }

  Future<void> connectDeviceToPlc(String deviceId, String plcId) async {
    try {
      _connectingPlcs.add(plcId);
      _disconnectingPlcs.remove(plcId);
      _connectionStates[plcId] =
          flutterblue.BluetoothConnectionState.disconnected;

      notifyListeners();
      _updateForegroundService();

      final scannedDevice = _scannedDevices[deviceId];
      if (scannedDevice == null) {
        throw Exception('Device not found');
      }

      if (scannedDevice.isConnected) {
        throw Exception(
          'Device is already connected to ${scannedDevice.assignedPlcId}',
        );
      }

      if (_connectedDevices.containsKey(plcId)) {
        await disconnectPlc(plcId);
      }

      debugPrint('Connecting ${scannedDevice.name} to $plcId');

      // Remember device for auto-reconnect; clear any manual-disconnect flag.
      _deviceIdForPlc[plcId] = deviceId;
      _manuallyDisconnected.remove(plcId);
      _cancelledConnections.remove(plcId);

      // If another device is already occupying this PLC slot, clean up its
      // flags so it returns to the available list and doesn't block the new device.
      final previousOccupant = _connectedDevices[plcId];
      if (previousOccupant != null && previousOccupant.id != deviceId) {
        previousOccupant.isConnected = false;
        previousOccupant.assignedPlcId = null;
        _connectedDevices.remove(plcId);
      }

      _reconnectTimers[plcId]?.cancel();
      _reconnectTimers.remove(plcId);

      // Clear stale GATT state from any previous connection on this slot so
      // the UI never shows data from a device that is no longer attached.
      _plcDataMap.remove(plcId);
      _discoveredServices.remove(plcId);
      _plcServices.remove(plcId);
      _chars.remove(plcId);
      _gattQueues.remove(plcId);
      _failedCcds.remove(plcId);
      _batchUpdateTimers[plcId]?.cancel();
      _batchUpdateTimers.remove(plcId);
      _pendingUpdates.remove(plcId);

      // Immediately mark the device as claimed so it disappears from the
      // available-devices list and cannot be assigned to another PLC block
      // while the connection handshake is in progress.
      scannedDevice.isConnected = true;
      scannedDevice.assignedPlcId = plcId;
      notifyListeners();

      // Attach the connection-state listener BEFORE calling connect() so we
      // cannot miss a disconnect event that occurs during the BLE handshake.
      _connectionStateSubscriptions[plcId]?.cancel();
      _connectionStateSubscriptions.remove(plcId);

      _connectionStateSubscriptions[plcId] = scannedDevice
          .device
          .connectionState
          .listen((state) {
            debugPrint('$plcId connection state → $state');

            if (state == flutterblue.BluetoothConnectionState.connected) {
              // Guard: ignore if a manual disconnect already cleaned this slot.
              if (_cancelledConnections.contains(plcId) ||
                  _disconnectingPlcs.contains(plcId)) {
                return;
              }
              scannedDevice.isConnected = true;
              scannedDevice.assignedPlcId = plcId;
              _connectedDevices[plcId] = scannedDevice;

              // Clear any pending reconnect state.
              _reconnectAttempts.remove(plcId);
              _reconnectTimers[plcId]?.cancel();
              _reconnectTimers.remove(plcId);

              // Request a larger ATT MTU on Android to reduce packet
              // fragmentation when reading the 19 BLE characteristics.
              if (Platform.isAndroid) {
                // Fire MTU request and discover services once it settles.
                // Do NOT return early — fall through to set connected state.
                scannedDevice.device
                    .requestMtu(512)
                    .catchError((e) {
                      debugPrint('$plcId: MTU request failed: $e');
                      return 0;
                    })
                    .whenComplete(
                      () => _discoverServices(plcId, scannedDevice.device),
                    );
              } else {
                _discoverServices(plcId, scannedDevice.device);
              }

              _connectingPlcs.remove(plcId);
              _connectionStates[plcId] =
                  flutterblue.BluetoothConnectionState.connected;
              notifyListeners();
              _updateForegroundService();

              // Record history and clean up auto-reconnect tracking.
              _recordConnectionHistory(
                plcId,
                scannedDevice.name,
                scannedDevice.id,
              );
              _awaitingReAdvertise.removeWhere((k, v) => v == plcId);
              final wasAutoReconnect = _autoReconnectingPlcs.remove(plcId);

              _bleEventController.add(
                BleEvent(
                  type: BleEventType.connected,
                  plcId: plcId,
                  deviceName: scannedDevice.name,
                  isAutoReconnect: wasAutoReconnect,
                ),
              );

              debugPrint(
                '$plcId connected to ${scannedDevice.name} successfully',
              );
            } else if (state ==
                flutterblue.BluetoothConnectionState.disconnected) {
              // Handle unexpected disconnect
              _handleDisconnect(plcId);
            }
          });

      // Initiate the physical BLE connection AFTER attaching the listener so
      // that any disconnect event that fires during the handshake is captured.
      await scannedDevice.device.connect(
        timeout: const Duration(seconds: 30),
        license: flutterblue.License.commercial,
      );
    } catch (e) {
      // Roll back the "claimed" flag so the device becomes available again.
      final sd = _scannedDevices[deviceId];
      if (sd != null) {
        sd.isConnected = false;
        sd.assignedPlcId = null;
      }

      // Cancel the connection-state subscription BEFORE removing the
      // cancelled-connections guard.  Without this a late 'connected' hardware
      // event can fire after the guard is cleared and wrongly mark the PLC as
      // connected even though the user already cancelled the attempt.
      if (_cancelledConnections.contains(plcId)) {
        _connectionStateSubscriptions[plcId]?.cancel();
        _connectionStateSubscriptions.remove(plcId);
      }

      _connectingPlcs.remove(plcId);
      _connectionStates[plcId] =
          flutterblue.BluetoothConnectionState.disconnected;
      notifyListeners();
      _updateForegroundService();
      debugPrint('Connection error for $plcId: $e');

      // Suppress error event when the user explicitly cancelled the attempt.
      if (!_cancelledConnections.remove(plcId)) {
        _bleEventController.add(
          BleEvent(
            type: BleEventType.connectionFailed,
            plcId: plcId,
            deviceName: _scannedDevices[deviceId]?.name ?? deviceId,
            error: e.toString(),
          ),
        );
        rethrow;
      }
    }
  }

  // Handle unexpected disconnect
  void _handleDisconnect(String plcId) {
    // Idempotency guard — prevents double-cleanup if the connection-state
    // listener fires more than once for the same slot.
    if (_connectionStates[plcId] ==
            flutterblue.BluetoothConnectionState.disconnected ||
        _disconnectingPlcs.contains(plcId)) {
      return;
    }

    final device = _connectedDevices[plcId];
    if (device != null) {
      device.isConnected = false;
      device.assignedPlcId = null;
      _cancelledConnections.remove(plcId);

      _connectionStateSubscriptions[plcId]?.cancel();
      _connectionStateSubscriptions.remove(plcId);

      _connectedDevices.remove(plcId);
      _packetCharByPlc.remove(plcId);
      _plcDataMap.remove(plcId);
      _discoveredServices.remove(plcId);
      _plcServices.remove(plcId);

      _chars.remove(plcId);
      _gattQueues.remove(plcId);
      _failedCcds.remove(plcId);

      // Discard any queued batch updates so stale data is never applied
      // after a reconnection races with a pending flush.
      _batchUpdateTimers[plcId]?.cancel();
      _batchUpdateTimers.remove(plcId);
      _pendingUpdates.remove(plcId);

      _connectingPlcs.remove(plcId);
      _disconnectingPlcs.remove(plcId);
      _connectionStates[plcId] =
          flutterblue.BluetoothConnectionState.disconnected;
      notifyListeners();
      _updateForegroundService();

      debugPrint('$plcId disconnected unexpectedly');

      _bleEventController.add(
        BleEvent(
          type: BleEventType.disconnected,
          plcId: plcId,
          deviceName: device.name,
          error: _lastGattError.remove(plcId),
        ),
      );

      // Try to re-establish the connection automatically.
      _scheduleReconnect(plcId);
    }
  }

  Future<void> disconnectPlc(String plcId) async {
    try {
      _manuallyDisconnected.add(plcId);
      _awaitingReAdvertise.removeWhere((k, v) => v == plcId);
      _autoReconnectingPlcs.remove(plcId);
      _reconnectTimers[plcId]?.cancel();
      _reconnectTimers.remove(plcId);
      _reconnectAttempts.remove(plcId);
      // Clear the stored device ID so _scheduleReconnect has nothing to
      // target and cannot re-establish the connection automatically.
      _deviceIdForPlc.remove(plcId);
      _savePlcAssignments(); // persist the cleared assignment

      _disconnectingPlcs.add(plcId);
      _connectingPlcs.remove(plcId);
      notifyListeners();

      final scannedDevice = _connectedDevices[plcId];
      if (scannedDevice != null) {
        debugPrint('Disconnecting $plcId from ${scannedDevice.name}');

        await _prepareForDisconnect(plcId);

        _connectionStateSubscriptions[plcId]?.cancel();
        _connectionStateSubscriptions.remove(plcId);

        await scannedDevice.device.disconnect();

        scannedDevice.isConnected = false;
        scannedDevice.assignedPlcId = null;

        _connectedDevices.remove(plcId);
        _packetCharByPlc.remove(plcId);
        _plcDataMap.remove(plcId);
        _discoveredServices.remove(plcId);
        _plcServices.remove(plcId);

        _chars.remove(plcId);
        _gattQueues.remove(plcId);
        _failedCcds.remove(plcId);

        _batchUpdateTimers[plcId]?.cancel();
        _batchUpdateTimers.remove(plcId);
        _pendingUpdates.remove(plcId);

        _disconnectingPlcs.remove(plcId);
        _connectionStates[plcId] =
            flutterblue.BluetoothConnectionState.disconnected;
        notifyListeners();
        _updateForegroundService();

        debugPrint('$plcId disconnected');
      }
    } catch (e) {
      debugPrint('Disconnect error for $plcId: $e');
      // Only roll back to connected if the device was actually registered;
      // avoids resurrecting state for a slot that was never fully connected.
      _disconnectingPlcs.remove(plcId);
      if (_connectedDevices.containsKey(plcId)) {
        _connectionStates[plcId] =
            flutterblue.BluetoothConnectionState.connected;
      } else {
        _connectionStates[plcId] =
            flutterblue.BluetoothConnectionState.disconnected;
      }
      notifyListeners();
    }
  }

  Future<void> _prepareForDisconnect(String plcId) async {
    final characteristics = [...?_chars[plcId]];

    for (var char in characteristics) {
      if (char != null) {
        try {
          if (char.isNotifying) {
            await char.setNotifyValue(false);
          }
        } catch (e) {
          debugPrint('Error stopping notification: $e');
        }
      }
    }
  }

  /// Disconnect all PLC slots in parallel so a slow teardown on one device
  /// does not delay the others.
  Future<void> disconnectAllPlcs() async {
    await Future.wait(
      _connectedDevices.keys.toList().map((plcId) => disconnectPlc(plcId)),
    );
    _connectedDevices.clear();
    notifyListeners();
  }

  void clearAvailableDevices() {
    final connectedDeviceIds = _connectedDevices.values
        .map((d) => d.id)
        .toSet();
    _scannedDevices.removeWhere(
      (id, device) => !connectedDeviceIds.contains(id),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _gattQueues.clear();
    _awaitingReAdvertise.clear();
    _autoReconnectingPlcs.clear();
    _notificationRefreshTimer?.cancel();
    _notificationRefreshTimer = null;
    _scanSubscription?.cancel();
    _scanningStateSubscription?.cancel();
    _adapterStateSubscription?.cancel();

    // Cancel all pending reconnect timers so they don't fire after disposal.
    for (final t in _reconnectTimers.values) {
      t.cancel();
    }
    _reconnectTimers.clear();

    for (final t in _batchUpdateTimers.values) {
      t.cancel();
    }
    _batchUpdateTimers.clear();
    _pendingUpdates.clear();

    _bleEventController.close();

    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    }

    for (var subscription in _connectionStateSubscriptions.values) {
      subscription.cancel();
    }

    flutterblue.FlutterBluePlus.stopScan();
    disconnectAllPlcs();

    _disposed = true;
    super.dispose();
  }

  Future<void> _discoverServices(
    String plcId,
    flutterblue.BluetoothDevice device,
  ) async {
    try {
      debugPrint('Discovering services for $plcId...');
      // Small delay lets the ESP32 BLE stack finish advertising its GATT
      // table before we enumerate it.
      await Future.delayed(const Duration(milliseconds: 500));

      List<flutterblue.BluetoothService> services = await device
          .discoverServices();
      _discoveredServices[plcId] = services;
      debugPrint('Found ${services.length} services for PLC $plcId');
      _findPlcService(plcId, services);

      // If the target service was not found yet, wait and retry once.
      // The ESP32 sometimes takes a moment to publish all GATT services.
      if (!_plcServices.containsKey(plcId) || _plcServices[plcId] == null) {
        debugPrint(
          '$plcId: ACS service not found, retrying discovery in 2 s...',
        );
        await Future.delayed(const Duration(seconds: 2));
        // Guard: connection may have been lost during the wait.
        if (_connectionStates[plcId] !=
            flutterblue.BluetoothConnectionState.connected) {
          return;
        }
        services = await device.discoverServices();
        _discoveredServices[plcId] = services;
        debugPrint('$plcId: retry found ${services.length} services');
        _findPlcService(plcId, services);
      }
    } catch (e) {
      debugPrint('Error discovering services for PLC $plcId: $e');
    }
  }

  void _findPlcService(
    String plcId,
    List<flutterblue.BluetoothService> services,
  ) {
    flutterblue.BluetoothService? plcService;

    // First try to match by the known ACS Diagnostic Monitor service UUID.
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == _bleServiceUuid) {
        plcService = service;
        debugPrint('PLC $plcId: Found ACS service by UUID: ${service.uuid}');
        break;
      }
    }

    if (plcService == null) {
      for (var service in services) {
        final uuidStr = service.uuid.toString().toLowerCase();
        if (uuidStr.contains('fff0') || uuidStr.contains('6e41')) {
          plcService = service;
          debugPrint(
            'PLC $plcId: Found service by UUID pattern: ${service.uuid}',
          );
          break;
        }
      }
    }

    if (plcService == null && services.isNotEmpty) {
      plcService = services.first;
      debugPrint('PLC $plcId: Using first service as fallback');
    }

    if (plcService != null) {
      _plcServices[plcId] = plcService;
      _identifyCharacteristics(plcId, plcService);
    } else {
      debugPrint('PLC $plcId: No suitable service found');
    }
  }

  Future<void> _identifyCharacteristics(
    String plcId,
    flutterblue.BluetoothService service,
  ) async {
    final characteristics = service.characteristics;

    // Map all 26 slots by UUID so the order the BLE stack returns them does
    // not matter.  The ESP32 ACS firmware assigns characteristic UUIDs using
    // the pattern:
    //   index i  →  UUID  6e41{(i+2):04X}-b5a3-f393-e0a9-e50e24dcca9e
    // e.g.  index 0  →  6e410002-...   index 19 →  6e410015-...
    // Fall back to positional ordering for any characteristic whose UUID does
    // not match the pattern (unrecognised firmware variants etc.).
    final List<flutterblue.BluetoothCharacteristic?> slots = List.filled(
      26,
      null,
    );

    final unmatched = <flutterblue.BluetoothCharacteristic>[];

    flutterblue.BluetoothCharacteristic? packetChar;

    for (final char in characteristics) {
      final uuidStr = char.uuid.toString().toLowerCase();
      if (uuidStr == _packetCharUuid && packetChar == null) {
        packetChar = char;
      }
      // Expected format: 6e41xxxx-b5a3-f393-e0a9-e50e24dcca9e
      // Extract the 4-digit hex group after '6e41'.
      bool placed = false;
      if (uuidStr.length >= 8 && uuidStr.startsWith('6e41')) {
        try {
          final hexPart = uuidStr.substring(4, 8);
          final charNum = int.parse(hexPart, radix: 16);
          final index = charNum - 2; // index 0 → 0x0002, index 23 → 0x0019
          if (index >= 0 && index < 26 && slots[index] == null) {
            slots[index] = char;
            placed = true;
          }
        } catch (_) {
          // UUID doesn't follow the pattern; handled below.
        }
      }
      if (!placed) unmatched.add(char);
    }

    // Diagnostic log — shows UUID mapping result in logcat / debug console.
    final mappedCount = slots.where((s) => s != null).length;
    debugPrint(
      'BLE[$plcId] UUID map: $mappedCount/26 matched, '
      '${unmatched.length} unmatched. '
      'Unmatched UUIDs: ${unmatched.map((c) => c.uuid.toString().split('-').first).join(', ')}',
    );

    // Fill any remaining empty slots with unmatched characteristics in order.
    int unmatchedIdx = 0;
    for (int i = 0; i < 26 && unmatchedIdx < unmatched.length; i++) {
      if (slots[i] == null) {
        slots[i] = unmatched[unmatchedIdx++];
      }
    }
    _chars[plcId] = slots;
    if (packetChar != null) {
      _packetCharByPlc[plcId] = packetChar;
    } else {
      _packetCharByPlc.remove(plcId);
    }

    // Seed an empty data entry so the detail screen shows widgets immediately
    // instead of staying stuck on "Waiting for data..." until the first
    // notification arrives (notify-only characteristics never trigger a read).
    _plcDataMap[plcId] ??= PLCData.empty(plcId, 'PLC $plcId');
    debugPrint(
      'PLC $plcId: Identified ${characteristics.length} characteristics',
    );

    // ── Phase 1: Register CCCD notifications ────────────────────────────────
    // Routed through a per-device _GattQueue that serialises writes and
    // retries up to 3× on GATT 133 with exponential back-off (200/500/1000 ms).
    // The fixed 50 ms inter-write delay is no longer needed.
    final queue = _gattQueues[plcId] ??= _GattQueue();
    final failedCcds = <int>{};
    for (final i in _setupOrder) {
      if (_connectionStates[plcId] !=
          flutterblue.BluetoothConnectionState.connected) {
        debugPrint(
          'BLE[$plcId] Phase 1 interrupted at char[$i] — disconnected',
        );
        break;
      }
      final char = slots[i];
      if (char == null || !char.properties.notify) continue;
      try {
        await queue.run(() => char.setNotifyValue(true));
        debugPrint('BLE[$plcId] char[$i] setNotifyValue(true) ✓');
      } catch (e) {
        failedCcds.add(i);
        debugPrint('BLE[$plcId] char[$i] setNotifyValue FAILED: $e');
        final errStr = e.toString();
        if (errStr.contains('133') || errStr.toUpperCase().contains('GATT')) {
          _lastGattError[plcId] = errStr;
        }
      }
    }

    // ── Phase 1b: Retry failed CCCDs after a brief recovery pause ────────────
    // _GattQueue already retried each char 3× internally.  If failures remain
    // the GATT stack may still recover after a short pause (e.g. ESP32 BLE
    // congestion clearing).  Safety-critical chars (index 10 = outputPINRelay)
    // get one extra attempt here before we decide monitoring is degraded.
    var stillFailed = failedCcds;
    if (failedCcds.isNotEmpty &&
        _connectionStates[plcId] ==
            flutterblue.BluetoothConnectionState.connected) {
      debugPrint(
        'BLE[$plcId] Phase 1b: retrying ${failedCcds.length} failed CCCD(s) '
        'after recovery pause (indices: ${failedCcds.join(', ')})…',
      );
      await Future.delayed(const Duration(milliseconds: 1500));

      if (_connectionStates[plcId] ==
          flutterblue.BluetoothConnectionState.connected) {
        final retryQueue = _GattQueue();
        stillFailed = <int>{};
        for (final i in failedCcds) {
          if (_connectionStates[plcId] !=
              flutterblue.BluetoothConnectionState.connected) {
            break;
          }
          final char = slots[i];
          if (char == null || !char.properties.notify) continue;
          try {
            await retryQueue.run(() => char.setNotifyValue(true));
            debugPrint('BLE[$plcId] char[$i] Phase 1b setNotifyValue(true) ✓');
          } catch (e) {
            stillFailed.add(i);
            debugPrint('BLE[$plcId] char[$i] Phase 1b FAILED permanently: $e');
          }
        }
      }
    }

    // Persist final failure set and alert on safety-critical failures.
    _failedCcds[plcId] = stillFailed;
    if (stillFailed.isNotEmpty) {
      final criticalFailures = stillFailed.intersection(_criticalCharIndices);
      if (criticalFailures.isNotEmpty) {
        debugPrint(
          '🚨 BLE[$plcId] CRITICAL: CCCD registration permanently failed for '
          'safety-critical char indices $criticalFailures — '
          'emergency relay monitoring may be inactive.',
        );
        _bleEventController.add(
          BleEvent(
            type: BleEventType.cccdRegistrationFailed,
            plcId: plcId,
            deviceName: _connectedDevices[plcId]?.displayName ?? plcId,
            error:
                'CCCD registration failed for char indices: $criticalFailures. '
                'Emergency relay monitoring may be inactive.',
          ),
        );
      }
    }

    debugPrint(
      'BLE[$plcId] Phase 1 complete'
      '${stillFailed.isEmpty ? ' — all CCCDs registered' : ' — ${stillFailed.length} CCCD(s) failed: $stillFailed'}',
    );

    // Bail out if the link dropped during Phase 1 — publishing stale
    // characteristics or attempting seed reads on a dead GATT link causes
    // cascading GATT errors on the next reconnect attempt.
    if (_connectionStates[plcId] ==
        flutterblue.BluetoothConnectionState.disconnected) {
      debugPrint('BLE[$plcId] dropped during Phase 1 — aborting Phase 2/3');
      return;
    }

    // ── Phase 2: Publish characteristics to the UI ───────────────────────────
    // Widgets build NOW and subscribe to each characteristic's lastValueStream.
    // Live BLE notifications from the ESP32 flow directly to each widget.
    notifyListeners();

    // ── Phase 3: Seed initial values (fire-and-forget background reads) ───────
    // Each char's read() updates its own lastValueStream independently when it
    // completes — every widget renders at its own pace, none blocks another.
    _seedInitialReads(plcId, slots); // intentionally unawaited
  }

  /// Seeds initial characteristic values after Phase 2 ([notifyListeners]).
  ///
  /// Runs in the background (unawaited). Each [char.read()] pushes its result
  /// onto [lastValueStream] independently the moment it completes, so every
  /// widget updates at its own pace — no characteristic blocks another.
  Future<void> _seedInitialReads(
    String plcId,
    List<flutterblue.BluetoothCharacteristic?> slots,
  ) async {
    if (_connectionStates[plcId] !=
        flutterblue.BluetoothConnectionState.connected) {
      debugPrint('BLE[$plcId] Phase 3 skipped — already disconnected');
      return;
    }

    debugPrint('BLE[$plcId] Phase 3: seeding initial reads (parallel)...');

    // All reads are dispatched at once so a mid-sequence disconnect fails
    // every in-flight read with a GATT error rather than silently skipping
    // the remaining characteristics.  The Android/iOS GATT stack serialises
    // ATT operations internally, so there are no collision hazards and the
    // artificial 30 ms inter-read delay is unnecessary.
    Future<void> readOne(int i) async {
      final char = slots[i];
      if (char == null || !char.properties.read) return;
      try {
        final data = await char.read();
        final hex = data
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        debugPrint('BLE[$plcId] char[$i] seed = [$hex] (${data.length} bytes)');
      } catch (e) {
        debugPrint('BLE[$plcId] char[$i] seed read FAILED: $e');
        final errStr = e.toString();
        if (errStr.contains('133') || errStr.toUpperCase().contains('GATT')) {
          _lastGattError[plcId] = errStr;
        }
      }
    }

    await Future.wait(_setupOrder.map(readOne), eagerError: false);
    debugPrint('BLE[$plcId] Phase 3 complete — all characteristics seeded');
  }

  // Retain empty maps so disconnect/dispose cleanup code compiles unchanged.
  final Map<String, Map<int, dynamic>> _pendingUpdates = {};
  final Map<String, Timer> _batchUpdateTimers = {};

  // --- Auto-reconnect -------------------------------------------------------

  static const int _maxReconnectAttempts = 5;

  /// Delay in seconds before each successive reconnect attempt
  /// (3 s, 6 s, 12 s, 24 s, 30 s).
  static const List<int> _reconnectDelays = [3, 6, 12, 24, 30];

  /// Schedule a reconnect attempt for [plcId] with exponential back-off.
  void _scheduleReconnect(String plcId) {
    if (_manuallyDisconnected.contains(plcId)) return;
    if (_crashDetector.record(plcId)) return; // Stop if crash loop

    final deviceId = _deviceIdForPlc[plcId];
    if (deviceId == null) return;

    final device = _scannedDevices[deviceId];
    if (device != null) {
      final now = DateTime.now();
      final isAdvertising =
          now.difference(device.lastSeen) <= _advertisingTimeout;

      if (!isAdvertising) {
        debugPrint(
          ' $plcId: device $deviceId not advertising — waiting for re-advertise',
        );
        _bleEventController.add(
          BleEvent(
            type: BleEventType.connectionFailed,
            plcId: plcId,
            deviceName: device.name,
            error: 'Device stopped advertising',
          ),
        );
        // Track for re-advertise reconnect instead of giving up permanently.
        _awaitingReAdvertise[deviceId] = plcId;
        return;
      }
    }

    final attempt = _reconnectAttempts[plcId] ?? 0;
    if (attempt >= _maxReconnectAttempts) {
      debugPrint('$plcId: max reconnect attempts reached');
      _reconnectAttempts.remove(plcId);
      return;
    }

    // Jittered backoff to prevent reconnection storms
    final baseDelay =
        _reconnectDelays[attempt.clamp(0, _reconnectDelays.length - 1)];
    final jitter = Random().nextInt(1000) / 1000; // 0-1s jitter
    final delaySecs = baseDelay + jitter;

    debugPrint(
      '$plcId: reconnect attempt ${attempt + 1}/$_maxReconnectAttempts in ${delaySecs.toStringAsFixed(1)}s',
    );

    _reconnectTimers[plcId]?.cancel();
    _reconnectTimers[plcId] = Timer(
      Duration(milliseconds: (delaySecs * 1000).toInt()),
      () => _attemptReconnect(plcId, deviceId, attempt + 1),
    );
  }

  Future<void> _attemptReconnect(
    String plcId,
    String deviceId,
    int attempt,
  ) async {
    if (_manuallyDisconnected.contains(plcId)) return;
    if (_connectionStates[plcId] ==
            flutterblue.BluetoothConnectionState.connected ||
        _connectingPlcs.contains(plcId)) {
      return; // already connected / in progress
    }

    final device = _scannedDevices[deviceId];
    if (device != null) {
      final now = DateTime.now();
      final isAdvertising =
          now.difference(device.lastSeen) <= _advertisingTimeout;

      if (!isAdvertising) {
        debugPrint(
          ' $plcId: device $deviceId not advertising — aborting reconnect, waiting for re-advertise',
        );
        // Track for re-advertise reconnect instead of giving up permanently.
        _awaitingReAdvertise[deviceId] = plcId;
        _bleEventController.add(
          BleEvent(
            type: BleEventType.connectionFailed,
            plcId: plcId,
            deviceName: device.name,
            error: 'Device stopped advertising',
          ),
        );
        return;
      }
    }

    debugPrint('$plcId: reconnect attempt $attempt/$_maxReconnectAttempts...');
    _reconnectAttempts[plcId] = attempt;
    _autoReconnectingPlcs.add(plcId);

    try {
      await connectDeviceToPlc(deviceId, plcId);
    } catch (e) {
      _autoReconnectingPlcs.remove(plcId);
      debugPrint('$plcId: reconnect attempt $attempt failed: $e');
      // If the connect call threw synchronously (device not in scan cache
      // etc.), schedule the next attempt ourselves.
      if (_connectionStates[plcId] !=
          flutterblue.BluetoothConnectionState.connected) {
        _scheduleReconnect(plcId);
      }
    }
  }

  // ── Re-advertise auto-reconnect ───────────────────────────────────────────

  /// Called whenever a device appears (or re-appears) in scan results.
  /// If the device was previously waiting for re-advertise on behalf of a PLC
  /// slot, and that slot is still free, an auto-reconnect is triggered.
  void _checkReAdvertiseReconnect(String deviceId) {
    final waitingPlcId = _awaitingReAdvertise[deviceId];
    if (waitingPlcId == null) return;

    final slotFree =
        _connectionStates[waitingPlcId] ==
            flutterblue.BluetoothConnectionState.disconnected &&
        !_connectingPlcs.contains(waitingPlcId);

    _awaitingReAdvertise.remove(deviceId);

    if (!slotFree) {
      debugPrint(
        '🔄 $waitingPlcId: slot no longer free — skipping re-advertise reconnect',
      );
      return;
    }

    debugPrint(
      ' $waitingPlcId: Device $deviceId re-advertising — scheduling auto-reconnect',
    );
    Future.microtask(
      () => _attemptAutoReconnectOnReAdvertise(waitingPlcId, deviceId),
    );
  }

  /// Initiates a connection for a device that re-appeared after previously
  /// stopping advertising while assigned to [plcId].
  Future<void> _attemptAutoReconnectOnReAdvertise(
    String plcId,
    String deviceId,
  ) async {
    if (_disposed) return;
    if (_manuallyDisconnected.contains(plcId)) return;
    if (_connectionStates[plcId] ==
            flutterblue.BluetoothConnectionState.connected ||
        _connectingPlcs.contains(plcId)) {
      return;
    }

    debugPrint(' $plcId: Auto-reconnecting to re-advertising device $deviceId');
    _autoReconnectingPlcs.add(plcId);
    try {
      await connectDeviceToPlc(deviceId, plcId);
    } catch (e) {
      _autoReconnectingPlcs.remove(plcId);
      debugPrint(' $plcId: Re-advertise auto-reconnect failed: $e');
      // connectDeviceToPlc already emits a connectionFailed event.
    }
  }
}
