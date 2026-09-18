import 'package:flutter/foundation.dart';

import '../models/nexus_preferences.dart';

class NexusController extends ChangeNotifier {
  AiTarget _aiTarget = AiTarget.pc;
  BuildTarget _buildTarget = BuildTarget.github;
  AgentMode _agentMode = AgentMode.autonomous;
  SyncMode _syncMode = SyncMode.automatic;
  bool _autoFix = true;

  AiTarget get aiTarget => _aiTarget;
  BuildTarget get buildTarget => _buildTarget;
  AgentMode get agentMode => _agentMode;
  SyncMode get syncMode => _syncMode;
  bool get autoFix => _autoFix;

  void setAiTarget(AiTarget value) {
    if (_aiTarget == value) return;
    _aiTarget = value;
    notifyListeners();
  }

  void setBuildTarget(BuildTarget value) {
    if (_buildTarget == value) return;
    _buildTarget = value;
    notifyListeners();
  }

  void setAgentMode(AgentMode value) {
    if (_agentMode == value) return;
    _agentMode = value;
    notifyListeners();
  }

  void setSyncMode(SyncMode value) {
    if (_syncMode == value) return;
    _syncMode = value;
    notifyListeners();
  }

  void setAutoFix(bool value) {
    if (_autoFix == value) return;
    _autoFix = value;
    notifyListeners();
  }
}
