import 'package:flutter/material.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:rev4_quadikran_monitoring/models/plc_data.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  reconnecting,
  unstable,
}

class PLCBlock extends StatelessWidget {
  final String plcId;
  final String? plcName;
  final PLCData? plcData;
  final BluetoothDevice? device;
  final String? connectedDeviceId;
  final String? connectedDeviceName;
  final ConnectionStatus connectionState;
  final VoidCallback onTap;
  final VoidCallback onConnectPressed;
  final VoidCallback onDisconnectPressed;
  final VoidCallback? onCancelConnection;
  final String? connectingDeviceName;
  final int? characteristicCount;
  final int? rssi;
  final int reconnectAttempt;
  final int maxReconnectAttempts;

  final bool isInEmergency;

  const PLCBlock({
    super.key,
    required this.plcId,
    this.plcName,
    this.plcData,
    this.connectedDeviceId,
    this.connectedDeviceName,
    this.device,
    required this.connectionState,
    required this.onTap,
    required this.onConnectPressed,
    required this.onDisconnectPressed,
    this.onCancelConnection,
    this.connectingDeviceName,
    this.characteristicCount,
    this.rssi,
    this.reconnectAttempt = 0,
    this.maxReconnectAttempts = 3,
    this.isInEmergency = false,
  });

  // though rebuilds are cheap here
  bool get isConnected => connectionState == ConnectionStatus.connected;
  bool get isConnecting => connectionState == ConnectionStatus.connecting;
  bool get isDisconnecting => connectionState == ConnectionStatus.disconnecting;
  bool get isReconnecting => connectionState == ConnectionStatus.reconnecting;
  bool get isUnstable => connectionState == ConnectionStatus.unstable;
  bool get isLoading => isConnecting || isDisconnecting;
  bool get showData => !isLoading && plcData != null;

  // Cache gradient colors to avoid recreation on every build
  static const _connectedGradient = [Color(0xFF2196F3), Color(0xFF1976D2)];
  static const _connectingGradient = [Color(0xFFFFB74D), Color(0xFFF57C00)];
  static final _disconnectedGradient = [
    const Color(0xFF9E9E9E).withAlpha(128),
    const Color(0xFF9E9E9E).withAlpha(128),
  ];

  static const _statusColors = {
    ConnectionStatus.connecting: Colors.orange,
    ConnectionStatus.disconnecting: Colors.orange,
    ConnectionStatus.connected: Colors.green,
    ConnectionStatus.reconnecting: Color(0xFFF57C00),
    ConnectionStatus.unstable: Color(0xFFD32F2F),
    ConnectionStatus.disconnected: Colors.red,
  };

