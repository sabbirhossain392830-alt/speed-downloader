import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/download_home.dart';
import '../shared/widgets/drox_widgets.dart';

class DroxApp extends StatefulWidget {
  const DroxApp({super.key});
  @override
  State<DroxApp> createState() => _DroxAppState();
}

class _DroxAppState extends State<DroxApp> {
  ThemeMode mode = ThemeMode.light;
  bool isBangla = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isBangla = prefs.getBool('drox_language_bangla_v2') ?? false;
      mode = (prefs.getBool('drox_dark_mode') ?? false) ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme() async {
    final nextMode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() => mode = nextMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drox_dark_mode', nextMode == ThemeMode.dark);
  }

  Future<void> _setLanguage(bool value) async {
    setState(() => isBangla = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drox_language_bangla_v2', value);
    final notifications = prefs.getBool('drox_notifications_enabled') ?? true;
    _configureDroxNotifications(notifications, bangla: value);
  }

  @override
  Widget build(BuildContext context) {
    const liquidBrown = Color(0xFF6B351B);
    const darkAccent = Color(0xFF4FC3F7);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DROX',
      themeMode: mode,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        colorScheme: ColorScheme.fromSeed(seedColor: liquidBrown, surface: const Color(0xFFFFFFFF)),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF6B351B), foregroundColor: Color(0xFFFFFFFF), elevation: 0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF202020),
        colorScheme: ColorScheme.fromSeed(seedColor: darkAccent, brightness: Brightness.dark, surface: const Color(0xFF303030)),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: darkAccent, foregroundColor: Color(0xFF101820)),
        snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xFF263238), contentTextStyle: TextStyle(color: Colors.white)),
        
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF151A22), foregroundColor: Color(0xFFF5F7FA), elevation: 0),
      ),
      home: DownloadHome(
        isDark: mode == ThemeMode.dark,
        isBangla: isBangla,
        onLanguageChanged: _setLanguage,
        onThemeTap: _toggleTheme,
      ),
    );
  }
}

