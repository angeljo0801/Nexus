import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class GitHubWorkflowRun {
  const GitHubWorkflowRun({
    required this.id,
    required this.status,
    required this.conclusion,
    required this.headSha,
    required this.htmlUrl,
  });

  final int id;
  final String status;
  final String conclusion;
  final String headSha;
  final String htmlUrl;

  bool get completed => status == 'completed';
  bool get succeeded => completed && conclusion == 'success';
}

class GitHubBuildResult {
  const GitHubBuildResult({
    required this.run,
    required this.logExcerpt,
  });

  final GitHubWorkflowRun run;
  final String logExcerpt;
}

class GitHubActionsService {
  GitHubActionsService();

  static const _apiVersion = '2026-03-10';

  Map<String, String> _headers(String token) => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': _apiVersion,
        'User-Agent': 'Nexus-Android',
      };

  Uri _repoUri(String repo, String path, [Map<String, String>? query]) {
    return Uri.https(
      'api.github.com',
      '/repos/$repo$path',
      query,
    );
  }

  Future<int> dispatchWorkflow({
    required String token,
    required String repositoryFullName,
    required String workflow,
    required String branch,
  }) async {
    final started = DateTime.now().toUtc();
    final encodedWorkflow = Uri.encodeComponent(workflow);
    final response = await http.post(
      _repoUri(
        repositoryFullName,
        '/actions/workflows/$encodedWorkflow/dispatches',
      ),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'ref': branch}),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw StateError(
        'GitHub Actions dispatch failed with HTTP '
        '${response.statusCode}: ${_shortBody(response.body)}',
      );
    }

    if (response.body.trim().isNotEmpty) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final directId = (data['workflow_run_id'] as num?)?.toInt();
        if (directId != null) return directId;
      } catch (_) {}
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final id = await _findRecentDispatch(
        token: token,
        repositoryFullName: repositoryFullName,
        workflow: workflow,
        branch: branch,
        startedAfter: started.subtract(const Duration(seconds: 5)),
      );
      if (id != null) return id;
    }

    throw StateError(
      'GitHub accepted the build request but Nexus could not identify '
      'the new workflow run.',
    );
  }

  Future<int?> _findRecentDispatch({
    required String token,
    required String repositoryFullName,
    required String workflow,
    required String branch,
    required DateTime startedAfter,
  }) async {
    final encodedWorkflow = Uri.encodeComponent(workflow);
    final response = await http.get(
      _repoUri(
        repositoryFullName,
        '/actions/workflows/$encodedWorkflow/runs',
        {
          'branch': branch,
          'event': 'workflow_dispatch',
          'per_page': '10',
        },
      ),
      headers: _headers(token),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final runs = data['workflow_runs'];
    if (runs is! List) return null;

    for (final raw in runs.whereType<Map>()) {
      final created =
          DateTime.tryParse(raw['created_at']?.toString() ?? '');
      if (created == null || created.isBefore(startedAfter)) continue;
      return (raw['id'] as num?)?.toInt();
    }

    return null;
  }

  Future<GitHubWorkflowRun> getRun({
    required String token,
    required String repositoryFullName,
    required int runId,
  }) async {
    final response = await http.get(
      _repoUri(repositoryFullName, '/actions/runs/$runId'),
      headers: _headers(token),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Could not read GitHub build $runId '
        '(HTTP ${response.statusCode}).',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubWorkflowRun(
      id: (data['id'] as num?)?.toInt() ?? runId,
      status: data['status']?.toString() ?? '',
      conclusion: data['conclusion']?.toString() ?? '',
      headSha: data['head_sha']?.toString() ?? '',
      htmlUrl: data['html_url']?.toString() ?? '',
    );
  }

  Future<GitHubBuildResult> waitForCompletion({
    required String token,
    required String repositoryFullName,
    required int runId,
    Duration timeout = const Duration(minutes: 30),
    void Function(GitHubWorkflowRun run)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    GitHubWorkflowRun run = await getRun(
      token: token,
      repositoryFullName: repositoryFullName,
      runId: runId,
    );

    while (!run.completed && DateTime.now().isBefore(deadline)) {
      onProgress?.call(run);
      await Future<void>.delayed(const Duration(seconds: 8));
      run = await getRun(
        token: token,
        repositoryFullName: repositoryFullName,
        runId: runId,
      );
    }

    if (!run.completed) {
      throw TimeoutException(
        'GitHub build did not finish within ${timeout.inMinutes} minutes.',
      );
    }

    onProgress?.call(run);
    final logs = run.succeeded
        ? ''
        : await failedLogs(
            token: token,
            repositoryFullName: repositoryFullName,
            runId: runId,
          );

    return GitHubBuildResult(
      run: run,
      logExcerpt: logs,
    );
  }

  Future<String> failedLogs({
    required String token,
    required String repositoryFullName,
    required int runId,
  }) async {
    final jobsResponse = await http.get(
      _repoUri(
        repositoryFullName,
        '/actions/runs/$runId/jobs',
        {'per_page': '100'},
      ),
      headers: _headers(token),
    );

    if (jobsResponse.statusCode < 200 ||
        jobsResponse.statusCode >= 300) {
      return 'Could not retrieve failed job metadata.';
    }

    final data = jsonDecode(jobsResponse.body) as Map<String, dynamic>;
    final jobs = data['jobs'];
    if (jobs is! List) return 'No GitHub Actions jobs were returned.';

    final buffer = StringBuffer();

    for (final raw in jobs.whereType<Map>()) {
      final conclusion = raw['conclusion']?.toString() ?? '';
      if (conclusion == 'success' || conclusion == 'skipped') continue;

      final jobId = (raw['id'] as num?)?.toInt();
      if (jobId == null) continue;

      buffer.writeln(
        '===== JOB: ${raw['name'] ?? jobId} '
        '(${conclusion.isEmpty ? 'failed' : conclusion}) =====',
      );

      try {
        final request = http.Request(
          'GET',
          _repoUri(repositoryFullName, '/actions/jobs/$jobId/logs'),
        );
        request.headers.addAll(_headers(token));
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamed = await request.send();
        if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
          final body = await streamed.stream.bytesToString();
          buffer.writeln(_tail(body, 18000));
        } else {
          buffer.writeln(
            'Could not download job logs '
            '(HTTP ${streamed.statusCode}).',
          );
        }
      } catch (error) {
        buffer.writeln('Could not download job logs: $error');
      }
    }

    final value = buffer.toString().trim();
    return value.isEmpty
        ? 'Build failed, but GitHub returned no failed-job log text.'
        : _tail(value, 24000);
  }

  String _shortBody(String body) {
    final clean = body.trim();
    if (clean.length <= 500) return clean;
    return '${clean.substring(0, 500)}…';
  }

  String _tail(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return text.substring(math.max(0, text.length - maxChars));
  }
}
