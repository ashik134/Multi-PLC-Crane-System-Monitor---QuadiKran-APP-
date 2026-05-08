import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fb;

import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// BLE Diagnostic Screen — Packet Mode
///
/// Diagnostics for single-characteristic packet mode.
/// One characteristic (UUID 6e410002) carries all 26 values as [v0,v1,...,v25].
/// ─────────────────────────────────────────────────────────────────────────────
class BleDiagnosticScreen extends StatefulWidget {
  final String plcId;

  const BleDiagnosticScreen({super.key, required this.plcId});

  @override
  State<BleDiagnosticScreen> createState() => _BleDiagnosticScreenState();
}

class _BleDiagnosticScreenState extends State<BleDiagnosticScreen> {
  static const List<String> _charNames = [
    'Data Stopped', // 0  bool
    'Err Comm C1', // 1  bool
    'Err Comm C2', // 2  bool
    'Err Comm C3', // 3  bool
    'Sensor Connected', // 4  bool
    'DAT Not Found', // 5  bool
    'Remote DAT N1', // 6  bool
    'Remote DAT N2', // 7  bool
    'Remote DAT N3', // 8  bool
    'Zero Distance', // 9  bool
    'Output Relay', // 10 bool
    'Output PIN 1', // 11 bool
    'Output PIN 2', // 12 bool
    'Output PIN 3', // 13 bool
    'Output PIN 4', // 14 bool
    'Crane 1 (mm)', // 15 float
    'Crane 2 (mm)', // 16 float
    'Crane 3 (mm)', // 17 float
    'Crane 4 (mm)', // 18 float
    'H1 Load (kg)', // 19 float
    'H2 Load (kg)', // 20 float
    'Total Load (kg)', // 21 float
    'Bypass Crane 3', // 22 bool
    'Bypass Crane 4', // 23 bool
    'Err Comm C4', // 24 bool
    'Remote DAT N4', // 25 bool
  ];

  // Single packet characteristic (UUID 6e410002 → slot index 0)
  fb.BluetoothCharacteristic? _packetChar;

  // Live tracking
  List<int>? _lastRawValue;
  List<int>? _replayValue;
  int _liveEventCount = 0;
  DateTime? _lastUpdate;
  bool _hasError = false;
  bool _isReading = false;
  StreamSubscription<List<int>>? _subscription;

  // Parsed per-field values extracted from each packet
  final List<String> _parsedValues = List.filled(26, '—');

