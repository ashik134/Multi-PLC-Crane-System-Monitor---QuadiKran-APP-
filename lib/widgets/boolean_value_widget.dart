import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BooleanValueWidget extends StatefulWidget {
  final BluetoothCharacteristic? characteristic;
  final String label;
  final int? packetIndex;

  const BooleanValueWidget({
    super.key,
    required this.characteristic,
    required this.label,
    this.packetIndex,
  });

  @override
  State<BooleanValueWidget> createState() => _BooleanValueWidgetState();
}

class _BooleanValueWidgetState extends State<BooleanValueWidget> {
  bool isNotifying = false;
  bool isReading = false;
  bool? _value;
  String _lastUpdateTime = '';

  StreamSubscription<List<int>>? _notificationSubscription;
  Timer? _readTimer;
  Timer? _safetyReadTimer;

  // Pre-compiled once — avoids RegExp construction on every BLE notification.
  static final _printableRe = RegExp(r'[^\x20-\x7E]');
  static final _numberRe = RegExp(r'[-+]?[0-9]*\.?[0-9]+');

  @override
  void initState() {
    super.initState();
    _initializeMonitoring();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    super.dispose();
  }

  /// Called by Flutter whenever the parent rebuilds with a different prop value.
  /// The most important case: the service replaces `_chars[plcId]` with fresh
  /// BluetoothCharacteristic objects after a reconnect, so the Consumer passes
  /// a new (or null) characteristic reference here. Cancel the stale
  /// subscription and resubscribe to the new one immediately.
  @override
  void didUpdateWidget(covariant BooleanValueWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.characteristic != oldWidget.characteristic) {
      // Tear down everything tied to the old characteristic.
      _cancelAllSubscriptions();
      _resetState();
      // Do NOT call setNotifyValue(false) — the service owns the GATT subscription.
      // Start fresh on the new characteristic (null → skip, non-null → subscribe).
      if (widget.characteristic != null) {
        _initializeMonitoring();
      }
    }
  }

  void _cancelAllSubscriptions() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _readTimer?.cancel();
    _readTimer = null;
    _safetyReadTimer?.cancel();
    _safetyReadTimer = null;
  }

  void _resetState() {
    isNotifying = false;
    isReading = false;
    _value = null;
    _lastUpdateTime = '';
  }

  Future<void> _initializeMonitoring() async {
    if (widget.characteristic == null) return;

    // Do NOT call _readValue() here — concurrent readCharacteristic calls from
    // all 24 widgets collide with the service's sequential setNotifyValue loop,
    // causing ERROR_GATT_WRITE_REQUEST_BUSY. The service seeds an initial read.
    await _startNotifications().catchError((error) {
      debugPrint('BooleanValueWidget notification setup failed: $error');
    });

    // Guard against disposal while _startNotifications() was executing.
    if (!mounted) return;

    if (widget.characteristic != null &&
        !widget.characteristic!.properties.notify &&
        widget.characteristic!.properties.read) {
      _startPeriodicReading();
    }

    // Safety net: if the value is still null after 4 s (the service's initial
    // char.read() fired before this widget subscribed and the ESP32 hasn't sent
    // a new notification), do one explicit read to pull the current value.
    // Only applicable for characteristics that support read.
    if (widget.characteristic!.properties.read) {
      _safetyReadTimer = Timer(const Duration(seconds: 4), () async {
        // Only read if the BLE device is still connected — firing a
        // readCharacteristic on a dropping/dead link causes GATT_ERROR 133
        // which forces a full disconnect.
        if (mounted &&
            _value == null &&
            !isReading &&
            (widget.characteristic?.device.isConnected ?? false)) {
          await _readValue();
        }
      });
    }
  }

  Future<void> _readValue() async {
    if (widget.characteristic == null ||
        isReading ||
        !widget.characteristic!.properties.read) {
      return;
    }

    if (mounted) setState(() => isReading = true);
    try {
      if (widget.characteristic!.properties.read) {
        final data = await widget.characteristic!.read();
        _processData(data);
      }
    } catch (e) {
      debugPrint('BooleanValueWidget read failed: $e');
    } finally {
      if (mounted) setState(() => isReading = false);
    }
  }

  Future<void> _startNotifications() async {
    if (widget.characteristic == null ||
        isNotifying ||
        !widget.characteristic!.properties.notify) {
      return;
    }

    try {
      // Use lastValueStream instead of onValueReceived so that:
      // (a) if the service already seeded a value via char.read() before this
      //     widget subscribed, we immediately get it (replay semantics); and
      // (b) all future notifications and reads are still delivered.
      _notificationSubscription = widget.characteristic!.lastValueStream.listen(
        _processData,
        onError: (error) {
          debugPrint('BooleanValueWidget notification error: $error');
          if (mounted) setState(() => isNotifying = false);
        },
        onDone: () {
          // Null the subscription so _startNotifications() won't try to cancel
          // an already-closed subscription on the next call.
          _notificationSubscription = null;
          if (mounted) setState(() => isNotifying = false);
        },
      );

      if (mounted) setState(() => isNotifying = true);
      debugPrint('BooleanValueWidget: monitoring enabled for ${widget.label}');
    } catch (e) {
      debugPrint('BooleanValue notification setup failed: $e');
      return;
    }
  }

  void _startPeriodicReading() {
    _readTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (widget.characteristic != null &&
          widget.characteristic!.properties.read &&
          !isReading) {
        await _readValue();
      }
    });
  }

  void _stopMonitoring() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    // Do NOT call setNotifyValue(false) — the service owns the GATT subscription.
    // Cancelling the stream subscription only pauses this widget's display.
    if (mounted) setState(() => isNotifying = false);
    debugPrint('BooleanValueWidget: monitoring stopped for ${widget.label}');
  }

  void _processData(List<int> data) {
    if (!mounted) return;
    // Skip the initial lastValueStream replay (empty list) — avoids setting
    // a stale timestamp before any real BLE notification has arrived.
    if (data.isEmpty) return;

    try {
      final ts = DateTime.now();
      // Include centiseconds so rapid updates show distinct timestamps.
      final newTime =
          '${ts.hour.toString().padLeft(2, '0')}:'
          '${ts.minute.toString().padLeft(2, '0')}:'
          '${ts.second.toString().padLeft(2, '0')}.'
          '${(ts.millisecond ~/ 10).toString().padLeft(2, '0')}';

      final str = String.fromCharCodes(
        data,
      ).replaceAll(_printableRe, '').trim().toLowerCase();

      bool? newValue;

      // Packet mode: payload is a bracketed CSV of all 26 values.
      if (widget.packetIndex != null &&
          str.contains('[') &&
          str.contains(']')) {
        final start = str.indexOf('[');
        final end = str.lastIndexOf(']');
        if (start >= 0 && end > start) {
          final inner = str.substring(start + 1, end);
          final parts = inner.split(',');
          final idx = widget.packetIndex!;
          if (idx >= 0 && idx < parts.length) {
            final token = parts[idx].trim();
            if (token == 'true' || token == '1') {
              newValue = true;
            } else if (token == 'false' || token == '0') {
              newValue = false;
            } else {
              final match = _numberRe.firstMatch(token);
              if (match != null) {
                final n = double.tryParse(match.group(0)!);
                if (n != null) newValue = n != 0;
              }
            }
          }
        }
      }

      // Single-value mode fallback.
      if (newValue == null) {
        if (str == 'true' || str == '1') {
          newValue = true;
        } else if (str == 'false' || str == '0') {
          newValue = false;
        } else {
          // Raw byte fallback: any non-zero byte = true
          newValue = data[0] != 0;
        }
      }

      // Always update the timestamp so every notification is visible, even
      // when the parsed value is the same as before. Only update _value when
      // we have a valid parse result — avoids wiping a good value with null.
      if (mounted && (_value != newValue || _lastUpdateTime != newTime)) {
        setState(() {
          if (newValue != null) _value = newValue;
          _lastUpdateTime = newTime;
        });
      }
    } catch (e) {
      debugPrint('BooleanValueWidget parse error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCharacteristic = widget.characteristic != null;
    final hasValue = _value != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: hasCharacteristic ? Colors.black87 : Colors.grey,
                  ),
                ),
                if (_lastUpdateTime.isNotEmpty)
                  Text(
                    'Updated: $_lastUpdateTime',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
          if (!hasCharacteristic)
            const Text(
              'N/A',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isNotifying ? Colors.green : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                if (isReading && !hasValue)
                  const SizedBox(
                    width: 50,
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 50,
                    height: 24,
                    decoration: BoxDecoration(
                      color: hasValue
                          ? (_value!
                                ? const Color.fromARGB(255, 74, 137, 76)
                                : const Color.fromARGB(255, 235, 87, 87))
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      hasValue ? (_value! ? 'ON' : 'OFF') : '—',
                      style: TextStyle(
                        color: hasValue ? Colors.white : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (hasCharacteristic &&
                    widget.characteristic!.properties.notify) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: isNotifying ? _stopMonitoring : _startNotifications,
                    child: Icon(
                      isNotifying ? Icons.pause_circle : Icons.play_circle,
                      size: 18,
                      color: isNotifying ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
