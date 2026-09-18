abstract interface class NexusBridge {
  Future<BridgeStatus> status();

  Future<PairingSession> beginPairing();

  Future<void> disconnect();

  Future<BridgeCapabilityReport> capabilities();
}

class BridgeStatus {
  const BridgeStatus({
    required this.connected,
    this.deviceName,
    this.modelName,
  });

  final bool connected;
  final String? deviceName;
  final String? modelName;
}

class PairingSession {
  const PairingSession({
    required this.code,
    required this.expiresAt,
    this.qrPayload,
  });

  final String code;
  final DateTime expiresAt;
  final String? qrPayload;
}

class BridgeCapabilityReport {
  const BridgeCapabilityReport({
    required this.ai,
    required this.git,
    required this.terminal,
    required this.builds,
    required this.tests,
  });

  final bool ai;
  final bool git;
  final bool terminal;
  final bool builds;
  final bool tests;
}
