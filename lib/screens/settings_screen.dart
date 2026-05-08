import 'dart:io';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _batteryIgnored = false;
  bool _loadingBattery = true;

  static const Color _navy = Color(0xFF0B2C5D);
  static const Color _amber = Color(0xFFF39C12);

  @override
  void initState() {
    super.initState();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    final service = context.read<PLCBluetoothService>();
    final ignored = await service.isBatteryOptimizationIgnored;
    if (mounted) {
      setState(() {
        _batteryIgnored = ignored;
        _loadingBattery = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
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
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
        ),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: Consumer<PLCBluetoothService>(
        builder: (context, service, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              const _SectionHeader('Notification'),
              _SettingsCard(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        color: service.notificationEnabled
                            ? _navy.withAlpha(25)
                            : Colors.grey.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.notifications_active_outlined,
                        color: service.notificationEnabled
                            ? _navy
                            : Colors.grey,
                        size: 22,
                      ),
                    ),
                    title: const Text(
                      'Persistent BLE Notification',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Show a status notification for all 4 PLCs while '
                      'connections are active. Keeps the service alive '
                      'when the app is backgrounded or killed.',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Rajdhani',
                        color: Colors.grey.shade600,
                      ),
                    ),
                    value: service.notificationEnabled,
                    activeThumbColor: _amber,
                    onChanged: (v) => service.setNotificationEnabled(v),
                  ),
                ],
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 8),
                const _SectionHeader('Boot Behaviour'),
                _SettingsCard(
                  children: [
                    SwitchListTile(
                      secondary: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: service.autoStartOnBoot
                              ? _navy.withAlpha(25)
                              : Colors.grey.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.restart_alt_rounded,
                          color: service.autoStartOnBoot ? _navy : Colors.grey,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Auto-start on Device Boot',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Automatically restart the background BLE service '
                        'after the device reboots so monitoring resumes '
                        'without opening the app.',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      value: service.autoStartOnBoot,
                      activeThumbColor: _amber,
                      onChanged: service.notificationEnabled
                          ? (v) => service.setAutoStartOnBoot(v)
                          : null,
                    ),
                    if (!service.notificationEnabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                        child: Text(
                          'Enable the persistent notification to use this option.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const _SectionHeader('Battery'),
                _SettingsCard(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: _batteryIgnored
                              ? Colors.green.withAlpha(25)
                              : Colors.orange.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _loadingBattery
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _batteryIgnored
                                    ? Icons.battery_charging_full_rounded
                                    : Icons.battery_alert_rounded,
                                color: _batteryIgnored
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                                size: 22,
                              ),
                      ),
                      title: const Text(
                        'Ignore Battery Optimisation',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',

                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _loadingBattery
                            ? 'Checking…'
                            : _batteryIgnored
                            ? 'Already exempted — BLE service will not be throttled.'
                            : 'Battery optimisation may kill the BLE service during '
                                  'extended monitoring. Tap to request exemption.',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 10,
                          color: _batteryIgnored
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                        ),
                      ),
                      trailing: _batteryIgnored
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green.shade600,
                            )
                          : TextButton(
                              onPressed: _loadingBattery
                                  ? null
                                  : () async {
                                      await service
                                          .requestBatteryOptimization();
                                      await _checkBatteryOptimization();
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: _amber,
                              ),
                              child: const Text('Exempt'),
                            ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              const _SectionHeader('About'),
              _SettingsCard(
                children: [
                  ListTile(
                    leading: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        color: _navy.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: _navy,
                        size: 22,
                      ),
                    ),
                    title: const Text(
                      'Notification Icons',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '● Connected  ◌ Connecting  ○ Disconnected\n',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
