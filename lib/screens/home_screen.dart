import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:rev4_quadikran_monitoring/models/plc_data.dart';
import 'package:rev4_quadikran_monitoring/widgets/plc_block.dart';
import 'package:rev4_quadikran_monitoring/screens/settings_screen.dart';
import 'package:rev4_quadikran_monitoring/widgets/device_list_drawer.dart';
import 'package:rev4_quadikran_monitoring/screens/plc_details_screen.dart';
import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';
import 'package:rev4_quadikran_monitoring/services/emergency_alert_service.dart';

const _kPrimaryCyan = Color(0xFF06B6D4);
const _kPrimaryBlue = Color(0xFF3B82F6);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
// const _kSlate950 = Color(0xFF020617);
const _kSlate900 = Color(0xFF0F172A);
const _kSlate800 = Color(0xFF1E293B);
const _kSlate700 = Color(0xFF334155);
const _kSlate600 = Color(0xFF475569);
const _kSlate500 = Color(0xFF64748B);
const _kSlate400 = Color(0xFF94A3B8);
const _kSlate300 = Color(0xFFCBD5E1);
const _kSlate200 = Color(0xFFE2E8F0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final List<Map<String, String>> plcs = const [
    {'id': 'PLC1', 'name': ' Crane A'},
    {'id': 'PLC2', 'name': ' Crane B'},
    {'id': 'PLC3', 'name': ' Crane C'},
    {'id': 'PLC4', 'name': ' Crane D'},
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<BleEvent>? _bleEventSub;
  StreamSubscription<User?>? _authStateSub;
  Timer? _authCheckTimer;

  late AnimationController _gradientController;

  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  String _filterCriteria = 'name';
  String _rssiPreset = 'any';

  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _subscribeToBleEvents();
    _subscribeToAuthState();
    _startAuthCheckTimer();
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestNotificationPermission(),
    );
  }

  @override
  void dispose() {
    _bleEventSub?.cancel();
    _authStateSub?.cancel();
    _authCheckTimer?.cancel();
    _gradientController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Auth & Session Management ---------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///

  void _subscribeToAuthState() {
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        _forceLogout();
        debugPrint('User signed out, redirecting to login screen.');
      }
    });
  }

  void _startAuthCheckTimer() {
    _authCheckTimer = Timer.periodic(const Duration(milliseconds: 10000), (
      _,
    ) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      try {
        await user.reload();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-disabled' || e.code == 'user-not-found') {
          await FirebaseAuth.instance.signOut();
          if (mounted) _forceLogout();
        }
      } catch (_) {}
    });
  }

  Future<void> _forceLogout() async {
    _authCheckTimer?.cancel();

    if (mounted) {
      _logoutHandler();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
    _showBleSnackBar(
      message:
          'The Administrator may have denied your access or removed your account',
      background: Colors.redAccent,
      gravity: ToastGravity.TOP,
    );
  }

  void _logoutHandler() async {
    final service = Provider.of<PLCBluetoothService>(context, listen: false);
    await service.stopScanning();
    await service.disconnectAllPlcs();
    await FlutterForegroundTask.stopService();
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- BLE Event Management ---------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///

  void _subscribeToBleEvents() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = Provider.of<PLCBluetoothService>(context, listen: false);
      _bleEventSub = service.bleEvents.listen(_onBleEvent);
    });
  }

  void _onBleEvent(BleEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case BleEventType.disconnected:
        _showBleSnackBar(
          message:
              '${event.plcId} disconnected (${event.deviceName}). Reconnecting…',
          background: _kRed,
          duration: const Duration(seconds: 4),
        );
        break;
      case BleEventType.connectionFailed:
        final msg =
            event.error?.replaceFirst(RegExp(r'^Exception:\s*'), '') ??
            'Unknown error';
        _showBleSnackBar(
          message: 'Failed to connect ${event.plcId}: $msg',
          background: _kRed,
          duration: const Duration(seconds: 5),
        );
        break;
      case BleEventType.connectionCancelled:
        _showBleSnackBar(
          message: '${event.plcId} connection cancelled',
          background: _kAmber,
          duration: const Duration(seconds: 2),
        );
        break;
      case BleEventType.connected:
        if (event.isAutoReconnect) {
          _showBleSnackBar(
            message: '${event.plcId} auto-reconnected to ${event.deviceName}',
            background: _kEmerald,
          );
        }
        break;
      case BleEventType.reconnecting:
        _showBleSnackBar(
          message:
              '${event.plcId}: Reconnecting (${event.reconnectAttempt ?? 1}/${event.maxAttempts ?? 5})…',
          background: _kAmber,
          duration: const Duration(seconds: 3),
        );
        break;
      case BleEventType.unstableConnection:
        _showBleSnackBar(
          message: '${event.plcId} (${event.deviceName}): Unstable connection',
          background: _kRed,
          duration: const Duration(seconds: 5),
        );
        break;
      case BleEventType.poorSignal:
        _showBleSnackBar(
          message: '${event.plcId}: Poor signal (${event.rssi ?? 'N/A'} dBm)',
          background: _kAmber,
          duration: const Duration(seconds: 3),
        );
        break;
      case BleEventType.cccdRegistrationFailed:
        _showBleSnackBar(
          message:
              '${event.plcId}: Failed to register for notifications. Data updates may not work.',
          background: _kRed,
          duration: const Duration(seconds: 5),
        );
        break;
    }
  }

  void _showBleSnackBar({
    required String message,
    required Color background,

    ToastGravity gravity = ToastGravity.SNACKBAR,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: message,
      toastLength: duration.inSeconds <= 2
          ? Toast.LENGTH_SHORT
          : Toast.LENGTH_LONG,
      gravity: gravity,
      backgroundColor: background,
      textColor: Colors.white,
      fontSize: 14.0,
      webShowClose: true,
      webPosition: 'right',
    );
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Permissions and Scanning--------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  Future<void> _requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && mounted) {
        await Permission.notification.request();
      }
    } on PlatformException catch (e) {
      debugPrint('Notification permission request skipped: ${e.message}');
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    final List<Permission> required = Platform.isAndroid
        ? [
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.locationWhenInUse,
          ]
        : [Permission.bluetooth, Permission.locationWhenInUse];

    final Map<Permission, PermissionStatus> statuses = {};
    for (final p in required) {
      statuses[p] = await p.status;
    }

    final denied = required.where((p) => !statuses[p]!.isGranted).toList();

    if (denied.isEmpty) return true;

    // Request only denied ones
    final results = await denied.request();

    final permanentlyDenied = results.entries
        .where((e) => e.value.isPermanentlyDenied)
        .map((e) => e.key)
        .toList();

    if (permanentlyDenied.isNotEmpty && mounted) {
      final names = permanentlyDenied
          .map((p) {
            if (p == Permission.bluetoothScan) return 'Nearby devices';
            if (p == Permission.bluetoothConnect) return 'Nearby devices';
            if (p == Permission.bluetooth) return 'Bluetooth';
            if (p == Permission.locationWhenInUse) return 'Location';
            return p.toString();
          })
          .toSet()
          .join(', ');

      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kSlate800,
          title: const Text(
            'Permissions Required',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white),
          ),
          content: Text(
            '$names permission(s) are permanently denied.\nPlease enable them in app settings to use Bluetooth scanning.',
            style: const TextStyle(fontFamily: 'Inter', color: _kSlate400),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'CANCEL',
                style: TextStyle(fontFamily: 'Inter', color: _kSlate400),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await openAppSettings();
              },
              style: TextButton.styleFrom(foregroundColor: _kPrimaryCyan),
              child: const Text(
                'OPEN SETTINGS',
                style: TextStyle(fontFamily: 'Inter'),
              ),
            ),
          ],
        ),
      );
      return false;
    }
    return results.values.every((s) => s.isGranted);
  }

  // Scanning
  Future<void> _handleScanButton(PLCBluetoothService service) async {
    if (service.isScanning) {
      service.stopScanning();
      setState(() => _lastScanTime = DateTime.now());
      _showBleSnackBar(
        message: 'Scanning stopped',
        background: Colors.black38,
        duration: const Duration(seconds: 1),
      );
    } else {
      final granted = await _checkAndRequestPermissions();
      if (!granted) return;
      service.startScanning();
      _showBleSnackBar(
        message: service.isBluetoothOn
            ? 'Scanning for devices...'
            : 'Bluetooth is off. Please turn it on.',
        background: Colors.black38,
        duration: const Duration(seconds: 2),
      );
    }
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Helpers and Formatters--------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///

  int _getSignalStrength(int rssi) {
    if (rssi >= -60) return 100;
    if (rssi >= -70) return 75;
    if (rssi >= -80) return 50;
    if (rssi >= -90) return 25;
    return 0;
  }

  String _getLastScanTime(PLCBluetoothService service) {
    if (service.isScanning) return 'scanning…';
    if (_lastScanTime == null) return 'never';
    return _formatTimeAgo(_lastScanTime!);
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDeviceId(String id) {
    if (id.length > 17) return '${id.substring(0, 17)}...';
    return id;
  }

  List<String> _getActiveErrors(PLCData? data) {
    if (data == null) return [];
    final errors = <String>[];
    if (data.dataStopped1Sec) errors.add('Data stopped (>1 sec)');
    if (data.errorCommWithC1) errors.add('Communication error with Crane 1');
    if (data.errorCommWithC2) errors.add('Communication error with Crane 2');
    if (data.errorCommWithC3) errors.add('Communication error with Crane 3');
    if (data.errorCommWithC4) errors.add('Communication error with Crane 4');
    if (data.datNotFound) errors.add('DAT not found');
    if (data.remoteDAT1) errors.add('Remote DAT not found (Node 1)');
    if (data.remoteDAT2) errors.add('Remote DAT not found (Node 2)');
    if (data.remoteDAT3) errors.add('Remote DAT not found (Node 3)');
    if (data.remoteDAT4) errors.add('Remote DAT not found (Node 4)');
    if (data.zeroDistanceMeasured) errors.add('Zero distance measured');
    return errors;
  }

  (String, Color) _getRssiInfo(int rssi) {
    if (rssi >= -60) return ('Strong', _kEmerald);
    if (rssi >= -75) return ('Good', Colors.lightGreen);
    if (rssi >= -85) return ('Fair', _kAmber);
    return ('Weak', _kRed);
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Filter Logic --------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  bool get _isFilterActive =>
      (_filterCriteria == 'name' && _filterQuery.isNotEmpty) ||
      (_filterCriteria == 'rssi' && _rssiPreset != 'any') ||
      _filterCriteria == 'known';

  String _filterCriteriaLabel() {
    return switch (_filterCriteria) {
      'name' => 'Name${_filterQuery.isNotEmpty ? ' "$_filterQuery"' : ''}',
      'rssi' => 'Signal • $_rssiPreset',
      'known' => 'Known PLC only',
      _ => _filterCriteria,
    };
  }

  List<ScannedDevice> _applyFilter(List<ScannedDevice> devices) {
    switch (_filterCriteria) {
      case 'name':
        if (_filterQuery.isEmpty) return devices;
        final q = _filterQuery.toLowerCase();
        return devices
            .where(
              (d) =>
                  d.displayName.toLowerCase().contains(q) ||
                  d.id.toLowerCase().contains(q),
            )
            .toList();
      case 'rssi':
        final minRssi = switch (_rssiPreset) {
          'strong' => -60,
          'good' => -75,
          'fair' => -85,
          _ => -999,
        };
        return devices.where((d) => d.rssi >= minRssi).toList();
      case 'known':
        const knownPrefix = '6e410001';
        return devices
            .where(
              (d) => d.advertisementData.serviceUuids.any(
                (u) => u.toString().toLowerCase().startsWith(knownPrefix),
              ),
            )
            .toList();
      default:
        return devices;
    }
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!---------------------------Build Method --------------------------------------------->
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(),
      drawer: _buildFilterDrawer(),
      endDrawer: DeviceListDrawer(applyFilter: _applyFilter),
      body: Consumer<PLCBluetoothService>(
        builder: (context, service, child) {
          return RefreshIndicator(
            color: _kPrimaryCyan,
            backgroundColor: const Color(0xFF1E293B),
            onRefresh: () async {
              if (!service.isScanning) {
                final granted = await _checkAndRequestPermissions();
                if (granted) service.startScanning();
              }
              await Future.delayed(const Duration(seconds: 2));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeaderSection(service)),
                SliverToBoxAdapter(child: _buildStatsCards(service)),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: _buildDeviceStatusSection(service),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(height: 12),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              "CONNECTION BLOCKS",
                              style: TextStyle(
                                fontFamily: 'Rajdhani',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _kSlate400,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                          bottom: 16,
                        ),

                        child: Text(
                          'Tap on a connected PLC block from the grid below to view detailed diagnostics, load data, and historical trends for that specific Crane.',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 11,
                            color: _kSlate600,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ],
                  ),
                ),

                _buildPlcGridSliver(service),

                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Build-Scaffold --------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: AnimatedBuilder(
        animation: _gradientController,
        builder: (context, child) {
          final t = _gradientController.value;
          final colors = [
            Color.lerp(Colors.white, const Color(0xFFF39C12), t)!,
            Colors.white,
            Color.lerp(Colors.white, const Color(0xFFF39C12), t)!,
            Colors.white,
            Color.lerp(Colors.white, const Color(0xFFF39C12), t)!,
          ];
          final logoScale = 0.8 + (t * 0.2);

          return Row(
            children: [
              Transform.scale(
                scale: logoScale,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF39C12), Color(0xFFFFBF47)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF39C12).withAlpha(102),
                        blurRadius: 12 + (t * 4),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.sensors_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Text(
                      'QuadiKran Connect',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withAlpha(128),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Live Monitoring',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 8,
                          color: Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),

      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF030B1F), Color(0xFF0B2C5D), Color(0xFF1F3F7A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),

      centerTitle: false,
      // toolbarHeight: 65,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      leadingWidth: 48,
      primary: true,

      foregroundColor: Colors.white,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: const Icon(Icons.menu_sharp),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            tooltip: 'Device Filters',
            autofocus: false,
          ),
          if (_isFilterActive)
            Positioned(
              right: 8,
              top: 10,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFF39C12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      actions: [
        Consumer<PLCBluetoothService>(
          builder: (context, service, child) {
            final available = service.availableDevices;
            final availableCount = _applyFilter(available).length;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  tooltip: 'Available Devices',
                  enableFeedback: true,
                ),
                if (availableCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$availableCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  //Header Section
  Widget _buildHeaderSection(PLCBluetoothService service) {
    return Container(
      padding: const EdgeInsets.all(20),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome back,',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 14,
              color: Colors.black,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_kPrimaryCyan, _kPrimaryBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              FirebaseAuth.instance.currentUser?.email?.split('@').first ??
                  'Operator',
              style: const TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Monitor crane positions, diagnostics, and load data\nin real-time across all connected PLCs.',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 12,
              color: _kSlate600,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // Stats Cards Section
  Widget _buildStatsCards(PLCBluetoothService service) {
    final connectedCount = service.connectedDevices().length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              background: const Color(0xFF0B2C5D),
              title: 'CONNECTED',
              value: '$connectedCount/4',
              subtitle: 'Active PLCs',
              icon: Icons.link,
              color: _kEmerald,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              background: const Color(0xFF0B2C5D),
              title: 'BLE STATUS',
              value: service.isBluetoothOn ? 'ACTIVE' : 'OFF',
              subtitle: service.isScanning ? 'Scanning...' : 'Ready',
              icon: service.isScanning
                  ? Icons.bluetooth_searching
                  : Icons.bluetooth,
              color: service.isBluetoothOn ? _kPrimaryCyan : _kSlate300,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () async => _handleScanButton(service),
              child: _buildStatCard(
                background: service.isScanning
                    ? const Color.fromARGB(255, 189, 121, 3)
                    : const Color(0xFF0B2C5D),
                title: 'SCAN',
                value: service.isScanning ? 'STOP' : 'START',
                subtitle: 'Find devices',
                icon: service.isScanning
                    ? Icons.stop
                    : Icons.bluetooth_searching,
                color: _kAmber,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Individual Stat Card
  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: background == const Color.fromARGB(255, 189, 121, 3)
                ? const Color.fromARGB(255, 255, 255, 255)
                : color,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 9,
              color: _kSlate200,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 10,
              color: color.withAlpha(255),
            ),
          ),
        ],
      ),
    );
  }

  // Device Status Section
  Widget _buildDeviceStatusSection(PLCBluetoothService service) {
    final connectedCount = service.connectedDevices().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'DEVICE STATUS',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _kSlate400,
                letterSpacing: 1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kPrimaryCyan.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: service.isBluetoothOn ? _kEmerald : _kSlate600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    service.isBluetoothOn ? 'BLE Active' : 'BLE Off',
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 9,
                      color: Color.fromARGB(255, 9, 110, 128),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2,
          children: plcs.map((plc) {
            final plcId = plc['id']!;
            final craneName = plc['name']!.trim();
            final connectedDevice = service.getDeviceForPlc(plcId);
            final isConnected = connectedDevice != null;
            final isConnecting = service.isConnecting(plcId);
            final isReconnecting = service.isReconnecting(plcId);
            final rssi = connectedDevice?.rssi ?? -100;

            return _buildDeviceStatusCard(
              plcId: plcId,
              craneName: craneName,
              isConnected: isConnected,
              isConnecting: isConnecting,
              isReconnecting: isReconnecting,
              deviceName: connectedDevice?.displayName,
              rssi: rssi,
              plcData: service.plcDataMap[plcId],
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '$connectedCount / 4 devices connected',
              style: const TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 10,
                color: _kSlate600,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: _kSlate600,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                const Icon(Icons.access_time, size: 10, color: _kSlate600),
                const SizedBox(width: 4),
                Text(
                  'Last scan: ${_getLastScanTime(service)}',
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 10,
                    color: _kSlate600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Individual Device Status Card
  Widget _buildDeviceStatusCard({
    required String plcId,
    required String craneName,
    required bool isConnected,
    required bool isConnecting,
    required bool isReconnecting,
    required String? deviceName,
    required int rssi,
    PLCData? plcData,
  }) {
    final Color statusColor;
    final String statusLabel;

    if (isConnected) {
      statusColor = _kEmerald;
      statusLabel = 'ONLINE';
    } else if (isConnecting) {
      statusColor = _kAmber;
      statusLabel = 'CONNECTING';
    } else if (isReconnecting) {
      statusColor = _kAmber;
      statusLabel = 'RECONNECTING';
    } else {
      statusColor = _kRed;
      statusLabel = 'OFFLINE';
    }

    final signalStrength = _getSignalStrength(rssi);
    final activeErrors = _getActiveErrors(plcData);
    final hasError = activeErrors.isNotEmpty;

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasError ? _kAmber.withAlpha(180) : statusColor.withAlpha(60),
          width: hasError ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: statusColor.withAlpha(120),
                        blurRadius: 5,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (hasError) ...[
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: _kAmber,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      craneName,
                      style: const TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (isConnected)
                  Row(
                    children: [
                      _buildSignalBars(signalStrength),
                      const SizedBox(width: 5),
                      Text(
                        '$rssi dBm',
                        style: const TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 8,
                          color: _kSlate600,
                        ),
                      ),
                    ],
                  )
                else if (isConnecting || isReconnecting)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: statusColor,
                    ),
                  )
                else
                  const Text(
                    '—————',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 10,
                      color: _kSlate900,
                    ),
                  ),
              ],
            ),
          ),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (hasError) ...[
                const SizedBox(height: 3),
                const Text(
                  'Tap for details',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 7,
                    color: _kAmber,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (hasError) {
      return GestureDetector(
        onTap: () => _showErrorDetailsDialog(plcId, craneName, activeErrors),
        child: card,
      );
    }
    return card;
  }

  // Signal Strength Bars
  Widget _buildSignalBars(int strength) {
    return Row(
      children: List.generate(4, (index) {
        final threshold = (index + 1) * 25;
        final isActive = strength >= threshold;
        final height = 6 + index * 2;
        return Container(
          width: 3,
          height: height.toDouble(),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: isActive ? _kPrimaryCyan : _kSlate600,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  // PLC Grid Section
  Widget _buildPlcGridSliver(PLCBluetoothService service) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
          childAspectRatio: 0.6,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final plc = plcs[index];
          final plcId = plc['id']!;
          final connectedDevice = service.getDeviceForPlc(plcId);
          final connectionStatus = service.isReconnecting(plcId)
              ? ConnectionStatus.reconnecting
              : service.isConnecting(plcId)
              ? ConnectionStatus.connecting
              : service.isDisconnecting(plcId)
              ? ConnectionStatus.disconnecting
              : connectedDevice != null
              ? ConnectionStatus.connected
              : ConnectionStatus.disconnected;
          final displayName = connectedDevice != null
              ? service.getDisplayName(connectedDevice.id)
              : null;

          return Selector<EmergencyAlertService, bool>(
            selector: (_, alertSvc) => alertSvc.activeRelays.contains(plcId),
            builder: (context, isInEmergency, _) =>
                Selector<PLCBluetoothService, PLCData?>(
                  selector: (_, svc) => svc.plcDataMap[plcId],
                  builder: (context, plcData, _) => PLCBlock(
                    key: ValueKey('plc_$plcId'),
                    plcId: plcId,
                    plcData: plcData,
                    isInEmergency: isInEmergency,
                    connectedDeviceName: displayName,
                    connectingDeviceName: service.getConnectingDeviceName(
                      plcId,
                    ),
                    connectionState: connectionStatus,
                    reconnectAttempt: service.getReconnectAttempt(plcId),
                    connectedDeviceId: connectedDevice?.id,
                    rssi: connectedDevice?.rssi,
                    characteristicCount: service
                        .getPlcService(plcId)
                        ?.characteristics
                        .length,
                    onTap: () {
                      if (connectedDevice != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PLCDetailScreen(plcId: plcId),
                          ),
                        );
                      } else if (!service.isConnecting(plcId) &&
                          !service.isDisconnecting(plcId)) {
                        if (service.availableDevices.isEmpty) {
                          _showBleSnackBar(
                            message: 'No available devices. Start scan first.',
                            background: _kSlate600,
                          );
                        } else {
                          _showDeviceSelectionDialog(plcId);
                        }
                      }
                    },
                    onConnectPressed: () {
                      if (service.availableDevices.isEmpty) {
                        _showBleSnackBar(
                          message: 'No available devices. Start scan first.',
                          background: _kRed,
                        );
                      } else {
                        _showDeviceSelectionDialog(plcId);
                      }
                    },
                    onDisconnectPressed: () => _confirmDisconnect(plcId),
                    onCancelConnection: () =>
                        service.cancelConnectionAttempt(plcId),
                    plcName: displayName ?? 'Not Connected',
                  ),
                ),
          );
        }, childCount: plcs.length),
      ),
    );
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Error Details Dialog --------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///

  void _showErrorDetailsDialog(
    String plcId,
    String craneName,
    List<String> errors,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSlate800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _kAmber, width: 1),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _kAmber, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ERROR DETAILS',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kAmber,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    '$plcId — $craneName',
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 12,
                      color: _kSlate400,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: _kSlate700, height: 12),
            ...errors.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.circle, size: 6, color: _kAmber),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e,
                        style: const TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 13,
                          color: _kSlate200,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: _kPrimaryCyan,
              backgroundColor: _kPrimaryCyan.withAlpha(25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            ),
            child: const Text(
              'OK',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Build-Device Selection Dialog --------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///

  void _showDeviceSelectionDialog(String plcId) {
    final service = Provider.of<PLCBluetoothService>(context, listen: false);
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (BuildContext dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isTablet ? screenSize.width * 0.2 : 24,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(26),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDialogHeader(plcId, service),

                      // Content
                      _buildDialogContent(service, plcId, dialogContext),

                      // Footer
                      _buildDialogFooter(dialogContext),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // Header
  Widget _buildDialogHeader(String plcId, PLCBluetoothService service) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade700, Colors.blue.shade500],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bluetooth_searching,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect to $plcId',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select a Bluetooth device to pair',
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(26),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: service.isScanning ? Colors.green : Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (service.isScanning ? Colors.green : Colors.orange)
                                .withAlpha(128),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  service.isScanning
                      ? 'Scanning for devices...'
                      : '${service.scannedDevices.length} devices found',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Content
  Widget _buildDialogContent(
    PLCBluetoothService service,
    String plcId,
    BuildContext dialogContext,
  ) {
    final allDevices = service.availableDevices;
    final devices = _applyFilter(allDevices);
    if (allDevices.isEmpty) {
      return _buildEmptyState(service, dialogContext);
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(dialogContext).size.height * 0.5,
        maxWidth: MediaQuery.of(dialogContext).size.width * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Available Devices',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (_isFilterActive) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.filter_alt,
                    size: 13,
                    color: Colors.orange.shade600,
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _isFilterActive
                        ? Colors.orange.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isFilterActive
                          ? Colors.orange.shade200
                          : Colors.blue.shade200,
                    ),
                  ),
                  child: Text(
                    _isFilterActive
                        ? '${devices.length}/${allDevices.length}'
                        : '${devices.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _isFilterActive
                          ? Colors.orange.shade700
                          : Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 40, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No devices match the current filter.\nOpen the \u2630 menu to adjust filters.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                key: const PageStorageKey('device_list'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: devices.length,

                itemBuilder: (context, index) {
                  if (index >= devices.length) {
                    return const SizedBox.shrink();
                  }
                  final device = devices[index];
                  if (device.displayName.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _buildDeviceTile(
                    device,
                    plcId,
                    service,
                    dialogContext,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDialogFooter(BuildContext dialogContext) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'CANCEL',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(
    ScannedDevice device,
    String plcId,
    PLCBluetoothService service,
    BuildContext dialogContext,
  ) {
    final rssiInfo = _getRssiInfo(device.rssi);
    final isConnecting =
        service.isConnecting(plcId) &&
        service.getConnectingDeviceName(plcId) == device.displayName;
    // final screenWidth = MediaQuery.of(dialogContext).size.width;

    return Container(
      key: ValueKey(device.id),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

        title: Text(
          device.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(Icons.code, size: 10, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _formatDeviceId(device.id),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 120,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: rssiInfo.$2.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.signal_cellular_alt,
                      size: 10,
                      color: rssiInfo.$2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              //
              if (isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                ElevatedButton(
                  onPressed: () =>
                      _connectToDevice(device, plcId, service, dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(60, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Connect',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Empty State
  Widget _buildEmptyState(
    PLCBluetoothService service,
    BuildContext dialogContext,
  ) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _kSlate700.withAlpha(128),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bluetooth_searching,
              size: 48,
              color: _kSlate500,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Devices Found',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            service.isScanning
                ? 'Scanning for nearby Bluetooth devices...'
                : 'Make sure your device is discoverable and try scanning again.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 14,
              color: _kSlate400,
            ),
          ),
          const SizedBox(height: 24),
          if (!service.isScanning)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                service.startScanning();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryCyan,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Connect to Device
  Future<void> _connectToDevice(
    ScannedDevice device,
    String plcId,
    PLCBluetoothService service,
    BuildContext dialogContext,
  ) async {
    Navigator.pop(dialogContext);
    _showBleSnackBar(
      message: 'Connecting $plcId to ${device.displayName}…',
      background: _kPrimaryBlue,

      duration: const Duration(seconds: 3),
    );

    try {
      await service.connectDeviceToPlc(device.id, plcId);
      // Only show the success snackbar if the PLC slot is actually connected.

      if (mounted && service.connectedDevices().containsKey(plcId)) {
        _showBleSnackBar(
          message: '$plcId connected to ${device.displayName}',
          background: _kEmerald,
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst(
          RegExp(r'^Exception:\s*|^Error:\s*'),
          '',
        );
        _showBleSnackBar(
          message: 'Failed to connect $plcId: $msg',
          background: _kRed,

          duration: const Duration(seconds: 5),
        );
      }
    }
  }

  // Confirm Disconnect
  void _confirmDisconnect(String plcId) {
    final service = Provider.of<PLCBluetoothService>(context, listen: false);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _kSlate800,
          title: Text(
            'Disconnect $plcId?',
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            'Are you sure you want to disconnect $plcId?',
            style: const TextStyle(color: _kSlate400),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: _kSlate400)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await service.disconnectPlc(plcId);
                if (mounted) {
                  _showBleSnackBar(
                    message: '$plcId disconnected',
                    background: _kRed,
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: _kRed),
              child: const Text('DISCONNECT'),
            ),
          ],
        );
      },
    );
  }

  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  /// <!--------------------------- Build-Filter Drawer--------------------------------------------->
  ///────────────────────────────────────────────────────────────────────────────────────────────────────────────────///
  Widget _buildFilterDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 48, 12, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color.fromARGB(255, 7, 50, 242), _kSlate800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isFilterActive
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  color: _isFilterActive ? _kAmber : _kSlate400,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Device Filters',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isFilterActive)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _filterQuery = '';
                      _filterController.clear();
                      _filterCriteria = 'name';
                      _rssiPreset = 'any';
                    }),
                    icon: const Icon(Icons.clear_all, size: 15, color: _kAmber),
                    label: const Text(
                      'Clear',
                      style: TextStyle(color: _kAmber, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isFilterActive)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _kAmber.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kAmber.withAlpha(77)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.filter_alt,
                            size: 14,
                            color: _kAmber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Active: ${_filterCriteriaLabel()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _kAmber,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'FILTER BY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: _kSlate500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _filterDrawerTile(
                    label: 'Device Name / MAC',
                    icon: Icons.text_fields_rounded,
                    value: 'name',
                    color: _kPrimaryCyan,
                  ),
                  _filterDrawerTile(
                    label: 'Signal Strength (RSSI)',
                    icon: Icons.signal_cellular_alt,
                    value: 'rssi',
                    color: _kEmerald,
                  ),
                  _filterDrawerTile(
                    label: 'Known PLC Devices Only',
                    icon: Icons.verified,
                    value: 'known',
                    color: _kAmber,
                  ),
                  const Divider(
                    indent: 16,
                    endIndent: 16,
                    height: 24,
                    color: _kSlate700,
                  ),
                  if (_filterCriteria == 'name')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _filterController,
                        onChanged: (v) => setState(() => _filterQuery = v),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search by name or MAC…',
                          hintStyle: TextStyle(
                            color: Colors.white70.withAlpha(222),
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: _kSlate400,
                          ),
                          suffixIcon: _filterQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: _kSlate400,
                                    size: 18,
                                  ),
                                  onPressed: () => setState(() {
                                    _filterQuery = '';
                                    _filterController.clear();
                                  }),
                                )
                              : null,
                          filled: true,
                          fillColor: _kSlate800,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _kPrimaryCyan,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_filterCriteria == 'rssi') ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Signal threshold',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kSlate400,
                        ),
                      ),
                    ),
                    for (final preset in ['any', 'fair', 'good', 'strong'])
                      _rssiPresetTile(preset),
                  ],
                  if (_filterCriteria == 'known')
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Shows only devices that advertise the app\'s PLC service UUID.',
                        style: TextStyle(fontSize: 12, color: _kSlate500),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(
            indent: 16,
            endIndent: 16,
            height: 1,
            color: _kSlate700,
          ),
          const SizedBox(height: 8),
          ListTile(
            minTileHeight: 5,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 0,
            ),
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _kSlate800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.settings_outlined,
                color: _kSlate400,
                size: 20,
              ),
            ),
            title: const Text(
              'Settings',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 0,
            ),
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _kRed.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout, color: _kRed, size: 20),
            ),
            title: const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.w600, color: _kRed),
            ),
            onTap: () async {
              final currentContext = context;
              Navigator.pop(currentContext);
              final confirm = await showDialog<bool>(
                context: currentContext,
                builder: (ctx) => AlertDialog(
                  backgroundColor: _kSlate800,
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: const Text(
                    'Are you sure you want to logout?',
                    style: TextStyle(color: _kSlate400),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: _kSlate400),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _logoutHandler();
                        Navigator.pop(ctx, true);
                      },
                      child: const Text(
                        'Logout',
                        style: TextStyle(color: _kRed),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true && currentContext.mounted) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isLoggedIn', false);
                if (!currentContext.mounted) return;
                final bleService = Provider.of<PLCBluetoothService>(
                  currentContext,
                  listen: false,
                );
                await bleService.disconnectAllPlcs();
                await FlutterForegroundTask.stopService();
                if (currentContext.mounted) {
                  Navigator.pushReplacementNamed(currentContext, '/login');
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // tiles for dynamic styling based on selection
  Widget _filterDrawerTile({
    required String label,
    required IconData icon,
    required String value,
    required Color color,
  }) {
    final selected = _filterCriteria == value;
    return InkWell(
      onTap: () => setState(() {
        _filterCriteria = value;
        if (value != 'name') {
          _filterQuery = '';
          _filterController.clear();
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        color: selected ? color.withAlpha(26) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? color.withAlpha(51) : _kSlate800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? color : Colors.white70,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: Colors.black87.withAlpha(selected ? 222 : 150),
                ),
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? color : _kSlate600,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rssiPresetTile(String preset) {
    final (label, color) = switch (preset) {
      'fair' => ('Fair (≥ -85 dBm)', _kAmber),
      'good' => ('Good (≥ -75 dBm)', Colors.lightGreen),
      'strong' => ('Strong (≥ -60 dBm)', _kEmerald),
      _ => ('Any signal', _kSlate500),
    };
    final selected = _rssiPreset == preset;
    return InkWell(
      onTap: () => setState(() => _rssiPreset = preset),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: 50),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? Colors.black87.withAlpha(222)
                      : Colors.black87.withAlpha(150),
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 16, color: _kEmerald),
          ],
        ),
      ),
    );
  }
}

// GridPainter for background (optional)
// class GridPainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = _kPrimaryCyan.withAlpha(8)
//       ..strokeWidth = 0.5
//       ..style = PaintingStyle.stroke;
//     const spacing = 48.0;
//     for (double x = 0; x < size.width; x += spacing) {
//       canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
//     }
//     for (double y = 0; y < size.height; y += spacing) {
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }
