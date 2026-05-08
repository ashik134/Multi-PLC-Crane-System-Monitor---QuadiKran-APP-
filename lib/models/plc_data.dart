/// Mirrors the 26 BLE characteristics from the ESP32 ACS Diagnostic Monitor.
///
/// Char indices (0-based, matching pChar[] in ble_broadcast.cpp):
///   0  dataStopped1Sec       (bool)   9  zeroDistanceMeasured (bool)
///   1  errorCommWithC1       (bool)  10  outputPINRelay       (bool)
///   2  errorCommWithC2       (bool)  11  outputPIN1           (bool)
///   3  errorCommWithC3       (bool)  12  outputPIN2           (bool)
///   4  sensorConnected       (bool)  13  outputPIN3           (bool)
///   5  DATNotFound           (bool)  14  outputPIN4           (bool)
///   6  remoteDATFromNode1    (bool)  15  crane1Value          (float mm)
///   7  remoteDATFromNode2    (bool)  16  crane2Value          (float mm)
///   8  remoteDATFromNode3    (bool)  17  crane3Value          (float mm)
///                                    18  crane4Value          (float mm)
///
/// Anticollision service (6e410001 / chars 6e410015-6e410019), indices 19-23:
///  19  h1LoadKg             (float kg)  22  bypassC3 / bypassed  (bool)
///  20  h2LoadKg             (float kg)  23  bypassC4 / bypassedC4(bool)
///  21  totalLoadKg          (float kg)
///
/// Extended diagnostics, indices 24-25:
///  24  errorCommWithC4      (bool)
///  25  remoteDATFromNode4   (bool)
class PLCData {
  final String plcId;
  final String plcName;

  // --- Diagnostic booleans ---
  final bool dataStopped1Sec;
  final bool errorCommWithC1;
  final bool errorCommWithC2;
  final bool errorCommWithC3;
  final bool sensorConnected;
  final bool datNotFound; // DATNotFound
  final bool remoteDAT1; // remoteDATNotFoundFromNode1
  final bool remoteDAT2; // remoteDATNotFoundFromNode2
  final bool remoteDAT3; // remoteDATNotFoundFromNode3
  final bool remoteDAT4; // remoteDATNotFoundFromNode4
  final bool zeroDistanceMeasured;

  // --- Extended comm errors ---
  final bool errorCommWithC4;

  // --- Output-pin states ---
  final bool outputPINRelay;
  final bool outputPIN1;
  final bool outputPIN2;
  final bool outputPIN3;
  final bool outputPIN4;

  // --- Crane position floats (mm) ---
  final double crane1Value;
  final double crane2Value;
  final double crane3Value;
  final double crane4Value;

  // --- Anticollision load monitoring (kg) ---
  final double h1LoadKg;
  final double h2LoadKg;
  final double totalLoadKg;

  // --- Anticollision bypass flags ---
  final bool bypassC3; // bypassed (Crane 3)
  final bool bypassC4; // bypassedC4 (Crane 4)

  final DateTime timestamp;

  const PLCData({
    required this.plcId,
    required this.plcName,
    required this.dataStopped1Sec,
    required this.errorCommWithC1,
    required this.errorCommWithC2,
    required this.errorCommWithC3,
    required this.sensorConnected,
    required this.datNotFound,
    required this.remoteDAT1,
    required this.remoteDAT2,
    required this.remoteDAT3,
    required this.remoteDAT4,
    required this.zeroDistanceMeasured,
    required this.errorCommWithC4,
    required this.outputPINRelay,
    required this.outputPIN1,
    required this.outputPIN2,
    required this.outputPIN3,
    required this.outputPIN4,
    required this.crane1Value,
    required this.crane2Value,
    required this.crane3Value,
    required this.crane4Value,
    required this.h1LoadKg,
    required this.h2LoadKg,
    required this.totalLoadKg,
    required this.bypassC3,
    required this.bypassC4,
    required this.timestamp,
  });

  factory PLCData.empty(String plcId, String plcName) => PLCData(
    plcId: plcId,
    plcName: plcName,
    dataStopped1Sec: false,
    errorCommWithC1: false,
    errorCommWithC2: false,
    errorCommWithC3: false,
    sensorConnected: false,
    datNotFound: false,
    remoteDAT1: false,
    remoteDAT2: false,
    remoteDAT3: false,
    remoteDAT4: false,
    zeroDistanceMeasured: false,
    errorCommWithC4: false,
    outputPINRelay: false,
    outputPIN1: false,
    outputPIN2: false,
    outputPIN3: false,
    outputPIN4: false,
    crane1Value: 0.0,
    crane2Value: 0.0,
    crane3Value: 0.0,
    crane4Value: 0.0,
    h1LoadKg: 0.0,
    h2LoadKg: 0.0,
    totalLoadKg: 0.0,
    bypassC3: false,
    bypassC4: false,
    timestamp: DateTime.now(),
  );

