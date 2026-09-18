import '../models/nexus_preferences.dart';

abstract interface class NexusBuildRunner {
  BuildTarget get target;

  Future<BuildResult> run({
    required String workspaceId,
    required BuildRequest request,
  });
}

class BuildRequest {
  const BuildRequest({
    this.analyze = true,
    this.test = true,
    this.build = true,
  });

  final bool analyze;
  final bool test;
  final bool build;
}

class BuildResult {
  const BuildResult({
    required this.success,
    required this.log,
    this.artifactPath,
  });

  final bool success;
  final String log;
  final String? artifactPath;
}
