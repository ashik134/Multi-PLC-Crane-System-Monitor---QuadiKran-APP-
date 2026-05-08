class EmergencyAlert {
  final String plcId;
  final String deviceName;
  final DateTime triggeredAt;
  final bool isActive;

  const EmergencyAlert({
    required this.plcId,
    required this.deviceName,
    required this.triggeredAt,
    required this.isActive,
  });
  @override
  String toString() =>
      'EmergencyAlert($plcId, isActive: $isActive, at: $triggeredAt)';
}
