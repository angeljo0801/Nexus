import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/services/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusApp());
  try {
    await NexusBackupService.autoBackupIfDue();
  } catch (_) {}
}