  bool _autoRefresh = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _init();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_autoRefresh && mounted) setState(() {});
    });
  }

  void _init() {
    final svc = Provider.of<PLCBluetoothService>(context, listen: false);
    // getChar falls back to the packet characteristic for any missing slot,
    // so index 0 reliably returns the single packet char in packet-mode firmware.
    _packetChar = svc.getChar(widget.plcId, 0);

    if (_packetChar == null) return;

    // Capture cached replay value
    _packetChar!.lastValueStream.first
        .then((value) {
          if (mounted) setState(() => _replayValue = value);
        })
        .catchError((_) {});

    // Subscribe to live notifications
    _subscription = _packetChar!.onValueReceived.listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _lastRawValue = value;
          _liveEventCount++;
          _lastUpdate = DateTime.now();
          _parsePacket(value);
        });
      },
      onError: (error) {
        debugPrint('Packet char error: $error');
        if (mounted) setState(() => _hasError = true);
      },
    );
  }

  void _reinit() {
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _packetChar = null;
      _lastRawValue = null;
      _replayValue = null;
      _liveEventCount = 0;
      _lastUpdate = null;
      _hasError = false;
      _parsedValues.fillRange(0, 26, '—');
    });
    _init();
  }

  Future<void> _readNow() async {
    if (_packetChar == null || !_packetChar!.properties.read) return;
    setState(() => _isReading = true);
    try {
      await _packetChar!.read();
    } catch (e) {
      debugPrint('Read failed: $e');
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  /// Parse a `[v0,v1,...,v25]` packet and update [_parsedValues].
  void _parsePacket(List<int> data) {
    final ascii = String.fromCharCodes(data.where((b) => b >= 32 && b < 127));
    final clean = ascii.trim();

    if (!clean.contains('[') || !clean.contains(']')) return;
    final start = clean.indexOf('[');
    final end = clean.lastIndexOf(']');
    if (start < 0 || end <= start) return;

    final parts = clean.substring(start + 1, end).split(',');
    for (int i = 0; i < 26 && i < parts.length; i++) {
      final token = parts[i].trim();
      final v = double.tryParse(token);
      if (v == null) {
        _parsedValues[i] = token;
        continue;
      }
      final isFloat = i >= 15 && i <= 21;
      if (isFloat) {
        _parsedValues[i] = v.toStringAsFixed(3);
      } else {
        _parsedValues[i] = v != 0.0 ? 'TRUE' : 'FALSE';
      }
    }
  }

  Color _getStatusColor() {
    if (_packetChar == null) return Colors.grey;
    if (_hasError) return Colors.red;
    if (!_packetChar!.isNotifying) return Colors.red;
    if (_liveEventCount == 0) return Colors.orange;
    return Colors.green;
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 1) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final svc = Provider.of<PLCBluetoothService>(context);
    final allServices = svc.getDiscoveredServices(widget.plcId) ?? [];
    final plcService = svc.getPlcService(widget.plcId);
    final connState = svc.getConnectionState(widget.plcId);
    final connected = connState == fb.BluetoothConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F6),
      appBar: AppBar(
        title: const Text('BLE Diagnostics', style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _autoRefresh ? Icons.autorenew : Icons.autorenew_outlined,
            ),
            tooltip: 'Toggle auto-refresh',
            onPressed: () => setState(() => _autoRefresh = !_autoRefresh),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reinitialize',
            onPressed: _reinit,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(connected, connState, allServices, plcService),
          _buildPacketCharCard(),
          _buildActionBar(),
          _buildLegend(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: 26,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _buildValueRow(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    bool connected,
    fb.BluetoothConnectionState connState,
    List<fb.BluetoothService> allSvcs,
    fb.BluetoothService? plcSvc,
  ) {
    return Container(
      width: double.infinity,
      color: connected ? Colors.green.shade50 : Colors.red.shade50,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: connected ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.plcId} · ${connState.name.toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Services: ${allSvcs.length} | Selected: ${plcSvc?.uuid.toString().split('-')[0] ?? 'N/A'}',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPacketCharCard() {
    final char = _packetChar;
    final statusColor = _getStatusColor();

    if (char == null) {
      return Container(
        color: Colors.red.shade50,
        padding: const EdgeInsets.all(12),
        child: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 16),
            SizedBox(width: 8),
            Text(
              'Packet characteristic not found',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final uuid = char.uuid.toString().toUpperCase();
    final rawAscii = _lastRawValue != null
        ? String.fromCharCodes(_lastRawValue!.where((b) => b >= 32 && b < 127))
        : null;
    final replayAscii = _replayValue != null
        ? String.fromCharCodes(_replayValue!.where((b) => b >= 32 && b < 127))
        : null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Packet Characteristic',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  '$_liveEventCount events',
                  style: TextStyle(fontSize: 10, color: Colors.green.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'UUID: $uuid',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _buildChip('NOTIFY', char.properties.notify),
              _buildChip('READ', char.properties.read),
              _buildChip('WRITE', char.properties.write),
              _buildChip('NOTIFYING', char.isNotifying, color: Colors.green),
              if (_hasError) _buildChip('ERROR', true, color: Colors.red),
            ],
          ),
          if (rawAscii != null) ...[
            const SizedBox(height: 8),
            _buildRawDataBox(
              label: 'Live',
              text: rawAscii,
              timestamp: _lastUpdate,
              color: Colors.green,
            ),
          ] else if (replayAscii != null) ...[
            const SizedBox(height: 8),
            _buildRawDataBox(
              label: 'Replay (cached)',
              text: replayAscii,
              color: Colors.blue,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRawDataBox({
    required String label,
    required String text,
    DateTime? timestamp,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$label: ',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (timestamp != null)
                Text(
                  _formatTime(timestamp),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: color.shade800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isReading ? null : _readNow,
              icon: _isReading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_isReading ? 'Reading...' : 'Force Read'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() {
              _liveEventCount = 0;
              _parsedValues.fillRange(0, 26, '—');
            }),
            tooltip: 'Reset counters',
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        children: [
          _legendItem(Colors.green, 'Notifying + data'),
          _legendItem(Colors.orange, 'Notifying, no data'),
          _legendItem(Colors.red, 'Not notifying / error'),
          _legendItem(Colors.grey, 'No characteristic'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildValueRow(int index) {
    final name = _charNames[index];
    final value = _parsedValues[index];
    final isFloat = index >= 15 && index <= 21;

    Color valueBg = Colors.grey.shade100;
    Color valueColor = Colors.black54;

    if (value == 'TRUE') {
      valueBg = Colors.orange.shade50;
      valueColor = Colors.orange.shade800;
    } else if (value == 'FALSE') {
      valueBg = Colors.green.shade50;
      valueColor = Colors.green.shade700;
    } else if (isFloat && value != '—') {
      valueBg = Colors.blue.shade50;
      valueColor = Colors.blue.shade700;
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$index',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  isFloat ? 'FLOAT' : 'BOOL',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: valueBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: isFloat ? 'monospace' : null,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool active, {Color? color}) {
    final activeColor =
        color ?? (label == 'NOTIFY' ? Colors.blue : Colors.teal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? activeColor.withAlpha(25) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: active ? activeColor : Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: active ? activeColor : Colors.grey,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
