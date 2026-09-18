abstract interface class RepositorySyncService {
  Future<SyncStatus> status(String workspaceId);

  Future<SyncResult> sync(String workspaceId);
}

class SyncStatus {
  const SyncStatus({
    required this.phoneChanges,
    required this.pcChanges,
    required this.remoteAhead,
    required this.remoteBehind,
    required this.hasConflict,
  });

  final bool phoneChanges;
  final bool pcChanges;
  final int remoteAhead;
  final int remoteBehind;
  final bool hasConflict;
}

class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    this.conflicts = const [],
  });

  final bool success;
  final String message;
  final List<String> conflicts;
}
