import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:nexus_android_bridge/nexus_android_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'project_workspace_service.dart';

class PhoneBuildAvailability {
  const PhoneBuildAvailability({
    required this.termuxInstalled,
    required this.runCommandPermission,
    required this.toolchainVerified,
    this.termuxVersion,
  });

  final bool termuxInstalled;
  final bool runCommandPermission;
  final bool toolchainVerified;
  final String? termuxVersion;

  bool get ready =>
      termuxInstalled && runCommandPermission && toolchainVerified;

  String get summary {
    if (!termuxInstalled) return 'Termux is not installed.';
    if (!runCommandPermission) {
      return 'Nexus needs permission to run approved commands in Termux.';
    }
    if (!toolchainVerified) {
      return 'Termux is connected, but the Flutter ARM64 toolchain is not verified.';
    }
    return 'Phone runner ready${termuxVersion == null ? '' : ' · Termux $termuxVersion'}.';
  }
}

class PhoneBuildExecutionResult {
  const PhoneBuildExecutionResult({
    required this.success,
    required this.log,
    required this.message,
    this.artifactPath,
    this.exitCode,
  });

  final bool success;
  final String log;
  final String message;
  final String? artifactPath;
  final int? exitCode;
}

class PhoneBuildRunner {
  PhoneBuildRunner._();

  static final PhoneBuildRunner instance = PhoneBuildRunner._();

  static const _verifiedKey = 'phone_runner_flutter_3449_verified';
  static const flutterVersion = '3.44.9';
  static const flutterPackageSha256 =
      'ca2cb4de90e657db5445ea3142bfdc71e6be511da8f56b8cdfd9eb49d71ac6b0';
  static const flutterPackageUrl =
      'https://github.com/ImL1s/termux-flutter-wsl/releases/download/'
      'v3.44.9-termux-1/flutter_3.44.9-1_aarch64.deb';

  final ProjectWorkspaceService _workspace = ProjectWorkspaceService.instance;

  Future<PhoneBuildAvailability> availability() async {
    final native = await NexusAndroidBridge.termuxStatus();
    final prefs = await SharedPreferences.getInstance();
    final verified = prefs.getBool(_verifiedKey) ?? false;
    return PhoneBuildAvailability(
      termuxInstalled: native.installed,
      runCommandPermission: native.runCommandPermission,
      toolchainVerified: verified,
      termuxVersion: native.version,
    );
  }

  Future<bool> requestRunCommandPermission() async {
    return NexusAndroidBridge.requestTermuxRunCommandPermission();
  }

  Future<void> openTermux() => NexusAndroidBridge.openTermux();

  Future<void> clearVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_verifiedKey);
  }

  Future<PhoneBuildExecutionResult> verify({
    void Function(String status)? onStatus,
  }) async {
    final status = await availability();
    if (!status.termuxInstalled) {
      return const PhoneBuildExecutionResult(
        success: false,
        log: '',
        message: 'Termux is not installed.',
      );
    }
    if (!status.runCommandPermission) {
      return const PhoneBuildExecutionResult(
        success: false,
        log: '',
        message:
            'Grant Nexus the "Run commands in Termux environment" permission first.',
      );
    }

    onStatus?.call('Checking Flutter ARM64 inside Termux…');
    final result = await _runCallbackSession(
      label: 'Nexus Phone Runner Check',
      timeout: const Duration(minutes: 3),
      onStatus: onStatus,
      scriptBuilder: (session) => _verificationScript(session),
    );

    final prefs = await SharedPreferences.getInstance();
    if (result.success) {
      await prefs.setBool(_verifiedKey, true);
    } else {
      await prefs.remove(_verifiedKey);
    }
    return result;
  }

  Future<PhoneBuildExecutionResult> installToolchain({
    void Function(String status)? onStatus,
  }) async {
    final status = await availability();
    if (!status.termuxInstalled) {
      return const PhoneBuildExecutionResult(
        success: false,
        log: '',
        message: 'Termux is not installed.',
      );
    }
    if (!status.runCommandPermission) {
      return const PhoneBuildExecutionResult(
        success: false,
        log: '',
        message:
            'Grant Nexus the "Run commands in Termux environment" permission first.',
      );
    }

    onStatus?.call('Installing Flutter $flutterVersion ARM64 in Termux…');
    final result = await _runCallbackSession(
      label: 'Install Nexus Phone Runner',
      timeout: const Duration(minutes: 45),
      onStatus: onStatus,
      scriptBuilder: (session) => _installerScript(session),
    );

    final prefs = await SharedPreferences.getInstance();
    if (result.success) {
      await prefs.setBool(_verifiedKey, true);
    } else {
      await prefs.remove(_verifiedKey);
    }
    return result;
  }

  Future<PhoneBuildExecutionResult> build({
    required String projectId,
    void Function(String status)? onStatus,
  }) async {
    final status = await availability();
    if (!status.ready) {
      return PhoneBuildExecutionResult(
        success: false,
        log: '',
        message: status.summary,
      );
    }

    final workspace = await _workspace.workspaceDirectory(projectId);
    final pubspec = File(p.join(workspace.path, 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      return const PhoneBuildExecutionResult(
        success: false,
        log: '',
        message:
            'The phone runner currently supports Flutter projects with pubspec.yaml.',
      );
    }

    onStatus?.call('Packaging the local project for Termux…');
    final archiveFile = await _createProjectArchive(projectId);

    try {
      return await _runCallbackSession(
        label: 'Nexus Flutter Phone Build',
        timeout: const Duration(minutes: 45),
        projectArchive: archiveFile,
        artifactProjectId: projectId,
        onStatus: onStatus,
        scriptBuilder: (session) => _buildScript(session),
      );
    } finally {
      try {
        if (await archiveFile.exists()) {
          await archiveFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<File> _createProjectArchive(String projectId) async {
    final workspace = await _workspace.workspaceDirectory(projectId);
    final cache = await getTemporaryDirectory();
    final session = DateTime.now().microsecondsSinceEpoch.toString();
    final zip = File(p.join(cache.path, 'nexus-phone-$session.zip'));

    final encoder = ZipFileEncoder();
    encoder.create(zip.path);

    try {
      final files = await _workspace.listFiles(projectId, limit: 5000);
      for (final relative in files) {
        final source = File(p.join(workspace.path, relative));
        if (!await source.exists()) continue;
        final size = await source.length();
        if (size > 64 * 1024 * 1024) {
          throw StateError(
            'Phone build skipped oversized project file: $relative',
          );
        }
        await encoder.addFile(source, relative);
      }
    } finally {
      await encoder.close();
    }

    return zip;
  }

  Future<PhoneBuildExecutionResult> _runCallbackSession({
    required String label,
    required Duration timeout,
    required String Function(_PhoneRunnerSession session) scriptBuilder,
    File? projectArchive,
    String? artifactProjectId,
    void Function(String status)? onStatus,
  }) async {
    final random = Random.secure();
    final sessionId =
        '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 31)}';
    final token = List<int>.generate(32, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );

    final completer = Completer<Map<String, Object?>>();
    var log = '';
    String? artifactPath;

    final session = _PhoneRunnerSession(
      id: sessionId,
      token: token,
      port: server.port,
    );

    Future<void> handle(HttpRequest request) async {
      try {
        if (request.headers.value('x-nexus-token') != token) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }

        final base = '/nexus/$sessionId';
        if (!request.uri.path.startsWith(base)) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final endpoint = request.uri.path.substring(base.length);

        if (request.method == 'GET' && endpoint == '/project.zip') {
          if (projectArchive == null || !await projectArchive.exists()) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.contentType =
                ContentType('application', 'zip');
            request.response.contentLength = await projectArchive.length();
            await request.response.addStream(projectArchive.openRead());
          }
          await request.response.close();
          return;
        }

        if (request.method == 'POST' && endpoint == '/phase') {
          final body = await utf8.decoder.bind(request).join();
          final phase = body.trim();
          if (phase.isNotEmpty) onStatus?.call(phase);
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        if (request.method == 'POST' && endpoint == '/log') {
          final bytes = <int>[];
          await for (final chunk in request) {
            if (bytes.length < 300000) {
              final remaining = 300000 - bytes.length;
              bytes.addAll(
                chunk.length <= remaining
                    ? chunk
                    : chunk.sublist(0, remaining),
              );
            }
          }
          log = utf8.decode(bytes, allowMalformed: true);
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        if (request.method == 'POST' && endpoint == '/artifact') {
          if (artifactProjectId == null) {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
            return;
          }

          final root = await _workspace.projectRoot(artifactProjectId);
          final outputDir = Directory(
            p.join(root.path, 'artifacts', 'phone'),
          );
          await outputDir.create(recursive: true);
          final output = File(
            p.join(
              outputDir.path,
              '${DateTime.now().millisecondsSinceEpoch}-app-debug.apk',
            ),
          );
          final sink = output.openWrite();
          await for (final chunk in request) {
            sink.add(chunk);
          }
          await sink.close();
          artifactPath = output.path;
          request.response.statusCode = HttpStatus.created;
          await request.response.close();
          return;
        }

        if (request.method == 'POST' && endpoint == '/complete') {
          final body = await utf8.decoder.bind(request).join();
          final decoded = body.trim().isEmpty
              ? <String, Object?>{}
              : (jsonDecode(body) as Map).cast<String, Object?>();
          if (!completer.isCompleted) {
            completer.complete(decoded);
          }
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (error) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.complete({
            'success': false,
            'message': 'Nexus local callback server error: $error',
          });
        }
      }
    }

    final subscription = server.listen(handle);

    try {
      final script = scriptBuilder(session);
      await NexusAndroidBridge.runTermuxScript(
        script,
        label: label,
      );

      final complete = await completer.future.timeout(
        timeout,
        onTimeout: () => {
          'success': false,
          'message':
              'Timed out waiting for Termux. Make sure allow-external-apps=true '
              'is enabled in ~/.termux/termux.properties and Termux is allowed '
              'to run in the background.',
        },
      );

      final success = complete['success'] == true;
      final exitCodeRaw = complete['exitCode'];
      final exitCode = exitCodeRaw is num ? exitCodeRaw.toInt() : null;
      final message = (complete['message'] as String?) ??
          (success ? 'Phone-local build completed.' : 'Phone-local build failed.');

      return PhoneBuildExecutionResult(
        success: success,
        log: log,
        message: message,
        artifactPath: artifactPath,
        exitCode: exitCode,
      );
    } catch (error) {
      return PhoneBuildExecutionResult(
        success: false,
        log: log,
        message: 'Could not start the Termux runner: $error',
        artifactPath: artifactPath,
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  String _callbackFunctions(_PhoneRunnerSession session) => '''
NEXUS_BASE="http://127.0.0.1:${session.port}/nexus/${session.id}"
NEXUS_TOKEN="${session.token}"
nexus_phase() {
  curl -fsS -X POST -H "X-Nexus-Token: \$NEXUS_TOKEN" \
    --data-binary "\$1" "\$NEXUS_BASE/phase" >/dev/null 2>&1 || true
}
nexus_log() {
  if [ -f "\$NEXUS_LOG" ]; then
    tail -c 280000 "\$NEXUS_LOG" | curl -fsS -X POST \
      -H "X-Nexus-Token: \$NEXUS_TOKEN" --data-binary @- \
      "\$NEXUS_BASE/log" >/dev/null 2>&1 || true
  fi
}
nexus_complete() {
  local success="\$1"
  local code="\$2"
  local message="\$3"
  nexus_log
  curl -fsS -X POST -H "X-Nexus-Token: \$NEXUS_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"success\":\$success,\"exitCode\":\$code,\"message\":\"\$message\"}" \
    "\$NEXUS_BASE/complete" >/dev/null 2>&1 || true
}
''';

  String _verificationScript(_PhoneRunnerSession session) => '''
set -Eeuo pipefail
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
NEXUS_LOG="\$HOME/.nexus/verify.log"
mkdir -p "\$HOME/.nexus"
: > "\$NEXUS_LOG"
exec > >(tee -a "\$NEXUS_LOG") 2>&1
${_callbackFunctions(session)}
trap 'code=\$?; nexus_complete false "\$code" "Phone runner verification failed"; exit "\$code"' ERR

command -v curl >/dev/null
if [ -f "\$PREFIX/etc/profile.d/flutter.sh" ]; then
  source "\$PREFIX/etc/profile.d/flutter.sh"
fi
nexus_phase "Checking Flutter ARM64 toolchain…"
command -v flutter
flutter --version
if command -v flutter-termux >/dev/null 2>&1; then
  flutter-termux --check
fi
command -v java
java -version
command -v aapt2
nexus_complete true 0 "Flutter $flutterVersion phone runner verified"
''';

  String _installerScript(_PhoneRunnerSession session) => '''
set -Eeuo pipefail
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
mkdir -p "\$HOME/.nexus"
NEXUS_LOG="\$HOME/.nexus/install.log"
: > "\$NEXUS_LOG"
exec > >(tee -a "\$NEXUS_LOG") 2>&1

pkg update -y
pkg install -y x11-repo wget curl unzip openjdk-21 openjdk-17
${_callbackFunctions(session)}
trap 'code=\$?; nexus_complete false "\$code" "Flutter ARM64 installation failed"; exit "\$code"' ERR

nexus_phase "Downloading Flutter $flutterVersion for Termux ARM64…"
PKG="\$HOME/.nexus/flutter_${flutterVersion}_aarch64.deb"
wget -O "\$PKG" "$flutterPackageUrl"
echo "$flutterPackageSha256  \$PKG" | sha256sum -c -

nexus_phase "Installing Flutter ARM64 package…"
dpkg -i "\$PKG" || apt --fix-broken install -y
bash "\$PREFIX/share/flutter/post_install.sh"
source "\$PREFIX/etc/profile.d/flutter.sh"

nexus_phase "Verifying the phone build toolchain…"
flutter --version
if command -v flutter-termux >/dev/null 2>&1; then
  flutter-termux --check
fi
flutter doctor -v || true
command -v aapt2
nexus_complete true 0 "Flutter $flutterVersion ARM64 installed and verified"
''';

  String _buildScript(_PhoneRunnerSession session) => '''
set -Eeuo pipefail
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
if [ -f "\$PREFIX/etc/profile.d/flutter.sh" ]; then
  source "\$PREFIX/etc/profile.d/flutter.sh"
fi
${_callbackFunctions(session)}

ROOT="\$HOME/.nexus/builds/${session.id}"
rm -rf "\$ROOT"
mkdir -p "\$ROOT/project"
NEXUS_LOG="\$ROOT/build.log"
: > "\$NEXUS_LOG"
exec > >(tee -a "\$NEXUS_LOG") 2>&1
trap 'code=\$?; nexus_complete false "\$code" "Phone-local Flutter build failed"; exit "\$code"' ERR

nexus_phase "Downloading the project into Termux…"
curl -fsS -H "X-Nexus-Token: \$NEXUS_TOKEN" \
  "\$NEXUS_BASE/project.zip" -o "\$ROOT/project.zip"
unzip -q "\$ROOT/project.zip" -d "\$ROOT/project"
cd "\$ROOT/project"

nexus_phase "Preparing Termux Android build settings…"
mkdir -p android
touch android/gradle.properties
grep -q '^android.aapt2FromMavenOverride=' android/gradle.properties || \
  echo "android.aapt2FromMavenOverride=\$PREFIX/bin/aapt2" >> android/gradle.properties
grep -q '^android.enableResourceOptimizations=' android/gradle.properties || \
  echo "android.enableResourceOptimizations=false" >> android/gradle.properties

if [ -f android/app/build.gradle.kts ]; then
  sed -i -E 's/compileSdk[[:space:]]*=[[:space:]]*.*/compileSdk = 34/' android/app/build.gradle.kts
  sed -i -E 's/targetSdk[[:space:]]*=[[:space:]]*.*/targetSdk = 34/' android/app/build.gradle.kts
  if ! grep -q 'abiFilters.*arm64-v8a' android/app/build.gradle.kts; then
    sed -i '/defaultConfig[[:space:]]*{/a\\        ndk { abiFilters += listOf("arm64-v8a") }' android/app/build.gradle.kts
  fi
elif [ -f android/app/build.gradle ]; then
  sed -i -E 's/compileSdkVersion[[:space:]]+.*/compileSdkVersion 34/' android/app/build.gradle
  sed -i -E 's/targetSdkVersion[[:space:]]+.*/targetSdkVersion 34/' android/app/build.gradle
  if ! grep -q "abiFilters.*arm64-v8a" android/app/build.gradle; then
    sed -i "/defaultConfig[[:space:]]*{/a\\        ndk { abiFilters 'arm64-v8a' }" android/app/build.gradle
  fi
fi

nexus_phase "Resolving Flutter dependencies…"
if ! flutter pub get --offline; then
  nexus_phase "Some dependencies are not cached; trying online resolution…"
  flutter pub get
fi

nexus_phase "Analyzing project…"
flutter analyze --no-fatal-infos --no-fatal-warnings

if [ -d test ] && find test -type f -name '*_test.dart' | grep -q .; then
  nexus_phase "Running Flutter tests…"
  flutter test
fi

nexus_phase "Building ARM64 debug APK on this phone…"
flutter build apk --debug --target-platform android-arm64 --no-tree-shake-icons

APK="build/app/outputs/flutter-apk/app-debug.apk"
test -f "\$APK"
nexus_phase "Returning APK to Nexus…"
curl -fsS -X POST -H "X-Nexus-Token: \$NEXUS_TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"\$APK" "\$NEXUS_BASE/artifact" >/dev/null

nexus_complete true 0 "Phone-local Flutter build passed"
''';
}

class _PhoneRunnerSession {
  const _PhoneRunnerSession({
    required this.id,
    required this.token,
    required this.port,
  });

  final String id;
  final String token;
  final int port;
}