  PLCData copyWith({
    bool? dataStopped1Sec,
    bool? errorCommWithC1,
    bool? errorCommWithC2,
    bool? errorCommWithC3,
    bool? sensorConnected,
    bool? datNotFound,
    bool? remoteDAT1,
    bool? remoteDAT2,
    bool? remoteDAT3,
    bool? remoteDAT4,
    bool? zeroDistanceMeasured,
    bool? errorCommWithC4,
    bool? outputPINRelay,
    bool? outputPIN1,
    bool? outputPIN2,
    bool? outputPIN3,
    bool? outputPIN4,
    double? crane1Value,
    double? crane2Value,
    double? crane3Value,
    double? crane4Value,
    double? h1LoadKg,
    double? h2LoadKg,
    double? totalLoadKg,
    bool? bypassC3,
    bool? bypassC4,
    DateTime? timestamp,
  }) => PLCData(
    plcId: plcId,
    plcName: plcName,
    dataStopped1Sec: dataStopped1Sec ?? this.dataStopped1Sec,
    errorCommWithC1: errorCommWithC1 ?? this.errorCommWithC1,
    errorCommWithC2: errorCommWithC2 ?? this.errorCommWithC2,
    errorCommWithC3: errorCommWithC3 ?? this.errorCommWithC3,
    sensorConnected: sensorConnected ?? this.sensorConnected,
    datNotFound: datNotFound ?? this.datNotFound,
    remoteDAT1: remoteDAT1 ?? this.remoteDAT1,
    remoteDAT2: remoteDAT2 ?? this.remoteDAT2,
    remoteDAT3: remoteDAT3 ?? this.remoteDAT3,
    remoteDAT4: remoteDAT4 ?? this.remoteDAT4,
    zeroDistanceMeasured: zeroDistanceMeasured ?? this.zeroDistanceMeasured,
    errorCommWithC4: errorCommWithC4 ?? this.errorCommWithC4,
    outputPINRelay: outputPINRelay ?? this.outputPINRelay,
    outputPIN1: outputPIN1 ?? this.outputPIN1,
    outputPIN2: outputPIN2 ?? this.outputPIN2,
    outputPIN3: outputPIN3 ?? this.outputPIN3,
    outputPIN4: outputPIN4 ?? this.outputPIN4,
    crane1Value: crane1Value ?? this.crane1Value,
    crane2Value: crane2Value ?? this.crane2Value,
    crane3Value: crane3Value ?? this.crane3Value,
    crane4Value: crane4Value ?? this.crane4Value,
    h1LoadKg: h1LoadKg ?? this.h1LoadKg,
    h2LoadKg: h2LoadKg ?? this.h2LoadKg,
    totalLoadKg: totalLoadKg ?? this.totalLoadKg,
    bypassC3: bypassC3 ?? this.bypassC3,
    bypassC4: bypassC4 ?? this.bypassC4,
    timestamp: timestamp ?? DateTime.now(),
  );

  /// Excludes [timestamp] from equality — two snapshots with identical field
  /// values are considered equal regardless of when they were received.
  // This allows Selector<PLCBluetoothService, PLCData?> to skip rebuilds when
  /// the PLC data hasn't actually changed.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PLCData) return false;
    return plcId == other.plcId &&
        plcName == other.plcName &&
        dataStopped1Sec == other.dataStopped1Sec &&
        errorCommWithC1 == other.errorCommWithC1 &&
        errorCommWithC2 == other.errorCommWithC2 &&
        errorCommWithC3 == other.errorCommWithC3 &&
        sensorConnected == other.sensorConnected &&
        datNotFound == other.datNotFound &&
        remoteDAT1 == other.remoteDAT1 &&
        remoteDAT2 == other.remoteDAT2 &&
        remoteDAT3 == other.remoteDAT3 &&
        remoteDAT4 == other.remoteDAT4 &&
        zeroDistanceMeasured == other.zeroDistanceMeasured &&
        errorCommWithC4 == other.errorCommWithC4 &&
        outputPINRelay == other.outputPINRelay &&
        outputPIN1 == other.outputPIN1 &&
        outputPIN2 == other.outputPIN2 &&
        outputPIN3 == other.outputPIN3 &&
        outputPIN4 == other.outputPIN4 &&
        crane1Value == other.crane1Value &&
        crane2Value == other.crane2Value &&
        crane3Value == other.crane3Value &&
        crane4Value == other.crane4Value &&
        h1LoadKg == other.h1LoadKg &&
        h2LoadKg == other.h2LoadKg &&
        totalLoadKg == other.totalLoadKg &&
        bypassC3 == other.bypassC3 &&
        bypassC4 == other.bypassC4;
  }

  @override
  int get hashCode => Object.hashAll([
    plcId,
    plcName,
    dataStopped1Sec,
    errorCommWithC1,
    errorCommWithC2,
    errorCommWithC3,
    sensorConnected,
    datNotFound,
    remoteDAT1,
    remoteDAT2,
    remoteDAT3,
    remoteDAT4,
    zeroDistanceMeasured,
    errorCommWithC4,
    outputPINRelay,
    outputPIN1,
    outputPIN2,
    outputPIN3,
    outputPIN4,
    crane1Value,
    crane2Value,
    crane3Value,
    crane4Value,
    h1LoadKg,
    h2LoadKg,
    totalLoadKg,
    bypassC3,
    bypassC4,
  ]);
}
