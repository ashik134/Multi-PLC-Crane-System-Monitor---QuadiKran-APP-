import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:vibration/vibration.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:rev4_quadikran_monitoring/models/emergency_alert.dart';
import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';

class EmergencyAlertService extends ChangeNotifier with WidgetsBindingObserver {
  final PLCBluetoothService _bleService;

  AppLifecycleState? _lifecycleState;

  bool get _isAppInForeground =>
      _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;

  static const List<String> _plcIds = ['PLC1', 'PLC2', 'PLC3', 'PLC4'];

  static const int _relayCharIndex = 10;

  // ── Subscription tracking ────────────────────────────────────────────────
  /// Live stream subscriptions, keyed by plcId.
  final Map<String, StreamSubscription<List<int>>> _charSubs = {};

  /// Last characteristic reference we subscribed to per PLC.
  /// Used to detect when `PLCBluetoothService` replaces chars after reconnect.
  final Map<String, fb.BluetoothCharacteristic?> _trackedChars = {};

  // ── Alert state ──────────────────────────────────────────────────────────
  /// PLCs where `outputPINRelay` is currently `true`.
  final Set<String> _activeRelays = {};

  /// PLCs with an active relay that the user has NOT yet acknowledged.
  /// This drives the in-app overlay visibility.
  final Set<String> _pendingAlerts = {};

  /// PLCs acknowledged by the user while the relay is still active.
  /// Removed when the relay clears so the next trip re-triggers the overlay.
  final Set<String> _acknowledgedAlerts = {};

  // ── Public state getters ─────────────────────────────────────────────────
  /// Returns `true` when at least one PLC has a new, unacknowledged alert.
  bool get hasPendingAlert => _pendingAlerts.isNotEmpty;

  /// Unmodifiable snapshot of PLC IDs with unacknowledged active alerts.
  Set<String> get pendingAlerts => Set.unmodifiable(_pendingAlerts);

  /// Unmodifiable snapshot of PLC IDs where outputPINRelay is currently true.
  Set<String> get activeRelays => Set.unmodifiable(_activeRelays);

  /// Display name for [plcId] — delegates to the BLE service.
  String getDeviceNameForPlc(String plcId) =>
      _bleService.getDeviceForPlc(plcId)?.displayName ?? plcId;

  // ── Alert stream (for overlay) ───────────────────────────────────────────
  final StreamController<EmergencyAlert> _alertCtrl =
      StreamController<EmergencyAlert>.broadcast();

  /// Emits an [EmergencyAlert] on each rising and falling relay edge.
  /// The overlay widget subscribes here to react immediately.
  Stream<EmergencyAlert> get alertStream => _alertCtrl.stream;

  // ── Local notifications ──────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();
  bool _notifReady = false;

  static const String _channelId = 'plc_emergency_relay';
  static const String _channelName = 'PLC Emergency Relay';

  // ── Regex — compiled once ─────────────────────────────────────────────────
  static final _nonPrintableRe = RegExp(r'[^\x20-\x7E]');
  static final _numberRe = RegExp(r'[-+]?[0-9]*\.?[0-9]+');

  bool _disposed = false;

  /// Subscription to [PLCBluetoothService.bleEvents] — watches for permanent
  /// CCCD registration failures on char 10 (outputPINRelay).
  StreamSubscription<BleEvent>? _bleEventSub;

