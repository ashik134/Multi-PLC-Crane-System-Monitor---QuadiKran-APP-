import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutterblue;

import 'package:rev4_quadikran_monitoring/widgets/float_value_widget.dart';
import 'package:rev4_quadikran_monitoring/widgets/boolean_value_widget.dart';
import 'package:rev4_quadikran_monitoring/screens/ble_diagnostic_screen.dart';
import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';



const List<String> _plcIds = ['PLC1', 'PLC2', 'PLC3', 'PLC4'];

// ─── Host screen (tabs + PageView) ────────────────────────────────────────────

/// Entry point pushed from the home screen.  Opens on the tapped PLC and lets
/// the user swipe left/right to visit every PLC without going back.
class PLCDetailScreen extends StatefulWidget {
  final String plcId;

  const PLCDetailScreen({super.key, required this.plcId});

  @override
  State<PLCDetailScreen> createState() => _PLCDetailScreenState();
}

class _PLCDetailScreenState extends State<PLCDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final initialIndex = _plcIds.indexOf(widget.plcId).clamp(0, 3);
    _tabController = TabController(
      length: _plcIds.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _pageController = PageController(initialPage: initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text(
          'QuadiKRAN Connect',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Consumer<PLCBluetoothService>(
            builder: (_, svc, _) => TabBar(
              controller: _tabController,
              onTap: (index) => _pageController.jumpToPage(index),
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: _plcIds.map((id) {
                final state = svc.getConnectionState(id);
                final isConnected =
                    state == flutterblue.BluetoothConnectionState.connected;
                final isConnecting = svc.isConnecting(id);
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusDot(
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                      ),
                      const SizedBox(width: 6),
                      Text(id),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _plcIds.map((id) => _PLCDetailPage(plcId: id)).toList(),
      ),
    );
  }
}

/// Small coloured dot shown in each tab to indicate connection state.
class _StatusDot extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;

  const _StatusDot({required this.isConnected, required this.isConnecting});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (isConnected) {
      color = Colors.greenAccent;
    } else if (isConnecting) {
      color = Colors.amberAccent;
    } else {
      color = Colors.white38;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── Single-PLC detail page ────────────────────────────────────────────────────

class _PLCDetailPage extends StatefulWidget {
  final String plcId;

  const _PLCDetailPage({required this.plcId});

  @override
  State<_PLCDetailPage> createState() => _PLCDetailPageState();
}

class _PLCDetailPageState extends State<_PLCDetailPage>
    with AutomaticKeepAliveClientMixin {
  // Keep page state alive while swiping between tabs.
  @override
  bool get wantKeepAlive => true;

  flutterblue.BluetoothConnectionState _connectionState =
      flutterblue.BluetoothConnectionState.disconnected;
  bool _isConnecting = false;
  bool _hasData = false;
  bool _hasService = false;
  String _deviceId = '';
  String _displayName = 'Unknown';
  List<flutterblue.BluetoothCharacteristic?> _chars = const [];

  // Expansion state for each collapsible section (all start collapsed).
  final Map<String, bool> _expandedSections = {
    'crane': false,
    'diagnostics': false,
    'output': false,
    'load': false,
    'anticollision': true,
  };

  void _toggleSection(String key) {
    setState(() {
      _expandedSections[key] = !(_expandedSections[key] ?? false);
    });
  }

  PLCBluetoothService? _svc;
  StreamSubscription<BleEvent>? _eventSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _svc = context.read<PLCBluetoothService>();
      _svc!.addListener(_onServiceUpdate);
      _eventSub = _svc!.bleEvents
          .where((e) => e.plcId == widget.plcId)
          .listen(_onBleEvent);
      _syncFromService();
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _svc?.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    _syncFromService();
  }

  void _onBleEvent(BleEvent event) {
    if (!mounted) return;
    if (event.type != BleEventType.disconnected) return;
    final isGatt =
        event.error != null &&
        (event.error!.contains('133') ||
            event.error!.toUpperCase().contains('GATT'));

    Fluttertoast.showToast(
      msg: isGatt
          ? 'GATT error 133 — BLE stack failure. Reconnecting…'
          : '${widget.plcId} disconnected. Reconnecting…',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.TOP,
      backgroundColor: isGatt ? Colors.red.shade800 : Colors.orange.shade800,
      textColor: Colors.white,
    );
  }

  /// Reads the latest connection-level state from the service and calls
  /// setState only when something actually changed.  This means the screen
  /// rebuilds only on connect/disconnect/reconnect events, not on every BLE
  /// notification that ticks the service's 50 ms throttle timer.
  void _syncFromService() {
    final svc = _svc;
    if (svc == null) return;
    final newState = svc.getConnectionState(widget.plcId);
    final newConnecting = svc.isConnecting(widget.plcId);
    final newHasData = svc.plcDataMap[widget.plcId] != null;
    final newHasService = svc.getPlcService(widget.plcId) != null;
    final newChars = svc.getCharList(widget.plcId);
    final device = svc.getDeviceForPlc(widget.plcId);
    final newDeviceId = device?.id ?? '';
    final newDisplayName = newDeviceId.isNotEmpty
        ? svc.getDisplayName(newDeviceId)
        : 'Unknown';

    if (newState != _connectionState ||
        newConnecting != _isConnecting ||
        newHasData != _hasData ||
        newHasService != _hasService ||
        newDeviceId != _deviceId ||
        newDisplayName != _displayName ||
        !_charsEqual(newChars)) {
      setState(() {
        _connectionState = newState;
        _isConnecting = newConnecting;
        _hasData = newHasData;
        _hasService = newHasService;
        _deviceId = newDeviceId;
        _displayName = newDisplayName;
        _chars = newChars;
      });
    }
  }

  bool _charsEqual(List<flutterblue.BluetoothCharacteristic?> other) {
    if (_chars.length != other.length) return false;
    for (int i = 0; i < _chars.length; i++) {
      if (_chars[i] != other[i]) return false;
    }
    return true;
  }

  flutterblue.BluetoothCharacteristic? _c(int i) {
    final local = (i < _chars.length) ? _chars[i] : null;
    if (local != null) return local;
    return _svc?.getChar(widget.plcId, i);
  }

  Future<void> _refreshAll() async {
    if (_connectionState != flutterblue.BluetoothConnectionState.connected) {
      Fluttertoast.showToast(
        msg: 'Not connected',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
        backgroundColor: Colors.orange.shade800,
        textColor: Colors.white,
      );
      return;
    }

    final reads = <Future<void>>[];
    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < _chars.length; i++) {
      final char = _chars[i];
      if (char == null || !char.properties.read) continue;

      reads.add(
        char
            .read()
            .then((_) {
              debugPrint('Char $i read successful');
              successCount++;
            })
            .catchError((e) {
              failCount++;
              debugPrint('Refresh char $i failed: $e');
            }),
      );
    }

    await Future.wait(reads);

    if (mounted) {
      Fluttertoast.showToast(
        msg: 'Refresh complete: $successCount successful, $failCount failed',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
        backgroundColor: failCount > 0
            ? Colors.orange.shade800
            : Colors.green.shade800,
        textColor: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return Column(
      children: [
        _buildPageHeader(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  // ── Per-page sub-header ────────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return Container(
      color: Colors.blue.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.plcId}  ·  $_displayName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_deviceId.isNotEmpty)
                  Text(
                    _deviceId,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          if (_connectionState ==
              flutterblue.BluetoothConnectionState.connected)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 18),
                      SizedBox(width: 8),
                      Text('Refresh Services'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'diagnostic',
                  child: Row(
                    children: [
                      Icon(
                        Icons.bug_report_outlined,
                        size: 18,
                        color: Colors.indigo,
                      ),
                      SizedBox(width: 8),
                      Text('BLE Diagnostics'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'disconnect',
                  child: Row(
                    children: [
                      Icon(Icons.link_off, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Disconnect', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'disconnect') {
                  _svc?.disconnectPlc(widget.plcId);
                } else if (value == 'refresh') {
                  _refreshAll();
                } else if (value == 'diagnostic') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BleDiagnosticScreen(plcId: widget.plcId),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting to PLC...'),
            SizedBox(height: 8),
            Text(
              'Discovering services...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_connectionState == flutterblue.BluetoothConnectionState.disconnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '${widget.plcId} is disconnected',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Swipe to another PLC or go back to connect',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (!_hasData) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Waiting for data...'),
            SizedBox(height: 8),
            Text(
              'Receiving sensor readings',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return _buildDataView();
  }

  Widget _buildDataView() {
    // final plcService = _svc!.getPlcService(widget.plcId);
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // if (_hasService) ...[
            //   _buildServiceCard(plcService),
            //   const SizedBox(height: 20),
            // ],
            _buildConnectionStatusCard(),
            const SizedBox(height: 20),
            _buildCranePositionsSection(),
            const SizedBox(height: 20),
            _buildDiagnosticsSection(),
            const SizedBox(height: 20),
            _buildOutputPinsSection(),
            const SizedBox(height: 20),
            _buildLoadMonitoringSection(),
            const SizedBox(height: 20),
            _buildAnticollisionSection(),
           
          ],
        ),
      ),
    );
  }

  // ── Section builders ───────────────────────────────────────────────────────

  /// Uses a targeted Selector so only this card rebuilds when the displayed
  /// timestamp string advances (≈ once per second), leaving all other widgets
  /// completely unaffected.
  Widget _buildConnectionStatusCard() {
    return Selector<PLCBluetoothService, String>(
      selector: (_, svc) {
        final ts = svc.plcDataMap[widget.plcId]?.timestamp;
        return ts != null ? _formatTime(ts) : '--:--:--';
      },
      builder: (_, timeStr, _) => Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Connected ',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCranePositionsSection() {
    return _ExpandableSectionCard(
      title: 'Crane Positions (mm)',
      icon: Icons.straighten,
      accentColor: const Color(0xFF1565C0),
      isExpanded: _expandedSections['crane']!,
      onToggle: () => _toggleSection('crane'),
      children: [
        FloatValueWidget(
          label: 'Crane 1 Distance',
          characteristic: _c(15),
          packetIndex: 15,
        ),
        FloatValueWidget(
          label: 'Crane 2 Distance',
          characteristic: _c(16),
          packetIndex: 16,
        ),
        FloatValueWidget(
          label: 'Crane 3 Distance',
          characteristic: _c(17),
          packetIndex: 17,
        ),
        FloatValueWidget(
          label: 'Crane 4 Distance',
          characteristic: _c(18),
          packetIndex: 18,
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    return _ExpandableSectionCard(
      title: 'Diagnostics',
      icon: Icons.analytics_outlined,
      accentColor: const Color(0xFF6A1B9A),
      isExpanded: _expandedSections['diagnostics']!,
      onToggle: () => _toggleSection('diagnostics'),
      children: [
        BooleanValueWidget(
          label: 'Data Stopped (1s)',
          characteristic: _c(0),
          packetIndex: 0,
        ),
        BooleanValueWidget(
          label: 'Comm Error C1',
          characteristic: _c(1),
          packetIndex: 1,
        ),
        BooleanValueWidget(
          label: 'Comm Error C2',
          characteristic: _c(2),
          packetIndex: 2,
        ),
        BooleanValueWidget(
          label: 'Comm Error C3',
          characteristic: _c(3),
          packetIndex: 3,
        ),
        BooleanValueWidget(
          label: 'Comm Error C4',
          characteristic: _c(24),
          packetIndex: 24,
        ),
        BooleanValueWidget(
          label: 'Sensor Connected',
          characteristic: _c(4),
          packetIndex: 4,
        ),
        BooleanValueWidget(
          label: 'DAT Not Found',
          characteristic: _c(5),
          packetIndex: 5,
        ),
        BooleanValueWidget(
          label: 'Remote DAT Node 1',
          characteristic: _c(6),
          packetIndex: 6,
        ),
        BooleanValueWidget(
          label: 'Remote DAT Node 2',
          characteristic: _c(7),
          packetIndex: 7,
        ),
        BooleanValueWidget(
          label: 'Remote DAT Node 3',
          characteristic: _c(8),
          packetIndex: 8,
        ),
        BooleanValueWidget(
          label: 'Remote DAT Node 4',
          characteristic: _c(25),
          packetIndex: 25,
        ),
        BooleanValueWidget(
          label: 'Zero Distance Measured',
          characteristic: _c(9),
          packetIndex: 9,
        ),
      ],
    );
  }

  Widget _buildOutputPinsSection() {
    return _ExpandableSectionCard(
      title: 'Output Pins',
      icon: Icons.toggle_on_outlined,
      accentColor: const Color(0xFF2E7D32),
      isExpanded: _expandedSections['output']!,
      onToggle: () => _toggleSection('output'),
      children: [
        BooleanValueWidget(
          label: 'Output PIN Relay',
          characteristic: _c(10),
          packetIndex: 10,
        ),
        BooleanValueWidget(
          label: 'Forward Slow',
          characteristic: _c(11),
          packetIndex: 11,
        ),
        BooleanValueWidget(
          label: 'Forward Stop',
          characteristic: _c(12),
          packetIndex: 12,
        ),
        BooleanValueWidget(
          label: 'Reverse Slow',
          characteristic: _c(13),
          packetIndex: 13,
        ),
        BooleanValueWidget(
          label: 'Reverse Stop',
          characteristic: _c(14),
          packetIndex: 14,
        ),
      ],
    );
  }

  Widget _buildLoadMonitoringSection() {
    return _ExpandableSectionCard(
      title: 'Load Monitoring (kg)',
      icon: Icons.monitor_weight_outlined,
      accentColor: const Color(0xFFC62828),
      isExpanded: _expandedSections['load']!,
      onToggle: () => _toggleSection('load'),
      children: [
        FloatValueWidget(
          label: 'H1 Measured Load',
          characteristic: _c(19),
          packetIndex: 19,
        ),
        FloatValueWidget(
          label: 'H2 Measured Load',
          characteristic: _c(20),
          packetIndex: 20,
        ),
        FloatValueWidget(
          label: 'Total Measured Load',
          characteristic: _c(21),
          packetIndex: 21,
        ),
      ],
    );
  }

  Widget _buildAnticollisionSection() {
    return _ExpandableSectionCard(
      title: 'Anticollision Bypass',
      icon: Icons.radar,
      accentColor: const Color(0xFFE65100),
      isExpanded: _expandedSections['anticollision']!,
      onToggle: () => _toggleSection('anticollision'),
      children: [
        BooleanValueWidget(
          label: 'Bypassed (Crane 3)',
          characteristic: _c(22),
          packetIndex: 22,
        ),
        BooleanValueWidget(
          label: 'Bypassed (Crane 4)',
          characteristic: _c(23),
          packetIndex: 23,
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

//  expandable section card

class _ExpandableSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _ExpandableSectionCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.white,
          child: Column(
            children: [
              InkWell(
                onTap: onToggle,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor,
                        accentColor.withValues(alpha: 0.80),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Animated content ───────────────────────────────────────────
              ClipRect(
                child: AnimatedAlign(
                  alignment: Alignment.topCenter,
                  heightFactor: isExpanded ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
