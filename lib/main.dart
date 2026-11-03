import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/drox_app.dart';
import 'notifications/download_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FileDownloader().configure(androidConfig: [
    (Config.runInForeground, Config.always),
    (Config.useCacheDir, Config.never),
  ]);
  final prefs = await SharedPreferences.getInstance();
  configureDroxNotifications(prefs.getBool('drox_notifications_enabled') ?? true, bangla: prefs.getBool('drox_language_bangla_v2') ?? false);

  runApp(const DroxApp());
}