  String _getStatusText() {
    switch (connectionState) {
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.disconnecting:
        return 'Disconnecting...';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting ($reconnectAttempt/$maxReconnectAttempts)';
      case ConnectionStatus.unstable:
        return 'Unstable';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  (IconData, Color)? _getRssiInfo() {
    if (rssi == null) return null;
    return switch (rssi!) {
      >= -60 => (Icons.signal_cellular_alt, Colors.green),
      >= -75 => (Icons.signal_cellular_alt_2_bar, Colors.orange),
      _ => (Icons.signal_cellular_alt_1_bar, Colors.red),
    };
  }

  String _getDisplayName() {
    if (plcName?.isNotEmpty == true) return plcName!;
    if (plcData?.plcName.isNotEmpty == true) return plcData!.plcName;
    if (plcId.isNotEmpty) return plcId;
    return 'Unknown PLC';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _getStatusText();
    final statusColor = _statusColors[connectionState] ?? Colors.grey;
    final rssiInfo = _getRssiInfo();
    final displayName = _getDisplayName();

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _getGradientColors(),
          ),
          borderRadius: BorderRadius.circular(16),
          // boxShadow: const [
          //   BoxShadow(
          //     color: Colors.black

          //   ),
          // ],
        ),
        child: Stack(
          children: [
            if (isLoading) _loadingOverlay(statusText),
            _statusIndicators(statusColor, rssiInfo),
            _content(statusText, displayName),
            // Emergency relay active — pulsing border + badge.
            if (isInEmergency) ..._errorIndicators(),
          ],
        ),
      ),
    );
  }

  List<Color> _getGradientColors() {
    if (isConnected) return _connectedGradient.cast<Color>();
    if (isConnecting || isDisconnecting || isReconnecting) {
      return _connectingGradient.cast<Color>();
    }
    return _disconnectedGradient.cast<Color>();
  }

  /// Builds the pulsing red border + "RELAY ON" badge shown during an error
  List<Widget> _errorIndicators() {
    return [
      Positioned.fill(
        child:
            IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF3B30),
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66FF3B30),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 0.2, end: 1.0, duration: 700.ms),
      ),
      // "RELAY ON" badge
      Positioned(
        bottom: 8,
        left: 8,
        child:
            Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_rounded,
                      color: Color(0xFFFF3B30),
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'RELAY ON',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 0.5, end: 1.0, duration: 500.ms)
                .scaleXY(
                  begin: 0.95,
                  end: 1.05,
                  duration: 500.ms,
                  curve: Curves.easeInOut,
                ),
      ),
    ];
  }

  Widget _loadingOverlay(String statusText) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(77),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              statusText,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isConnecting && connectingDeviceName != null) ...[
              const SizedBox(height: 4),
              // Container(
              //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              //   decoration: BoxDecoration(
              //     color: Colors.white24,
              //     borderRadius: BorderRadius.circular(12),
              //   ),
              //   child: Text(
              //     connectingDeviceName!,
              //     style: const TextStyle(color: Colors.white70, fontSize: 10),
              //   ),
              // ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIndicators(Color statusColor, (IconData, Color)? rssiInfo) {
    return Positioned(
      top: 6,
      right: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          if (rssiInfo != null) ...[
            const SizedBox(height: 4),
            Tooltip(
              message: '$rssi dBm',
              child: Icon(rssiInfo.$1, size: 14, color: rssiInfo.$2),
            ),
          ],
          if (isUnstable) ...[
            const SizedBox(height: 4),
            const Tooltip(
              message: 'Unstable connection',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: Colors.amber,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _content(String statusText, String displayName) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24), // Space for status indicators
          Text(
            plcId,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            displayName,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              color: Colors.black,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (!isLoading && !isConnected && !isReconnecting) ...[
            const Spacer(),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, size: 14, color: Colors.white60),
                SizedBox(width: 4),
                Text(
                  'Tap to connect',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontFamily: 'Asul',
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
          if (!isLoading && isConnected && connectedDeviceName != null) ...[
            const SizedBox(height: 4),
            _buildInfoChip(label: connectedDeviceId!, fontSize: 9),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Tap to see details',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'Asul',
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (!isLoading && !isConnected && isReconnecting) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (isConnecting && connectingDeviceName != null) ...[
            const SizedBox(height: 4),
            _buildInfoChip(
              label: connectingDeviceName!,
              fontSize: 9,
              backgroundColor: Colors.white24,
            ),
          ],
          const Spacer(),

          if (isConnected || isConnecting) ...[
            const SizedBox(height: 8),
            _buildActionButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    IconData? icon,
    required String label,
    double fontSize = 9,
    Color? backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white24,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white.withAlpha(179)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: Colors.white, fontSize: fontSize),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    final isInConnectingState = isConnecting && onCancelConnection != null;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isInConnectingState
            ? onCancelConnection
            : onDisconnectPressed,
        icon: Icon(
          isInConnectingState ? Icons.close : Icons.link_off,
          size: 14,
          color: Colors.white,
        ),
        label: Text(
          isInConnectingState ? 'Cancel' : 'Disconnect',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white54, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: const Size(0, 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