  // ─────────────────────────────────────────────────────────────────────────
  EmergencyAlertService(this._bleService) {
    WidgetsBinding.instance.addObserver(this);
    _bleService.addListener(_onBleStateChanged);
    _bleEventSub = _bleService.bleEvents.listen(_onBleEvent);
    _initNotifications().then((_) {
      // Initial sweep — PLCs may already be connected when this service starts.
      _onBleStateChanged();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _bleService.removeListener(_onBleStateChanged);
    _bleEventSub?.cancel();
    _bleEventSub = null;
    for (final sub in _charSubs.values) {
      sub.cancel();
    }
    _charSubs.clear();
    _alertCtrl.close();
    super.dispose();
  }

  // ── BLE safety-event listener ─────────────────────────────────────────────

  /// Listens for [BleEventType.cccdRegistrationFailed] events.
  /// When char 10 (outputPINRelay) could not be registered, logs a prominent
  /// warning so that operators and developers are aware that emergency relay
  /// monitoring is degraded for that PLC slot.
  void _onBleEvent(BleEvent event) {
    if (_disposed) return;
    if (event.type != BleEventType.cccdRegistrationFailed) return;
    if (!_bleService.isCccdRegistered(event.plcId, _relayCharIndex)) {
      debugPrint(
        'EmergencyAlertService [${event.plcId}]: char[$_relayCharIndex] '
        '(outputPINRelay) CCCD registration failed — live emergency relay '
        'notifications will NOT be received for this device. '
        'Detail: ${event.error}',
      );
    }
  }

  // ── BLE listener ─────────────────────────────────────────────────────────

  /// Called every time `PLCBluetoothService` calls `notifyListeners()`.
  /// Refreshes characteristic subscriptions for all slots.
  void _onBleStateChanged() {
    if (_disposed) return;
    for (final plcId in _plcIds) {
      _refreshCharSub(plcId);
    }
  }

  /// Ensures this service is subscribed to the correct characteristic for
  /// [plcId].  Tears down stale subscriptions when the char object changes
  /// (e.g. after a reconnect that replaces the `_chars` map in the service).
  void _refreshCharSub(String plcId) {
    // `getChar(plcId, 10)` returns:
    //  • packet char   — packet-mode firmware (all 26 values in one char)
    //  • individual char — individual-char firmware (direct bool value)
    //  • null           — PLC disconnected / GATT setup not yet complete
    final char = _bleService.getChar(plcId, _relayCharIndex);

    // No-op if we are already subscribed to the same object.
    if (_trackedChars[plcId] == char) return;

    // Tear down old subscription.
    _charSubs[plcId]?.cancel();
    _charSubs.remove(plcId);
    _trackedChars[plcId] = char;

    if (char == null) {
      _handlePlcDisconnected(plcId);
      return;
    }

    // Passive subscription — CCCD is already registered by PLCBluetoothService.
    // `lastValueStream` replays the last value immediately on subscription so
    // the current relay state is captured even before the next BLE packet.
    _charSubs[plcId] = char.lastValueStream.listen(
      (data) => _processPacket(plcId, data),
      onError: (Object e) =>
          debugPrint('EmergencyAlertService[$plcId] stream error: $e'),
      cancelOnError: false,
    );
    debugPrint(
      'EmergencyAlertService: subscribed to char[$_relayCharIndex] for $plcId',
    );
  }

  void _handlePlcDisconnected(String plcId) {
    final wasActive = _activeRelays.contains(plcId);
    _activeRelays.remove(plcId);
    _pendingAlerts.remove(plcId);
    _acknowledgedAlerts.remove(plcId);
    if (wasActive) notifyListeners();
  }

  // ── Packet parsing ────────────────────────────────────────────────────────

  void _processPacket(String plcId, List<int> data) {
    if (_disposed || data.isEmpty) return;

    final relayActive = _parseRelayState(data);
    if (relayActive == null) return; // Unrecognised payload — skip.

    final wasActive = _activeRelays.contains(plcId);
    if (wasActive == relayActive) return; // No state change — skip.

    if (relayActive) {
      _activeRelays.add(plcId);
      _onRelayTriggered(plcId);
    } else {
      _activeRelays.remove(plcId);
      _onRelayCleared(plcId);
    }
  }

  /// Extracts the `outputPINRelay` field (index 10) from a raw BLE payload.
  ///
  /// Handles both packet-mode payloads `[v0,v1,...,v25]` and single-value
  /// payloads (individual-characteristic firmware).  Returns `null` when the
  /// payload cannot be decoded.
  bool? _parseRelayState(List<int> data) {
    final str = String.fromCharCodes(
      data,
    ).replaceAll(_nonPrintableRe, '').trim().toLowerCase();

    // ── Packet mode ──────────────────────────────────────────────────────
    if (str.contains('[') && str.contains(']')) {
      final start = str.indexOf('[');
      final end = str.lastIndexOf(']');
      if (start >= 0 && end > start) {
        final parts = str.substring(start + 1, end).split(',');
        if (_relayCharIndex < parts.length) {
          final token = parts[_relayCharIndex].trim();
          if (token == 'true' || token == '1') return true;
          if (token == 'false' || token == '0') return false;
          final m = _numberRe.firstMatch(token);
          if (m != null) {
            final n = double.tryParse(m.group(0)!);
            if (n != null) return n != 0;
          }
        }
      }
      return null; // Packet format but index 10 not decodable.
    }

    // ── Single-value mode (individual characteristic) ─────────────────────
    if (str == 'true' || str == '1') return true;
    if (str == 'false' || str == '0') return false;
    final m = _numberRe.firstMatch(str);
    if (m != null) {
      final n = double.tryParse(m.group(0)!);
      if (n != null) return n != 0;
    }
    return null;
  }

  // ── Alert lifecycle ───────────────────────────────────────────────────────

  void _onRelayTriggered(String plcId) {
    final deviceName = getDeviceNameForPlc(plcId);

    // Only add to pending if not yet acknowledged in this active session.
    if (!_acknowledgedAlerts.contains(plcId)) {
      _pendingAlerts.add(plcId);
    }

    _alertCtrl.add(
      EmergencyAlert(
        plcId: plcId,
        deviceName: deviceName,
        triggeredAt: DateTime.now(),
        isActive: true,
      ),
    );
    notifyListeners();
    _fireLocalNotification(plcId, deviceName);
    // Vibrate the device when in foreground; the notification handles background.
    if (_isAppInForeground) _vibrateDevice();
    debugPrint('🚨 EMERGENCY: outputPINRelay = TRUE  [$plcId / $deviceName]');
  }

  void _onRelayCleared(String plcId) {
    final deviceName = getDeviceNameForPlc(plcId);

    _pendingAlerts.remove(plcId);
    _acknowledgedAlerts.remove(plcId); // Reset so next trip re-alerts.

    _alertCtrl.add(
      EmergencyAlert(
        plcId: plcId,
        deviceName: deviceName,
        triggeredAt: DateTime.now(),
        isActive: false,
      ),
    );
    notifyListeners();
    _cancelLocalNotification(plcId);
    if (_isAppInForeground) Vibration.cancel();
    debugPrint('✅ Emergency cleared: outputPINRelay = FALSE  [$plcId]');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Dismiss the in-app overlay for [plcId].  The relay state is unchanged —
  /// if it trips again later the overlay will reappear.
  void acknowledgeAlert(String plcId) {
    if (_pendingAlerts.remove(plcId)) {
      if (_activeRelays.contains(plcId)) {
        // Relay still active — record acknowledgment so we don't re-trigger
        // on the next BLE packet (which would still read relay = true).
        _acknowledgedAlerts.add(plcId);
      }
      notifyListeners();
    }
  }

  /// Dismiss all pending overlays at once.
  void acknowledgeAll() {
    if (_pendingAlerts.isEmpty) return;
    for (final plcId in _pendingAlerts) {
      if (_activeRelays.contains(plcId)) {
        _acknowledgedAlerts.add(plcId);
      }
    }
    _pendingAlerts.clear();
    notifyListeners();
  }

  // ── Local notifications ───────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    if (_notifReady) return;
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _notifPlugin.initialize(settings);
      _notifReady = true;
      debugPrint('EmergencyAlertService: local notifications initialised');
    } catch (e) {
      debugPrint('EmergencyAlertService: notification init failed: $e');
    }
  }

  Future<void> _fireLocalNotification(String plcId, String deviceName) async {
    if (!_notifReady) await _initNotifications();
    if (!_notifReady) return; // Give up if init keeps failing.

    try {
      NotificationDetails details;

      if (Platform.isAndroid) {
        final androidDetails = AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Critical PLC relay alerts requiring immediate attention.',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'Emergency: Output Relay Active',
          category: AndroidNotificationCategory.alarm,
          // Shows as a full-screen overlay (heads-up) on the lock screen.
          // Requires USE_FULL_SCREEN_INTENT permission (added to manifest).
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
          playSound: true,
          enableLights: true,
          ledColor: const Color(0xFFFF0000),
          ledOnMs: 500,
          ledOffMs: 300,
          color: const Color(0xFFFF0000),
          channelShowBadge: true,
          // Keep visible until user swipes it away.
          autoCancel: false,
        );
        details = NotificationDetails(android: androidDetails);
      } else if (Platform.isIOS) {
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          // timeSensitive bypasses Focus / Do-Not-Disturb on iOS 15+.
          interruptionLevel: InterruptionLevel.timeSensitive,
        );
        details = const NotificationDetails(iOS: iosDetails);
      } else {
        return;
      }

      // One stable notification ID per PLC slot (0—3).
      final notifId = _plcIds.indexOf(plcId);
      final truncName = deviceName.length > 30
          ? '${deviceName.substring(0, 27)}...'
          : deviceName;

      await _notifPlugin.show(
        notifId,
        '🚨 Emergency: Output Relay Active',
        '$plcId ($truncName) — outputPINRelay ACTIVE. Check equipment immediately.',
        details,
      );
    } catch (e) {
      debugPrint('EmergencyAlertService: notification show failed: $e');
    }
  }

  Future<void> _cancelLocalNotification(String plcId) async {
    try {
      final notifId = _plcIds.indexOf(plcId);
      await _notifPlugin.cancel(notifId);
    } catch (e) {
      debugPrint('EmergencyAlertService: notification cancel failed: $e');
    }
  }

  // ── App lifecycle observer ────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  // ── Device vibration ─────────────────────────────────────────────────────

  /// Drives the vibration motor with an SOS-style pattern when the app is
  /// in the foreground.  The OS notification handles background vibration.
  Future<void> _vibrateDevice() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;
      // Pattern: [delay_ms, on_ms, off_ms, on_ms, off_ms, on_ms]
      await Vibration.vibrate(pattern: [0, 600, 200, 600, 200, 600]);
    } catch (e) {
      debugPrint('EmergencyAlertService: vibration error: $e');
    }
  }
}
