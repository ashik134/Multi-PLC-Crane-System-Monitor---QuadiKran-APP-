import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class FloatValueWidget extends StatefulWidget {
  final BluetoothCharacteristic? characteristic;
  final String label;
  final Color? accentColor;
  final int? packetIndex;

  const FloatValueWidget({
    super.key,
    required this.characteristic,
    required this.label,
    this.accentColor,
    this.packetIndex,
  });

  @override
  State<FloatValueWidget> createState() => _FloatValueWidgetState();
}

class _FloatValueWidgetState extends State<FloatValueWidget> {
  // State variables:
  bool isNotifying = false;
  bool isReading = false;
  String _value = '—';
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

  @override
  void didUpdateWidget(covariant FloatValueWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.characteristic != oldWidget.characteristic) {
      // Tear down everything tied to the old characteristic.
      _cancelAllSubscriptions();
      _resetState();
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
    _value = '—';
    _lastUpdateTime = '';
  }

  Future<void> _initializeMonitoring() async {
    if (widget.characteristic == null) return;

    // Do NOT call _readValue() here — concurrent readCharacteristic calls from
    // all 24 widgets collide with the service's sequential setNotifyValue loop,
    // causing ERROR_GATT_WRITE_REQUEST_BUSY. The service seeds an initial read.
    await _startNotifications().catchError((error) {
      debugPrint('FloatValueWidget notification setup failed: $error');
    });

    // Guard against disposal while _startNotifications() was executing.
    if (!mounted) return;

    if (widget.characteristic != null &&
        !widget.characteristic!.properties.notify &&
        widget.characteristic!.properties.read) {
      _startPeriodicReading();
    }

    // Safety net: if the value is still '—' after 4 s (e.g., the service's
    // initial char.read() fired before this widget subscribed to lastValueStream
    // and no further notification arrived), do one explicit read to pull the
    // current value.  Only applicable for characteristics that support read.
    if (widget.characteristic!.properties.read) {
      _safetyReadTimer = Timer(const Duration(seconds: 4), () async {
        // Only read if the BLE device is still connected — firing a
        // readCharacteristic on a dropping/dead link causes GATT_ERROR 133
        // which forces a full disconnect.
        if (mounted &&
            _value == '—' &&
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
      debugPrint('FloatValueWidget read failed: $e');
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
        (data) => _processData(data),
        onError: (error) {
          debugPrint('FloatValueWidget notification error: $error');
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
      debugPrint('FloatValueWidget: monitoring enabled for ${widget.label}');
    } catch (e) {
      debugPrint('FloatValue notification setup failed: $e');
      return;
    }
  }

  void _startPeriodicReading() {
    _readTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
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
    debugPrint('FloatValueWidget: monitoring stopped for ${widget.label}');
  }

  void _processData(List<int> data) {
    if (!mounted) return;
    // Skip the initial lastValueStream replay (empty list) — avoids setting
    // a stale timestamp before any real BLE notification has arrived.
    if (data.isEmpty) return;

    try {
      final ts = DateTime.now();
      final newTime =
          '${ts.hour.toString().padLeft(2, '0')}:'
          '${ts.minute.toString().padLeft(2, '0')}:'
          '${ts.second.toString().padLeft(2, '0')}:'
          '${(ts.millisecond ~/ 10).toString().padLeft(2, '0')}';

      String? parsed;

      // Step 1 — ASCII numeric string (ESP32 text mode).
      final ascii = String.fromCharCodes(data);
      final clean = ascii.replaceAll(_printableRe, '').trim();

      // Step 0 — packet mode: [v0,v1,...,v25], extract this widget's index.
      if (widget.packetIndex != null &&
          clean.contains('[') &&
          clean.contains(']')) {
        final start = clean.indexOf('[');
        final end = clean.lastIndexOf(']');
        if (start >= 0 && end > start) {
          final inner = clean.substring(start + 1, end);
          final parts = inner.split(',');
          final idx = widget.packetIndex!;
          if (idx >= 0 && idx < parts.length) {
            final token = parts[idx].trim();
            final v = double.tryParse(token);
            if (v != null) {
              parsed = v.toStringAsFixed(2);
            }
          }
        }
      }

      if (clean.isNotEmpty) {
        final match = _numberRe.firstMatch(clean);
        if (match != null) {
          try {
            parsed ??= double.parse(match.group(0)!).toStringAsFixed(2);
          } catch (_) {}
        }
      }

      // Step 2 — IEEE 754 little-endian float32 (ESP32 binary mode).
      // Also runs when clean was non-empty but had no valid number, so that
      // partially-printable binary bytes don't show as garbage text.
      if (parsed == null && data.length >= 4) {
        try {
          final bd = ByteData(4);
          for (int j = 0; j < 4; j++) {
            bd.setUint8(j, data[j]);
          }
          final value = bd.getFloat32(0, Endian.little);
          if (value.isFinite) parsed = value.toStringAsFixed(2);
        } catch (_) {}
      }

      // Step 3 — 16-bit big-endian integer (scaled ÷ 100).
      if (parsed == null && data.length >= 2) {
        final raw = (data[0] << 8) | data[1];
        parsed = (raw / 100.0).toStringAsFixed(2);
      }

      // Step 4 — raw printable text fallback.
      if (parsed == null && clean.isNotEmpty) parsed = clean;

      if (mounted && (_value != parsed || _lastUpdateTime != newTime)) {
        setState(() {
          _value = parsed ?? '—';
          _lastUpdateTime = newTime;
        });
      }
    } catch (e) {
      debugPrint('FloatValueWidget parse error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCharacteristic = widget.characteristic != null;
    final color = widget.accentColor ?? Colors.blue;
    final hasValue = _value != '—';

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
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  Text(
                    _value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: hasValue ? color : Colors.grey,
                    ),
                  ),
                if (hasCharacteristic &&
                    widget.characteristic!.properties.notify) ...[
                  const SizedBox(width: 8),
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
