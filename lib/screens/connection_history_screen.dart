import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';

const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
// const _kSlate950 = Color(0xFF020617);
// const _kSlate900 = Color(0xFF0F172A);
const _kSlate800 = Color(0xFF1E293B);
// const _kSlate700 = Color(0xFF334155);
// const _kSlate600 = Color(0xFF475569);
const _kSlate500 = Color(0xFF64748B);
const _kSlate400 = Color(0xFF94A3B8);
const _kSlate300 = Color(0xFFFFFFF1);
const _kPrimaryCyan = Color(0xFF06B6D4);

class ConnectionHistoryScreen extends StatelessWidget {
  const ConnectionHistoryScreen({super.key});

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _plcColor(String plcId) {
    return switch (plcId) {
      'PLC1' => _kPrimaryCyan,
      'PLC2' => _kEmerald,
      'PLC3' => _kAmber,
      'PLC4' => _kRed,
      _ => _kSlate500,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF030B1F),
                Color(0xFF0B2C5D),
                Color(0xFF1F3F7A),
                Color(0xFF2F3F7F),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            // borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'Connection History',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          Consumer<PLCBluetoothService>(
            builder: (context, service, _) {
              if (service.connectionHistory.isEmpty) return const SizedBox();
              return TextButton.icon(
                onPressed: service.clearConnectionHistory,
                icon: const Icon(Icons.delete_sweep, size: 18, color: _kRed),
                label: const Text(
                  'Clear',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    color: _kRed,
                    fontSize: 14,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kSlate300),
        ),
      ),
      body: Consumer<PLCBluetoothService>(
        builder: (context, service, _) {
          return RepaintBoundary(child: _buildContent(service));
        },
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _kSlate400),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _kSlate300,
          ),
        ),
      ],
    );
  }

  Widget? _buildContent(PLCBluetoothService service) {
    final history = service.connectionHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: _kSlate800,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_toggle_off,
                size: 40,
                color: _kSlate500,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No History Yet',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Device connections will appear here.',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 14,
                color: _kSlate500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: Colors.blue.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              _statChip(Icons.link, '${history.length}', 'Total'),
              const SizedBox(width: 16),
              _statChip(
                Icons.access_time,
                _formatTimeAgo(history.first.connectedAt),
                'Last',
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _kSlate800),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: history.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 72, color: _kSlate800),
            itemBuilder: (context, index) {
              final entry = history[index];
              final color = _plcColor(entry.plcId);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withAlpha(80)),
                  ),
                  child: Icon(
                    Icons.bluetooth_connected,
                    color: color,
                    size: 18,
                  ),
                ),
                title: Text(
                  entry.deviceName,
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.plcId,
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.deviceId,
                            style: const TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 10,
                              color: _kSlate500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Text(
                  _formatTimeAgo(entry.connectedAt),
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 11,
                    color: _kSlate400,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
