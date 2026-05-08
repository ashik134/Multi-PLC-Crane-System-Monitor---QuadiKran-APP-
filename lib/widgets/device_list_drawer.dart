import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';

(String, Color) _rssiLabel(int rssi) {
  if (rssi >= -60) return ('Strong', Colors.green);
  if (rssi >= -75) return ('Good', Colors.lightGreen);
  if (rssi >= -85) return ('Fair', Colors.orange);
  return ('Weak', Colors.red);
}

class DeviceListDrawer extends StatelessWidget {
  const DeviceListDrawer({super.key, required this.applyFilter});

  final List<ScannedDevice> Function(List<ScannedDevice>) applyFilter;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Consumer<PLCBluetoothService>(
        builder: (context, service, child) {
          final connectedDevices = service.connectedDevices().values.toList();
          final connectingDevices = service.connectingDevices();
          final availableDevices = service.availableDevices;
          final devices = applyFilter(availableDevices);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF030B1F),
                        Color(0xFF0B2C5D),
                        Color(0xFF1F3F7A),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bluetooth Devices',
                          style: TextStyle(
                            fontFamily: 'Trirong',
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${connectedDevices.length} connected | '
                          '${connectingDevices.length} connecting | '
                          '${devices.length} available',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: service.isScanning
                                    ? () {
                                        service.stopScanning();
                                      }
                                    : () {
                                        service.startScanning();
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: service.isScanning
                                      ? const Color.fromARGB(255, 26, 79, 159)
                                      : Colors.white,
                                  foregroundColor: service.isScanning
                                      ? Colors.white
                                      : const Color(0xFF0B2C5D),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  service.isScanning ? 'STOP' : 'SCAN',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: devices.isEmpty
                                    ? null
                                    : () {
                                        service.clearAvailableDevices();
                                      },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('CLEAR'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Connecting Devices Section
                if (connectingDevices.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'CONNECTING (${connectingDevices.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...connectingDevices.entries.map(
                    (entry) => Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.bluetooth_searching,
                          color: Colors.orange,
                        ),
                        title: Text(
                          entry.value.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          'Connecting to ${entry.key}…\n${entry.value.id}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.orange,
                                size: 16,
                              ),
                              onPressed: () =>
                                  service.cancelConnectionAttempt(entry.key),
                              tooltip: 'Cancel connection',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(),
                  ),
                ],

                // Connected Devices Section
                if (connectedDevices.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'CONNECTED (${connectedDevices.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...connectedDevices.map(
                    (device) => Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.bluetooth_connected,
                          color: Colors.green,
                        ),
                        title: Text(
                          device.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          '${device.assignedPlcId} • ${device.rssi}dBm',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 16),
                              onPressed: () =>
                                  _showRenameDialog(context, service, device),
                              tooltip: 'Rename device',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                            Chip(
                              label: Text(
                                device.assignedPlcId ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(),
                  ),
                ],

                // Available Devices Section Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bluetooth,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AVAILABLE (${devices.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),

                // Available Devices List
                if (devices.isEmpty)
                  SizedBox(
                    height: 100,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No devices found',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap SCAN to discover devices',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    padding: const EdgeInsets.only(top: 20),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final rssiInfo = _rssiLabel(device.rssi);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.bluetooth,
                            color: Colors.blue,
                          ),
                          title: Text(
                            device.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),

                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  device.id,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 0),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: rssiInfo.$2.withAlpha(31),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.signal_cellular_alt,
                                      size: 12,
                                      color: rssiInfo.$2,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${device.rssi}dBm',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: rssiInfo.$2,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 16),
                                onPressed: () =>
                                    _showRenameDialog(context, service, device),
                                tooltip: 'Rename device',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showPlcAssignmentDialog(context, device);
                          },
                        ),
                      );
                    },
                  ),

                // Add bottom padding for scroll
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPlcAssignmentDialog(BuildContext context, ScannedDevice device) {
    final plcs = ['PLC1', 'PLC2', 'PLC3', 'PLC4'];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Assign "${device.displayName == 'Unknown Device' ? device.device.remoteId : device.displayName}"',
            style: const TextStyle(fontSize: 18),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: plcs.length,
              itemBuilder: (context, index) {
                final plcId = plcs[index];
                final service = Provider.of<PLCBluetoothService>(
                  context,
                  listen: false,
                );
                final isPlcConnected = service.getDeviceForPlc(plcId) != null;
                final isPlcConnecting = service.isConnecting(plcId);
                final isBlocked = isPlcConnected || isPlcConnecting;

                return Opacity(
                  opacity: isBlocked ? 0.5 : 1.0,
                  child: ListTile(
                    leading: Icon(
                      isPlcConnected
                          ? Icons.link
                          : isPlcConnecting
                          ? Icons.hourglass_top
                          : Icons.link_off,
                      color: isPlcConnected
                          ? Colors.green
                          : isPlcConnecting
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    title: Text(
                      plcId,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: isPlcConnecting
                        ? const Text(
                            'Connecting…',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    enabled: !isBlocked,
                    onTap: isBlocked
                        ? null
                        : () async {
                            Navigator.pop(context);
                            try {
                              await service.connectDeviceToPlc(
                                device.id,
                                plcId,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$plcId connecting…'),
                                    backgroundColor: Colors.orange,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                final msg = e.toString().replaceFirst(
                                  RegExp(r'^Exception:\s*'),
                                  '',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed: $msg'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(
    BuildContext context,
    PLCBluetoothService service,
    ScannedDevice device,
  ) {
    final controller = TextEditingController(
      text: service.getDisplayName(device.id),
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Custom name',
            hintText: device.name,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                service.setCustomDeviceName(device.id, name);
              }
              Navigator.pop(context);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }
}
