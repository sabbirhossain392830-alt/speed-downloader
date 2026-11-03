// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

void _configureDroxNotifications(bool enabled, {bool bangla = false}) {
  FileDownloader().configureNotification(
    running: enabled
        ? TaskNotification(
            bangla ? 'DROX • ডাউনলোড হচ্ছে {progress}' : 'DROX • Downloading {progress}',
            '{filename}',
          )
        : null,
    paused: enabled
        ? TaskNotification(bangla ? 'DROX • বিরতি' : 'DROX • Paused', '{filename} • {progress}')
        : null,
    complete: enabled
        ? TaskNotification(bangla ? 'DROX • ডাউনলোড সম্পন্ন' : 'DROX • Download complete', '{filename}')
        : null,
    error: enabled
        ? TaskNotification(bangla ? 'DROX • ডাউনলোড ব্যর্থ' : 'DROX • Download failed', '{filename}')
        : null,
    progressBar: enabled,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FileDownloader().start();
  final prefs = await SharedPreferences.getInstance();
  _configureDroxNotifications(prefs.getBool('drox_notifications_enabled') ?? true, bangla: prefs.getBool('drox_language_bangla_v2') ?? false);

  runApp(const DroxApp());
}

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

class DroxAnimatedSwitch extends StatelessWidget {
  const DroxAnimatedSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = dark ? const Color(0xFF4FC3F7) : const Color(0xFF6B351B);
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: 54,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? activeColor : (dark ? const Color(0xFF555555) : const Color(0xFFD8D8D8)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: value ? Colors.white : (dark ? const Color(0xFFBDBDBD) : Colors.white),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .20), blurRadius: 3, offset: const Offset(0, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DroxLogoMark extends StatelessWidget {
  const DroxLogoMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFF7F6F3),
      borderRadius: BorderRadius.circular(size * .27),
      border: Border.all(color: const Color(0xFFE8E5E0)),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: size * .20, offset: const Offset(0, 3)),
      ],
    ),
    child: CustomPaint(painter: _DroxWingPainter(), size: Size(size, size)),
  );
}

class _DroxWingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 44);
    final orange = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9DA5AA), Color(0xFFD0D2D1), Color(0xFFC47A50), Color(0xFF858D93)],
      ).createShader(const Rect.fromLTWH(0, 0, 44, 44))
      ..style = PaintingStyle.fill;
    final upper = Path()
      ..moveTo(9, 28)
      ..cubicTo(8, 27, 8, 25, 10, 23)
      ..lineTo(31, 5)
      ..cubicTo(33, 3, 37, 4, 36, 7)
      ..lineTo(17, 30)
      ..cubicTo(15, 33, 12, 32, 9, 28)
      ..close();
    final lower = Path()
      ..moveTo(16, 31)
      ..cubicTo(17, 29, 18, 27, 20, 25)
      ..lineTo(33, 14)
      ..cubicTo(36, 12, 39, 14, 36, 17)
      ..lineTo(27, 26)
      ..cubicTo(25, 28, 26, 30, 28, 32)
      ..lineTo(39, 39)
      ..cubicTo(40, 40, 39, 42, 36, 42)
      ..lineTo(25, 41)
      ..cubicTo(22, 41, 20, 39, 18, 37)
      ..lineTo(11, 32)
      ..cubicTo(10, 31, 13, 29, 16, 31)
      ..close();
    canvas.drawPath(upper, orange);
    canvas.drawPath(lower, orange);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DroxDownloadProgress extends StatelessWidget {
  const DroxDownloadProgress({super.key, required this.progress, required this.isDark});
  final double progress;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? Colors.white : Colors.black;
    return ClipRect(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _DroxDownloadStripePainter(
            progress: progress.clamp(0.0, 1.0),
            stripeColor: ink,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

class _DroxDownloadStripePainter extends CustomPainter {
  const _DroxDownloadStripePainter({
    required this.progress,
    required this.stripeColor,
    required this.isDark,
  });

  final double progress;
  final Color stripeColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // A very subtle track keeps the row clean without looking like a thick bar.
    final track = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .025 : .018);
    canvas.drawRect(Offset.zero & size, track);

    final filledWidth = size.width * progress;
    if (filledWidth <= 0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, filledWidth, size.height));

    final fill = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .055 : .035);
    canvas.drawRect(Rect.fromLTWH(0, 0, filledWidth, size.height), fill);

    // Static, fine pinstripes: only the progress boundary moves as bytes download.
    final stripe = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .48 : .42);
    const stripeWidth = 1.0;
    const spacing = 38.0;
    for (double x = 0; x < filledWidth; x += spacing) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripeWidth, size.height), stripe);
    }

    final edge = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .72 : .62);
    canvas.drawRect(
      Rect.fromLTWH((filledWidth - 1).clamp(0.0, size.width), 0, 1, size.height),
      edge,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DroxDownloadStripePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.stripeColor != stripeColor ||
      oldDelegate.isDark != isDark;
}

class DownloadEntry {
  DownloadEntry(this.task);
  final DownloadTask task;
  double progress = 0;
  int expectedFileSize = -1;
  String status = 'কিউতে আছে';
  String? error;
  String? sharedPath;
  int lastDownloadedBytes = 0;
  DateTime? lastSpeedSampleAt;
  double speedBytesPerSecond = 0;
}

enum DownloadFilter { all, active, completed, failed, scheduled }

class DownloadHome extends StatefulWidget {
  const DownloadHome({super.key, required this.isDark, required this.isBangla, required this.onLanguageChanged, required this.onThemeTap});
  final bool isDark;
  final bool isBangla;
  final ValueChanged<bool> onLanguageChanged;
  final VoidCallback onThemeTap;
  @override
  State<DownloadHome> createState() => _DownloadHomeState();
}

class _DownloadHomeState extends State<DownloadHome> {
  String _tr(String english, String bangla) => widget.isBangla ? bangla : english;

  String _localizedStatus(String value) {
    const labels = {
      'কিউতে আছে': ['Queued', 'কিউতে আছে'],
      'ডাউনলোড হচ্ছে': ['Downloading', 'ডাউনলোড হচ্ছে'],
      'আবার চেষ্টা করছে': ['Retrying', 'আবার চেষ্টা করছে'],
      'সম্পন্ন': ['Completed', 'সম্পন্ন'],
      'বিরতি': ['Paused', 'বিরতি'],
      'বাতিল': ['Cancelled', 'বাতিল'],
      'ব্যর্থ': ['Failed', 'ব্যর্থ'],
      'ফাইল পাওয়া যায়নি': ['File not found', 'ফাইল পাওয়া যায়নি'],
      'কিউতে যোগ করা যায়নি': ['Could not queue', 'কিউতে যোগ করা যায়নি'],
      'যাচাই হচ্ছে': ['Verifying', 'যাচাই হচ্ছে'],
      'যাচাই ব্যর্থ': ['Verification failed', 'যাচাই ব্যর্থ'],
      'নির্ধারিত': ['Scheduled', 'নির্ধারিত'],
    };
    final pair = labels[value];
    return pair == null ? (widget.isBangla ? value : (RegExp(r'[\\u0980-\\u09FF]').hasMatch(value) ? 'Status unavailable' : value)) : pair[widget.isBangla ? 1 : 0];
  }

  String _localizedError(String value) {
    if (widget.isBangla) return value;
    const translations = {
      'ডাউনলোড ব্যর্থ': 'Download failed',
      'ডাউনলোড করা ফাইল পাওয়া যায়নি': 'Downloaded file not found',
      'ফাইলটি খালি—ডাউনলোড সম্পূর্ণ হয়নি': 'The file is empty; the download is incomplete',
      'ফাইলের সাইজ অসম্পূর্ণ': 'The downloaded file is incomplete',
      'সার্ভার তথ্য যাচাই করতে দেয়নি': 'The server did not allow information verification',
      'সার্ভার থেকে ফাইলের তথ্য পাওয়া যায়নি': 'Could not retrieve file information from the server',
      'সঠিক HTTP/HTTPS direct link দিন': 'Enter a valid HTTP/HTTPS direct link',
      'সার্ভার ভিডিওর বদলে HTML/Cloudflare পেজ পাঠিয়েছে': 'The server returned an HTML/Cloudflare page instead of a video',
      'সার্ভার ডাউনলোড লিংক অনুমোদন করেনি': 'The server did not authorize the download link',
      'সার্ভার লিংকটি অনুমোদন করেনি': 'The server did not authorize this link',
      'এটি সরাসরি মিডিয়া ফাইল নয়—সার্ভার HTML/Cloudflare পেজ পাঠাচ্ছে': 'This is not a direct media file; the server returned an HTML/Cloudflare page',
    };
    return translations[value] ?? (RegExp(r'[\\u0980-\\u09FF]').hasMatch(value) ? 'Download error. Please try again.' : value);
  }

  Future<void> _showLanguageDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Choose language', 'ভাষা নির্বাচন করুন')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioListTile<bool>(
            value: true, groupValue: widget.isBangla, title: const Text('বাংলা'),
            onChanged: (v) { if (v != null) { widget.onLanguageChanged(v); Navigator.pop(ctx); } },
          ),
          RadioListTile<bool>(
            value: false, groupValue: widget.isBangla, title: const Text('English'),
            onChanged: (v) { if (v != null) { widget.onLanguageChanged(v); Navigator.pop(ctx); } },
          ),
        ]),
      ),
    );
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const DroxLogoMark(size: 58),
        title: const Center(child: Text('DROX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4))),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Text(_tr('Download Manager & Browser', 'ডাউনলোড ম্যানেজার ও ব্রাউজার'), style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          _aboutRow(_tr('Version', 'ভার্সন'), info.version),
          _aboutRow(_tr('Build', 'বিল্ড'), info.buildNumber),
          const Divider(height: 18),
          Text(_tr(
            'DROX helps you download files, track progress, manage completed downloads and browse the web in one app.',
            'DROX দিয়ে ফাইল ডাউনলোড, অগ্রগতি দেখা, সম্পন্ন ফাইল পরিচালনা এবং একই অ্যাপে ওয়েব ব্রাউজ করা যায়।',
          )),
          const SizedBox(height: 10),
          Text(_tr('Features', 'সুবিধাসমূহ'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(_tr(
            '• Download queue and progress\n• Pause, resume and retry\n• File search and sorting\n• Built-in browser\n• Wi-Fi-only download option',
            '• ডাউনলোড তালিকা ও অগ্রগতি\n• Pause, Resume ও Retry\n• ফাইল খোঁজা ও সাজানো\n• বিল্ট-ইন ব্রাউজার\n• শুধু Wi-Fi দিয়ে ডাউনলোড',
          )),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_tr('Close', 'বন্ধ করুন')))],
      ),
    );
  }

  Widget _aboutRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      SizedBox(width: 82, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
      Expanded(child: Text(value)),
    ]),
  );

  static const MethodChannel _shareMethod = MethodChannel('drox/share');
  static const EventChannel _shareEvents = EventChannel('drox/share_events');
  StreamSubscription<dynamic>? _shareSubscription;

  Future<void> _acceptSharedText(String? text) async {
    if (text == null || text.trim().isEmpty || !mounted) return;
    final match = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(text);
    final shared = (match?.group(0) ?? '').replaceAll(RegExp(r'[),.;]+$'), '');
    if (shared.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('No HTTP/HTTPS link found in the shared text', 'শেয়ার করা লেখায় কোনো HTTP/HTTPS লিংক পাওয়া যায়নি'))),
      );
      return;
    }
    setState(() {
      selectedTab = 0;
      controller.text = shared;
    });
    await _add();
  }

  final controller = TextEditingController();
  final List<DownloadEntry> entries = [];
  StreamSubscription<TaskUpdate>? subscription;
  DownloadFilter filter = DownloadFilter.all;
  bool searching = false;
  final TextEditingController searchController = TextEditingController();
  bool adding = false;
  bool wifiOnly = false;
  bool notificationsEnabled = true;
  int selectedTab = 0;
  final GlobalKey<_BrowserPageState> browserKey = GlobalKey<_BrowserPageState>();
  static const _historyKey = 'drox_download_history';

  Future<void> _loadNotificationSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('drox_notifications_enabled') ?? true;
    if (mounted) setState(() => notificationsEnabled = enabled);
    _configureDroxNotifications(enabled, bangla: widget.isBangla);
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (enabled) {
      var status = await FileDownloader().permissions.status(PermissionType.notifications);
      if (status != PermissionStatus.granted) {
        status = await FileDownloader().permissions.request(PermissionType.notifications);
      }
      if (status != PermissionStatus.granted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Allow notifications to receive download alerts', 'ডাউনলোডের নোটিফিকেশন পেতে অনুমতি দিন'))));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drox_notifications_enabled', enabled);
    _configureDroxNotifications(enabled);
    if (mounted) setState(() => notificationsEnabled = enabled);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? _tr('Download notifications enabled', 'ডাউনলোড নোটিফিকেশন চালু হয়েছে') : _tr('Download notifications disabled', 'ডাউনলোড নোটিফিকেশন বন্ধ হয়েছে'))));
  }

  Future<void> _loadWifiOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('drox_wifi_only') ?? false;
    if (mounted) setState(() => wifiOnly = enabled);
    await FileDownloader().requireWiFi(enabled ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks);
  }

  Future<void> _setWifiOnly(bool enabled) async {
    setState(() => wifiOnly = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drox_wifi_only', enabled);
    await FileDownloader().requireWiFi(enabled ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? _tr('Downloads will use Wi-Fi only', 'শুধু Wi‑Fi দিয়ে ডাউনলোড হবে') : _tr('Downloads can use mobile data', 'মোবাইল ডেটাতেও ডাউনলোড হবে'))));
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = entries.map((e) => {
      'taskId': e.task.taskId,
      'url': e.task.url,
      'filename': e.task.filename,
      'progress': e.progress,
      'expectedFileSize': e.expectedFileSize,
      'status': e.status,
      'error': e.error,
      'sharedPath': e.sharedPath,
    }).toList();
    await prefs.setString(_historyKey, jsonEncode(data));
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    final restored = <DownloadEntry>[];
    final restoredIds = <String>{};

    // Reconnect to the downloader's native persistent records. Recreating a
    // DownloadTask from only its URL gives it a new task ID and breaks Resume.
    try {
      final records = await FileDownloader().database.allRecords();
      for (final record in records) {
        if (record.task is! DownloadTask) continue;
        final task = record.task as DownloadTask;
        final entry = DownloadEntry(task)
          ..progress = record.progress.clamp(0.0, 1.0)
          ..expectedFileSize = record.expectedFileSize
          ..status = _statusText(record.status);
        if (record.status == TaskStatus.complete) {
          entry.progress = 1;
          entry.status = 'সম্পন্ন';
        }
        restored.add(entry);
        restoredIds.add(task.taskId);
      }
    } catch (_) {
      // Keep the locally saved list available if the native task database
      // cannot be read on this device.
    }

    // Merge older history entries that predate native task-record restoration.
    if (raw != null) {
      try {
        final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final item in data) {
          final id = item['taskId'] as String?;
          if (id != null && restoredIds.contains(id)) continue;
          final task = DownloadTask(
            url: item['url'] as String,
            filename: item['filename'] as String,
            directory: 'DROX',
            baseDirectory: BaseDirectory.applicationSupport,
            updates: Updates.statusAndProgress,
            allowPause: true,
            retries: 3,
            taskId: id,
          );
          final entry = DownloadEntry(task)
            ..progress = (item['progress'] as num?)?.toDouble() ?? 0
            ..expectedFileSize = (item['expectedFileSize'] as num?)?.toInt() ?? -1
            ..status = (item['status'] as String?) ?? 'ইতিহাসে সংরক্ষিত'
            ..error = item['error'] as String?
            ..sharedPath = item['sharedPath'] as String?;
          // If a native record is missing, do not falsely claim the old
          // worker is still active. The Resume action can safely retry it.
          if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে'].contains(entry.status)) {
            entry.status = 'বিরতি';
          }
          restored.add(entry);
        }
      } catch (_) {
        // Do not delete the history on a transient parse/database issue.
      }
    }

    // Completed downloads may not have received a Content-Length header.
    // Read the actual saved file size so history never shows "Size unknown".
    for (final entry in restored) {
      if (entry.status != 'সম্পন্ন' || entry.expectedFileSize > 0) continue;
      try {
        final file = File(await entry.task.filePath());
        if (await file.exists()) {
          entry.expectedFileSize = await file.length();
          entry.progress = 1;
        }
      } catch (_) {
        // Keep the saved history entry if the file is not currently accessible.
      }
    }

    if (mounted) {
      setState(() {
        entries
          ..clear()
          ..addAll(restored);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWifiOnly();
    _loadNotificationSetting();
    subscription = FileDownloader().updates.listen(_onUpdate);
    _shareSubscription = _shareEvents.receiveBroadcastStream().listen((value) => _acceptSharedText(value?.toString()));
    _shareMethod.invokeMethod<String>('getInitialSharedText').then(_acceptSharedText).catchError((_) {});
    FileDownloader().resumeFromBackground();
    _loadHistory();
  }

  void _onUpdate(TaskUpdate update) {
    final index = entries.indexWhere((e) => e.task.taskId == update.task.taskId);
    if (index < 0) return;
    setState(() {
      final entry = entries[index];
      if (update is TaskProgressUpdate) {
        entry.progress = update.progress.clamp(0.0, 1.0);
        if (update.hasExpectedFileSize) entry.expectedFileSize = update.expectedFileSize;
        if (entry.expectedFileSize > 0) {
          final now = DateTime.now();
          final downloaded = (entry.progress * entry.expectedFileSize).round();
          final previousAt = entry.lastSpeedSampleAt;
          if (previousAt != null) {
            final elapsed = now.difference(previousAt).inMilliseconds / 1000;
            if (elapsed >= 0.5) {
              entry.speedBytesPerSecond = ((downloaded - entry.lastDownloadedBytes) / elapsed).clamp(0, double.infinity);
              entry.lastDownloadedBytes = downloaded;
              entry.lastSpeedSampleAt = now;
            }
          } else {
            entry.lastDownloadedBytes = downloaded;
            entry.lastSpeedSampleAt = now;
          }
        }
      } else if (update is TaskStatusUpdate) {
        if (update.status == TaskStatus.complete) {
          entry.status = 'ফাইল যাচাই হচ্ছে';
          entry.progress = 1;
          entry.error = null;
          _verifyCompletedFile(entry);
        } else {
          entry.status = _statusText(update.status);
          if (update.status != TaskStatus.running) entry.speedBytesPerSecond = 0;
          if (update.status == TaskStatus.failed) {
            entry.error = update.exception?.description ?? 'ডাউনলোড ব্যর্থ';
          }
        }
      }
    });
    _saveHistory();
  }

  Future<void> _verifyCompletedFile(DownloadEntry entry) async {
    try {
      final path = await entry.task.filePath();
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('ডাউনলোড করা ফাইল পাওয়া যায়নি');
      }
      final actualSize = await file.length();
      if (actualSize <= 0) {
        throw Exception('ফাইলটি খালি—ডাউনলোড সম্পূর্ণ হয়নি');
      }
      // Preserve integrity checks when the server reports a size.
      // If it does not, use the actual saved file length for the UI.
      final reportedSize = entry.expectedFileSize;
      if (reportedSize > 0 && actualSize != reportedSize) {
        throw Exception('ফাইলের সাইজ অসম্পূর্ণ');
      }
      entry.expectedFileSize = actualSize;
      if (!mounted) return;
      setState(() {
        entry.status = 'সম্পন্ন';
        entry.progress = 1;
        entry.error = null;
      });
      await _publishToPhone(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        entry.status = 'যাচাই ব্যর্থ';
        entry.error = e.toString().replaceFirst('Exception: ', '');
      });
    }
    await _saveHistory();
  }

  String _statusText(TaskStatus s) {
    switch (s) {
      case TaskStatus.enqueued: return 'কিউতে আছে';
      case TaskStatus.running: return 'ডাউনলোড হচ্ছে';
      case TaskStatus.complete: return 'সম্পন্ন';
      case TaskStatus.paused: return 'বিরতি';
      case TaskStatus.canceled: return 'বাতিল';
      case TaskStatus.failed: return 'ব্যর্থ';
      case TaskStatus.notFound: return 'ফাইল পাওয়া যায়নি';
      case TaskStatus.waitingToRetry: return 'আবার চেষ্টা করছে';
    }
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_').trim();
    return cleaned.isEmpty ? 'drox_download.bin' : cleaned;
  }

  String _fileName(String url) {
    final uri = Uri.tryParse(url);
    final last = uri == null || uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    String decoded;
    try { decoded = Uri.decodeComponent(last); } catch (_) { decoded = last; }
    return decoded.contains('.') ? _safeFileName(decoded) : 'drox_' + DateTime.now().millisecondsSinceEpoch.toString() + '.bin';
  }

  String? _extensionForMime(String? contentType) {
    final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
    const extensions = <String, String>{
      'application/pdf': 'pdf',
      'application/zip': 'zip',
      'application/x-rar-compressed': 'rar',
      'application/vnd.rar': 'rar',
      'application/x-7z-compressed': '7z',
      'application/vnd.android.package-archive': 'apk',
      'video/mp4': 'mp4',
      'video/webm': 'webm',
      'video/x-matroska': 'mkv',
      'video/quicktime': 'mov',
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/aac': 'aac',
      'audio/wav': 'wav',
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'text/plain': 'txt',
      'application/msword': 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
      'application/vnd.ms-excel': 'xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
      'application/vnd.ms-powerpoint': 'ppt',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
    };
    return extensions[mime];
  }

  Future<(String, String)> _downloadDetails(String url) async {
    var finalUrl = url;
    var filename = _fileName(url);
    final dio = Dio(BaseOptions(
      followRedirects: true,
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    ));
    Response<dynamic>? response;
    // HEAD reads metadata only; do not probe with GET because some servers
    // ignore Range and may send the entire file.
    try {
      response = await dio.head(url);
    } catch (_) {
      response = null;
    }
    if (response != null) {
      final responseType = (response.headers.value('content-type') ?? '').toLowerCase();
      if ((response.statusCode ?? 200) >= 400 || responseType.contains('text/html')) {
        throw Exception(responseType.contains('text/html')
            ? 'সার্ভার ভিডিওর বদলে HTML/Cloudflare পেজ পাঠিয়েছে'
            : 'সার্ভার ডাউনলোড লিংক অনুমোদন করেনি (HTTP ${response.statusCode})');
      }
      final redirected = response.realUri.toString();
      if (redirected.startsWith('http')) finalUrl = redirected;
      final disposition = response.headers.value('content-disposition') ?? '';
      // RFC 5987 filename*=UTF-8''... takes precedence over filename=...
      final encoded = RegExp(
        r"filename\*\s*=\s*(?:UTF-8'')?([^;]+)",
        caseSensitive: false,
      ).firstMatch(disposition);
      final plain = RegExp(
        r'filename\s*=\s*"([^"]+)"|filename\s*=\s*([^;]+)',
        caseSensitive: false,
      ).firstMatch(disposition);
      final headerName = encoded?.group(1) ?? plain?.group(1) ?? plain?.group(2);
      if (headerName != null && headerName.trim().isNotEmpty) {
        final rawName = headerName.trim().replaceAll('"', '');
        try {
          filename = _safeFileName(Uri.decodeComponent(rawName));
        } catch (_) {
          filename = _safeFileName(rawName);
        }
      } else {
        final path = response.realUri.pathSegments.isEmpty
            ? ''
            : response.realUri.pathSegments.last;
        if (path.contains('.')) {
          try {
            filename = _safeFileName(Uri.decodeComponent(path));
          } catch (_) {
            filename = _safeFileName(path);
          }
        } else {
          final extension = _extensionForMime(response.headers.value('content-type'));
          if (extension != null) {
            final base = filename.replaceFirst(RegExp(r'\.bin$', caseSensitive: false), '');
            filename = _safeFileName('$base.$extension');
          }
        }
      }
    }
    return (finalUrl, filename);
  }

  Future<void> _add() async {
    if (adding) return;
    final value = controller.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সঠিক HTTP/HTTPS direct link দিন')));
      return;
    }
    setState(() => adding = true);
    late final (String, String) details;
    try {
      details = await _downloadDetails(value);
    } catch (e) {
      if (mounted) {
        setState(() => adding = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 6),
        ));
      }
      return;
    }
    final task = DownloadTask(
      url: details.$1,
      filename: details.$2,
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      transferHints: {TransferHint.largeFile},
      retries: 10,
    );
    setState(() {
      entries.insert(0, DownloadEntry(task));
      controller.clear();
    });
    _saveHistory();
    try {
      // Transfer API hands offline tasks to Android's native scheduler so
      // they can start when connectivity returns, even if DROX is closed.
      await FileDownloader().transfers.start(task);
    } catch (_) {
      if (mounted) {
        final index = entries.indexWhere((e) => e.task.taskId == task.taskId);
        if (index >= 0) setState(() => entries[index].status = 'কিউতে যোগ করা যায়নি');
      }
    }
    _saveHistory();
    if (mounted) setState(() => adding = false);
  }

  Future<void> _pause(DownloadEntry entry) async {
    final ok = await FileDownloader().pause(entry.task);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('This server may not support Pause/Resume', 'এই সার্ভার Pause/Resume সমর্থন নাও করতে পারে'))));
    }
  }

  Future<void> _resume(DownloadEntry entry) async {
    var ok = false;
    try {
      // First resume the exact persisted native task so its partial file and
      // HTTP Range state are retained.
      ok = await FileDownloader().resume(entry.task);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      // If the OS removed the partial worker record, enqueue a fresh task
      // rather than leaving a dead Resume button on screen.
      final retryTask = DownloadTask(
        url: entry.task.url,
        filename: entry.task.filename,
        directory: 'DROX',
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 10,
      );
      final replacement = DownloadEntry(retryTask);
      final index = entries.indexWhere((e) => e.task.taskId == entry.task.taskId);
      if (index >= 0 && mounted) {
        setState(() => entries[index] = replacement);
        await _saveHistory();
      }
      try {
        await FileDownloader().transfers.start(retryTask);
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!ok && mounted) {
        setState(() => replacement.status = 'ব্যর্থ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('Could not restart this download. Check the link and try again.', 'ডাউনলোডটি আবার চালু করা যায়নি। লিংক যাচাই করে চেষ্টা করুন।'))),
        );
      }
    }
    await _saveHistory();
  }

  Future<void> _cancel(DownloadEntry entry) async {
    await FileDownloader().cancelTaskWithId(entry.task.taskId);
  }

  Future<void> _publishToPhone(DownloadEntry entry) async {
    if (entry.sharedPath != null) return;
    try {
      final path = await FileDownloader().moveToSharedStorage(entry.task, SharedStorage.downloads, directory: 'DROX');
      if (path != null) { entry.sharedPath = path; await _saveHistory(); if (mounted) setState(() {}); }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Could not copy the file to the phone Downloads folder', 'ফোনের Downloads ফোল্ডারে কপি করা যায়নি'))));
    }
  }

  Future<void> _open(DownloadEntry entry) async {
    if (entry.status != 'সম্পন্ন') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('The file can be opened after the download completes', 'ডাউনলোড সম্পন্ন হলে ফাইল Open করা যাবে'))));
      return;
    }
    if (entry.sharedPath == null) await _publishToPhone(entry);
    final result = entry.sharedPath != null
        ? await FileDownloader().openFile(filePath: entry.sharedPath!)
        : await FileDownloader().openFile(task: entry.task);
    if (!result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Could not open the file', 'ফাইলটি খোলা যায়নি'))));
    }
  }

  Future<void> _redownload(DownloadEntry entry) async {
    final details = await _downloadDetails(entry.task.url);
    final task = DownloadTask(
      url: details.$1,
      filename: details.$2,
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      transferHints: {TransferHint.largeFile},
      retries: 10,
    );
    setState(() => entries.insert(0, DownloadEntry(task)));
    _saveHistory();
    try {
      await FileDownloader().transfers.start(task);
    } catch (_) {
      if (mounted) {
        final index = entries.indexWhere((e) => e.task.taskId == task.taskId);
        if (index >= 0) setState(() => entries[index].status = 'কিউতে যোগ করা যায়নি');
      }
    }
  }

  Future<void> _remove(DownloadEntry entry) async {
    if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(entry.status)) {
      await FileDownloader().cancelTaskWithId(entry.task.taskId);
    }
    if (mounted) setState(() => entries.removeWhere((e) => e.task.taskId == entry.task.taskId));
    _saveHistory();
  }

  bool _matches(DownloadEntry e) {
    final query = searchController.text.trim().toLowerCase();
    final nameMatches = query.isEmpty ||
        e.task.filename.toLowerCase().contains(query) ||
        e.task.url.toLowerCase().contains(query);
    if (!nameMatches) return false;
    switch (filter) {
      case DownloadFilter.all: return true;
      case DownloadFilter.active: return ['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(e.status);
      case DownloadFilter.completed: return e.status == 'সম্পন্ন';
      case DownloadFilter.failed: return ['ব্যর্থ', 'বাতিল', 'কিউতে যোগ করা যায়নি', 'যাচাই ব্যর্থ'].contains(e.status);
      case DownloadFilter.scheduled: return e.status == 'নির্ধারিত';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    searchController.dispose();
    subscription?.cancel();
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = entries.where((e) => ['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে'].contains(e.status)).length;
    final done = entries.where((e) => e.status == 'সম্পন্ন').length;
    final failed = entries.where((e) => ['ব্যর্থ', 'বাতিল', 'কিউতে যোগ করা যায়নি', 'যাচাই ব্যর্থ'].contains(e.status)).length;
    final visible = entries.where(_matches).toList();
    return PopScope(
      canPop: selectedTab == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (selectedTab == 1) {
          final handled = await browserKey.currentState?.handleSystemBack() ?? false;
          if (handled || !mounted) return;
        }
        if (selectedTab != 0) setState(() => selectedTab = 0);
      },
      child: Scaffold(
        appBar: selectedTab == 1 ? null : AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: const Text('DROX', style: TextStyle(fontWeight: FontWeight.w500, letterSpacing: .2, fontSize: 22)),
          actions: [
            IconButton(
              tooltip: _tr('Search downloads', 'ডাউনলোড খুঁজুন'),
              onPressed: () => setState(() {
                searching = !searching;
                if (!searching) searchController.clear();
              }),
              icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
            ),
            IconButton(
              tooltip: _tr('Sort downloads', 'ডাউনলোড সাজান'),
              onPressed: () => setState(() => entries.sort((a, b) => a.task.filename.toLowerCase().compareTo(b.task.filename.toLowerCase()))),
              icon: const Icon(Icons.sort_rounded),
            ),
            IconButton(
              tooltip: _tr('Browser', 'ব্রাউজার'),
              onPressed: () => setState(() => selectedTab = 1),
              icon: const Icon(Icons.public_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: _tr('Menu', 'মেনু'),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) async {
                switch (v) {
                  case 'settings':
                    setState(() => selectedTab = 3);
                    break;
                  case 'theme':
                    widget.onThemeTap();
                    break;
                  case 'language':
                    await _showLanguageDialog();
                    break;
                  case 'share':
                    try {
                      await _shareMethod.invokeMethod<void>('shareApp');
                    } on PlatformException catch (error) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_tr('Share failed: ${error.message ?? 'Unknown error'}', 'শেয়ার করা যায়নি: ${error.message ?? 'অজানা সমস্যা'}'))),
                      );
                    } on MissingPluginException {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_tr('Share is unavailable in this build. Please update the app.', 'এই বিল্ডে শেয়ার সুবিধা নেই। অ্যাপ আপডেট করুন।'))),
                      );
                    }
                    break;
                  case 'browser':
                    setState(() => selectedTab = 1);
                    break;
                  case 'notifications':
                    setState(() => selectedTab = 3);
                    break;
                  case 'wifi':
                    _setWifiOnly(!wifiOnly);
                    break;
                  case 'about':
                    await _showAbout();
                    break;
                  case 'sort':
                    setState(() => entries.sort((a, b) => a.task.filename.toLowerCase().compareTo(b.task.filename.toLowerCase())));
                    break;
                  case 'exit':
                    SystemNavigator.pop();
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: const Icon(Icons.settings_outlined), title: Text(_tr('Settings', 'সেটিংস')))),
                PopupMenuItem(value: 'theme', child: ListTile(dense: true, leading: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: Text(widget.isDark ? _tr('Light mode', 'লাইট মোড') : _tr('Dark mode', 'ডার্ক মোড')))),
                PopupMenuItem(value: 'language', child: ListTile(dense: true, leading: const Icon(Icons.language_rounded), title: Text(_tr('Language', 'ভাষা')))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'browser', child: ListTile(dense: true, leading: const Icon(Icons.public_rounded), title: Text(_tr('Browser', 'ব্রাউজার')))),
                PopupMenuItem(value: 'share', child: ListTile(dense: true, leading: const Icon(Icons.share_outlined), title: Text(_tr('Share the app', 'অ্যাপ শেয়ার করুন')))),
                PopupMenuItem(value: 'notifications', child: ListTile(dense: true, leading: const Icon(Icons.notifications_outlined), title: Text(_tr('Notification settings', 'নোটিফিকেশন সেটিংস')))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'wifi', child: ListTile(dense: true, leading: const Icon(Icons.wifi_rounded), title: Text(_tr('Wi-Fi only', 'শুধু Wi-Fi')), trailing: Icon(wifiOnly ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded))),
                PopupMenuItem(value: 'sort', child: ListTile(dense: true, leading: const Icon(Icons.sort_by_alpha_rounded), title: Text(_tr('Sort by name', 'নাম অনুযায়ী সাজান')))),
                PopupMenuItem(value: 'about', child: ListTile(dense: true, leading: const Icon(Icons.info_outline_rounded), title: Text(_tr('About', 'পরিচিতি')))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'exit', child: ListTile(dense: true, leading: const Icon(Icons.exit_to_app_rounded), title: Text(_tr('Exit', 'বন্ধ করুন')))),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(index: selectedTab, children: [
          Column(children: [
            Material(
              color: widget.isDark ? const Color(0xFF151A22) : const Color(0xFF6B351B),
              child: Row(children: [
                _homeCategory(_tr('ALL', 'সব'), entries.length, DownloadFilter.all, Icons.all_inbox_rounded),
                _homeCategory(_tr('DOWNLOADING', 'চলমান'), active, DownloadFilter.active, Icons.downloading_rounded),
                _homeCategory(_tr('FINISHED', 'সম্পন্ন'), done, DownloadFilter.completed, Icons.check_circle_outline_rounded),
                _homeCategory(_tr('ERROR', 'ত্রুটি'), failed, DownloadFilter.failed, Icons.error_outline_rounded),
              ]),
            ),
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 5),
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _tr('Search downloaded files', 'ডাউনলোড করা ফাইল খুঁজুন'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: _tr('Clear search', 'সার্চ মুছুন'),
                      onPressed: () { searchController.clear(); setState(() {}); },
                      icon: const Icon(Icons.close_rounded),
                    ),
                    isDense: true,
                    filled: true,
                    border: const OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? const SizedBox.expand()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 100),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => _downloadCard(visible[i]),
                    ),
            ),
          ]),
          BrowserPage(key: browserKey, isDark: widget.isDark, isBangla: widget.isBangla, onThemeTap: widget.onThemeTap, onReturn: () => setState(() => selectedTab = 0), onSettings: () => setState(() => selectedTab = 3), onDownload: (url) { controller.text = url; _add(); }),
          ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              Text('Downloads', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const Spacer(),
              Text('${entries.length} files'),
              IconButton(tooltip: _tr('Quick download', 'দ্রুত ডাউনলোড'), onPressed: _quickDownloadDialog, icon: const Icon(Icons.add_link_rounded)),
            ]),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              _filterChip(_tr('All', 'সব'), DownloadFilter.all), _filterChip(_tr('Active', 'চলমান'), DownloadFilter.active),
              _filterChip(_tr('Completed', 'সম্পন্ন'), DownloadFilter.completed), _filterChip(_tr('Failed', 'ব্যর্থ'), DownloadFilter.failed),
            ])),
            ...visible.map(_downloadCard),
          ]),
          ListView(padding: const EdgeInsets.all(16), children: [
            Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 12),
            Card(child: Column(children: [
              ListTile(leading: const Icon(Icons.palette_outlined), title: Text(_tr('Appearance', 'দেখতে কেমন হবে')), subtitle: Text(widget.isDark ? _tr('Dark theme', 'ডার্ক থিম') : _tr('Light theme', 'লাইট থিম')), trailing: DroxAnimatedSwitch(value: widget.isDark, onChanged: (_) => widget.onThemeTap())),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.wifi_rounded), title: Text(_tr('Wi-Fi only', 'শুধু Wi-Fi')), subtitle: Text(_tr('Prevent downloads on mobile data', 'মোবাইল ডেটায় ডাউনলোড বন্ধ রাখুন')), trailing: DroxAnimatedSwitch(value: wifiOnly, onChanged: _setWifiOnly)),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.language_rounded), title: Text(_tr('Language', 'ভাষা')), subtitle: Text(widget.isBangla ? 'বাংলা' : 'English'), onTap: _showLanguageDialog),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.notifications_active_outlined), title: Text(_tr('Download notifications', 'ডাউনলোড নোটিফিকেশন')), subtitle: Text(_tr('Show an alert when a download finishes', 'ডাউনলোড শেষ হলে নোটিফিকেশন বারে দেখাবে')), trailing: DroxAnimatedSwitch(value: notificationsEnabled, onChanged: _setNotificationsEnabled)),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.folder_outlined), title: Text(_tr('Download folder', 'ডাউনলোড ফোল্ডার')), subtitle: const Text('Phone storage / Downloads / DROX')),
            ])),
            const SizedBox(height: 18),
            ListTile(leading: Icon(Icons.info_outline), title: Text(_tr('About DROX', 'DROX পরিচিতি')), subtitle: Text(_tr('Browser and download manager', 'ব্রাউজার ও ডাউনলোড ম্যানেজার'))),
          ]),
        ]),
        floatingActionButton: selectedTab == 0
            ? FloatingActionButton(
                tooltip: 'Add download',
                backgroundColor: widget.isDark ? const Color(0xFF4FC3F7) : const Color(0xFF6B351B),
                foregroundColor: widget.isDark ? const Color(0xFF101820) : Colors.white,
                onPressed: _quickDownloadDialog,
                child: const Icon(Icons.add_rounded, size: 30),
              )
            : null,
      ),
    );
  }

  Widget _homeCategory(String label, int count, DownloadFilter value, IconData icon) {
    final selected = filter == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => filter = value),
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: selected ? (widget.isDark ? const Color(0xFF4FC3F7) : const Color(0xFF6B351B)) : Colors.transparent,
              width: 3,
            )),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: .05,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? (widget.isDark ? const Color(0xFF4FC3F7) : Colors.white)
                      : Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? (widget.isDark ? const Color(0xFF101820) : const Color(0xFF6B351B))
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _quickDownloadDialog() async {
    controller.clear();
    final value = await showDialog<String>(context: context, builder: (ctx) {
      final field = TextEditingController();
      return AlertDialog(
        title: Text(_tr('Quick download', 'দ্রুত ডাউনলোড')),
        content: TextField(controller: field, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Paste direct download URL')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, field.text.trim()), child: const Text('Download')),
        ],
      );
    });
    if (value != null && value.isNotEmpty && mounted) { controller.text = value; _add(); }
  }

  Widget _filterChip(String label, DownloadFilter value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(label: Text(label), selected: filter == value, onSelected: (_) => setState(() => filter = value)),
  );

  IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) return Icons.folder_zip_outlined;
    if (['.mp4', '.mkv', '.mov', '.avi', '.webm'].any(n.endsWith)) return Icons.video_file_outlined;
    if (['.mp3', '.wav', '.m4a', '.aac', '.flac'].any(n.endsWith)) return Icons.audio_file_outlined;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].any(n.endsWith)) return Icons.image_outlined;
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.apk')) return Icons.android_outlined;
    if (['.doc', '.docx', '.txt'].any(n.endsWith)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return _tr('Size unknown', 'সাইজ অজানা');
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return value >= 100 || unit == 0 ? '${value.toStringAsFixed(0)} ${units[unit]}' : '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB/s';
    if (bytesPerSecond >= 1024 * 1024) return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }

  Widget _downloadCard(DownloadEntry entry) {
    final running = entry.status == 'ডাউনলোড হচ্ছে';
    final paused = entry.status == 'বিরতি';
    final queued = ['কিউতে আছে', 'আবার চেষ্টা করছে'].contains(entry.status);
    final failed = ['ব্যর্থ', 'যাচাই ব্যর্থ', 'কিউতে যোগ করা যায়নি'].contains(entry.status);
    final completed = entry.status == 'সম্পন্ন';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : Colors.black;
    final progress = completed ? 1.0 : entry.progress.clamp(0.0, 1.0);
    final downloaded = entry.expectedFileSize > 0
        ? _formatBytes(completed ? entry.expectedFileSize : (progress * entry.expectedFileSize).round())
        : _formatBytes(0);
    final percent = completed ? '100' : (progress * 100).toStringAsFixed(0);
    final isVideo = RegExp(r'\.(mp4|mkv|avi|mov|webm|m4v|3gp)$', caseSensitive: false)
        .hasMatch(entry.task.filename);
    final speed = entry.speedBytesPerSecond;
    final etaSeconds = speed > 0 && entry.expectedFileSize > 0
        ? ((entry.expectedFileSize * (1 - progress)) / speed).round()
        : 0;
    String timeLabel(int seconds) {
      if (seconds <= 0) return '—';
      final minutes = seconds ~/ 60;
      final secs = seconds % 60;
      return minutes > 0 ? '${minutes}m${secs}s' : '${secs}s';
    }

    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: (isDark ? const Color(0xFF455A64) : const Color(0xFF8A5636)).withValues(alpha: isDark ? .95 : .72),
          width: 1.15,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (running || paused || queued)
            DroxDownloadProgress(progress: progress, isDark: isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 3, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Icon(
                    isVideo ? Icons.video_file_rounded : _fileIcon(entry.task.filename),
                    size: 39,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.task.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                          ),
                          Text(' (Resume: ', style: TextStyle(fontSize: 11, color: ink)),
                          Text(
                            'Yes',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF72B52D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(')', style: TextStyle(fontSize: 11, color: ink)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$percent% | $downloaded',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: ink),
                            ),
                          ),
                          if (running) ...[
                            Text(
                              '${_formatSpeed(speed)}  ${timeLabel(etaSeconds)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else
                            Text(
                              _localizedStatus(entry.status),
                              style: TextStyle(fontSize: 12, color: ink),
                            ),
                        ],
                      ),
                      if (failed && entry.error != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _localizedError(entry.error!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: ink),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                if (running)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _tr('Pause', 'বিরতি'),
                    onPressed: () => _pause(entry),
                    icon: Icon(Icons.pause_circle_outline_rounded, size: 32, color: ink),
                  )
                else if (paused || queued)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _tr('Resume', 'রিজিউম'),
                    onPressed: () => _resume(entry),
                    icon: Icon(Icons.play_circle_outline_rounded, size: 32, color: ink),
                  )
                else if (failed)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _tr('Retry', 'আবার চেষ্টা'),
                    onPressed: () => _redownload(entry),
                    icon: Icon(Icons.refresh_rounded, size: 30, color: ink),
                  )
                else if (completed)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _tr('Open folder', 'ফোল্ডার খুলুন'),
                    onPressed: () => _open(entry),
                    icon: Icon(Icons.folder_open_rounded, size: 28, color: ink),
                  ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 21,
                  iconColor: ink,
                  tooltip: _tr('More options', 'আরও অপশন'),
                  onSelected: (value) {
                    if (value == 'open') _open(entry);
                    if (value == 'redownload') _redownload(entry);
                    if (value == 'remove') _remove(entry);
                    if (value == 'cancel') _cancel(entry);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'open', enabled: completed, child: ListTile(dense: true, leading: const Icon(Icons.open_in_new), title: const Text('Open'))),
                    PopupMenuItem(value: 'redownload', child: ListTile(dense: true, leading: const Icon(Icons.refresh), title: const Text('Redownload'))),
                    if (running || paused || queued)
                      PopupMenuItem(value: 'cancel', child: ListTile(dense: true, leading: const Icon(Icons.close), title: const Text('Cancel'))),
                    PopupMenuItem(value: 'remove', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline), title: const Text('Remove'))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}


class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.onDownload, required this.isDark, required this.isBangla, required this.onThemeTap, required this.onReturn, required this.onSettings});
  final ValueChanged<String> onDownload;
  final bool isDark, isBangla;
  final VoidCallback onThemeTap, onReturn, onSettings;
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}
class _DroxTab {
  _DroxTab(this.controller, this.url);
  final WebViewController controller;
  String url;
  String title = 'New tab';
  bool loading = false, back = false, forward = false;
}
class _BrowserPageState extends State<BrowserPage> {
  final address = TextEditingController(text: 'https://www.google.com');
  final tabs = <_DroxTab>[];
  final history = <Map<String,String>>[];
  int active = 0;
  bool showHistory = false, adBlockEnabled = true, desktopMode = false;
  _DroxTab? get tab => tabs.isEmpty ? null : tabs[active];
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadBrowserSettings();
    _newTab();
  }

  Future<void> _loadBrowserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedAdBlock = prefs.getBool('drox_browser_adblock') ?? true;
    final savedDesktop = prefs.getBool('drox_browser_desktop_mode') ?? false;
    setState(() {
      adBlockEnabled = savedAdBlock;
      desktopMode = savedDesktop;
    });
    if (savedDesktop && tab != null) {
      await tab!.controller.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      await tab!.controller.reload();
    }
  }
  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString('drox_browser_history');
      if (raw != null) history.addAll((jsonDecode(raw) as List).cast<Map<String,dynamic>>().map((e) => <String,String>{'title': (e['title'] ?? '').toString(), 'url': (e['url'] ?? '').toString()}));
      if (mounted) setState(() {});
    } catch (_) {}
  }
  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('drox_browser_history', jsonEncode(history.take(100).toList()));
  }
  bool _isKnownAdUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    const blocked = ['doubleclick.net', 'googlesyndication.com', 'googleadservices.com', 'adservice.google.com', 'googletagmanager.com', 'adnxs.com', 'taboola.com', 'outbrain.com'];
    return blocked.any((domain) => host == domain || host.endsWith('.' + domain));
  }
  bool _downloadable(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(pdf|zip|rar|7z|apk|mp4|m4v|mkv|mov|avi|webm|ogv|3gp|mpeg|mpg|mp3|m4a|aac|wav|ogg|oga|opus|flac|m3u8|mpd|jpg|jpeg|png|gif|webp|bmp|tif|tiff|docx?|xlsx?|pptx?)$').hasMatch(path);
  }
  Future<void> _newTab([String url = 'https://www.google.com']) async {
    final t = _DroxTab(WebViewController(), url);
    tabs.add(t); active = tabs.length - 1; showHistory = false;
    final ctrl = t.controller;
    await ctrl.setJavaScriptMode(JavaScriptMode.unrestricted);
    await ctrl.addJavaScriptChannel('DroxDownload', onMessageReceived: (m) => _downloadPrompt(m.message));
    await ctrl.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (r) {
        if (_downloadable(r.url)) { _downloadPrompt(r.url); return NavigationDecision.prevent; }
        if (adBlockEnabled && _isKnownAdUrl(r.url)) return NavigationDecision.prevent;
        return NavigationDecision.navigate;
      },
      onPageStarted: (u) { t.url = u; t.loading = true; if (mounted) setState(() { if (tab == t) address.text = u; }); },
      onPageFinished: (u) async {
        t.url = u;
        await ctrl.runJavaScript(r'''(function(){
          if(window.__droxMediaDetector)return;window.__droxMediaDetector=true;
          var seen={};
          var exts=/\.(mp4|m4v|webm|mov|ogv|3gp|mpeg|mpg|mp3|m4a|aac|wav|ogg|oga|opus|flac|m3u8|mpd)(?:$|[?#])/i;
          var mediaTypes=/^(video\/|audio\/|application\/(vnd\.apple\.mpegurl|x-mpegurl|dash\+xml))/i;
          function valid(raw){try{var u=new URL(raw,location.href);return /^https?:$/.test(u.protocol)?u.href:null}catch(_){return null}}
          function send(raw){var u=valid(raw);if(!u||seen[u])return;seen[u]=1;DroxDownload.postMessage(u)}
          function mediaSources(v){var list=[v.currentSrc,v.src];v.querySelectorAll('source[src]').forEach(function(s){list.push(s.src)});list.forEach(function(u){if(u)send(u)})}
          function scan(){document.querySelectorAll('video,audio').forEach(function(v){
            if(!v.__droxBound){v.__droxBound=true;
              v.addEventListener('play',function(){mediaSources(v)});
              v.addEventListener('loadedmetadata',function(){mediaSources(v)});
              v.addEventListener('canplay',function(){mediaSources(v)});
              v.addEventListener('loadstart',function(){mediaSources(v)});
              v.addEventListener('emptied',function(){mediaSources(v)});
            }
            mediaSources(v);
          })}
          function scanResources(){try{performance.getEntriesByType('resource').forEach(function(e){if(exts.test(e.name))send(e.name)})}catch(_){}}
          function scanFrames(){document.querySelectorAll('iframe').forEach(function(f){try{if(f.contentDocument){f.contentDocument.querySelectorAll('video,audio').forEach(function(v){mediaSources(v)})}}catch(_){}})}
          if(window.fetch){var originalFetch=window.fetch;window.fetch=function(){var p=originalFetch.apply(this,arguments);try{var u=typeof arguments[0]==='string'?arguments[0]:arguments[0].url; p.then(function(r){var ct=r.headers.get('content-type')||'';var target=r.url||u;if(mediaTypes.test(ct)||exts.test(target||''))send(target)})}catch(_){}return p}}
          if(window.XMLHttpRequest){var originalOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){this.__droxUrl=u;return originalOpen.apply(this,arguments)};var originalSend=XMLHttpRequest.prototype.send;XMLHttpRequest.prototype.send=function(){this.addEventListener('load',function(){var ct=this.getResponseHeader('content-type')||'';if(mediaTypes.test(ct)||exts.test(this.__droxUrl||''))send(this.responseURL||this.__droxUrl)});return originalSend.apply(this,arguments)}}
          scan();new MutationObserver(function(){scan();scanResources();scanFrames()}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
          setInterval(function(){scan();scanResources();scanFrames()},2500);
          document.addEventListener('play',function(e){if(e.target&&(e.target.tagName==='VIDEO'||e.target.tagName==='AUDIO'))mediaSources(e.target)},true);
          document.addEventListener('click',function(e){var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;if(!a)return;try{var u=new URL(a.href,location.href);if(a.hasAttribute('download')||exts.test(u.pathname)){e.preventDefault();e.stopImmediatePropagation();send(u.href)}}catch(_){}},true);
        })();''');
        final title = await ctrl.getTitle();
        t.title = title == null || title.isEmpty ? (Uri.tryParse(u)?.host ?? 'Website') : title;
        t.loading = false; t.back = await ctrl.canGoBack(); t.forward = await ctrl.canGoForward();
        if (!mounted) return;
        setState(() { if (tab == t) address.text = u; });
        if (u.startsWith('http')) { history.removeWhere((e) => e['url'] == u); history.insert(0, {'title': t.title, 'url': u}); if (history.length > 100) history.removeLast(); _saveHistory(); }
      },
      onWebResourceError: (_) { t.loading = false; if (mounted) setState(() {}); },
    ));
    if (mounted) setState(() {});
    await ctrl.loadRequest(Uri.parse(url));
  }
  final Set<String> _promptedDownloadUrls = <String>{};
  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return widget.isBangla ? 'অজানা' : 'Unknown';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _downloadPrompt(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return;
    if (_promptedDownloadUrls.contains(url)) return;
    _promptedDownloadUrls.add(url);
    if (!mounted) { _promptedDownloadUrls.remove(url); return; }
    final wantsDownload = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.video_file_rounded, size: 42),
        title: const Text('ভিডিওটি ডাউনলোড করবেন?'),
        content: Text('এই ওয়েবসাইটে একটি ভিডিও পাওয়া গেছে।\n\n${uri.host}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('এখন নয়')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.download_rounded), label: const Text('হ্যাঁ, ডাউনলোড')),
        ],
      ),
    );
    if (wantsDownload != true || !mounted) {
      _promptedDownloadUrls.remove(url);
      return;
    }
    var finalUrl = url;
    var name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'media_file';
    try { name = Uri.decodeComponent(name); } catch (_) {}
    if (name.isEmpty || !name.contains('.')) name = 'media_file';
    var size = 'অজানা';
    var type = 'অজানা';
    var statusNote = '';
    try {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        validateStatus: (s) => s != null && s < 500,
      ));
      final response = await dio.head(url);
      final responseType = (response.headers.value('content-type') ?? '').toLowerCase();
      if ((response.statusCode ?? 200) >= 400) {
        statusNote = 'সার্ভার লিংকটি অনুমোদন করেনি (HTTP ${response.statusCode})';
      } else if (responseType.contains('text/html')) {
        statusNote = 'এটি সরাসরি মিডিয়া ফাইল নয়—সার্ভার HTML/Cloudflare পেজ পাঠাচ্ছে';
      } else {
        if (response.realUri.toString().startsWith('http')) finalUrl = response.realUri.toString();
        final length = int.tryParse(response.headers.value('content-length') ?? '');
        size = _formatFileSize(length);
        type = responseType.split(';').first.isEmpty ? 'অজানা' : responseType.split(';').first;
      }
      final disposition = response.headers.value('content-disposition') ?? '';
      final match = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(disposition);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        try { name = Uri.decodeComponent(match.group(1)!.trim().replaceAll('"', '').replaceAll("'", '')); } catch (_) { name = match.group(1)!.trim().replaceAll('"', '').replaceAll("'", ''); }
      }
      if (response.statusCode != null && response.statusCode! >= 400) statusNote = 'সার্ভার তথ্য যাচাই করতে দেয়নি';
    } catch (_) {
      statusNote = 'সার্ভার থেকে ফাইলের তথ্য পাওয়া যায়নি';
    }
    name = name.replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_');
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const DroxLogoMark(size: 50),
        title: const Center(child: Text('File Details', style: TextStyle(fontWeight: FontWeight.w800))),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(statusNote.isEmpty ? Icons.insert_drive_file_rounded : Icons.info_outline_rounded, color: Theme.of(ctx).colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 3, overflow: TextOverflow.ellipsis)),
            ]),
          ),
          const SizedBox(height: 14),
          _detailRow('ধরন', type),
          _detailRow('সাইজ', size),
          _detailRow('সাইট', uri.host),
          if (statusNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Text(statusNote, style: TextStyle(color: Theme.of(ctx).colorScheme.onErrorContainer, fontSize: 12))),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton.icon(onPressed: statusNote.isEmpty ? () => Navigator.pop(ctx, true) : null, icon: const Icon(Icons.download_rounded), label: const Text('Download')),
        ],
      ),
    );
    _promptedDownloadUrls.remove(url);
    if (approved == true && mounted) widget.onDownload(finalUrl);
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 58, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );
  void go() {
    var v = address.text.trim(); if (v.isEmpty || tab == null) return;
    if (!v.contains('://')) v = (v.contains(' ') || !v.contains('.')) ? 'https://www.google.com/search?q=' + Uri.encodeQueryComponent(v) : 'https://' + v;
    final uri = Uri.tryParse(v);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) { tab!.controller.loadRequest(uri); setState(() => showHistory = false); }
  }
  Future<bool> handleSystemBack() async {
    if (tab != null && await tab!.controller.canGoBack()) { await tab!.controller.goBack(); return true; }
    if (showHistory) { setState(() => showHistory = false); return true; }
    return false;
  }
  void _select(int i) { setState(() { active = i; address.text = tab?.url ?? ''; showHistory = false; }); }
  void _close(int i) {
    if (tabs.length == 1) { tabs.first.controller.loadRequest(Uri.parse('https://www.google.com')); return; }
    setState(() { tabs.removeAt(i); if (active >= tabs.length) active = tabs.length - 1; else if (i < active) active--; address.text = tab?.url ?? ''; });
  }
  void _showTabs() {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: SizedBox(height: 350, child: Column(children: [
      ListTile(title: Text('Open pages (' + tabs.length.toString() + ')'), trailing: IconButton(onPressed: () { Navigator.pop(ctx); _newTab(); }, icon: const Icon(Icons.add))),
      Expanded(child: ListView.builder(itemCount: tabs.length, itemBuilder: (_, i) => ListTile(selected: i == active, leading: const Icon(Icons.language), title: Text(tabs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(tabs[i].url, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () { Navigator.pop(ctx); _select(i); }, trailing: IconButton(onPressed: () { Navigator.pop(ctx); _close(i); }, icon: const Icon(Icons.close))))),
    ]))));
  }
  Future<void> _action(String v) async {
    switch (v) {
      case 'new': _newTab(); break;
      case 'adblock':
        setState(() => adBlockEnabled = !adBlockEnabled);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('drox_browser_adblock', adBlockEnabled);
        break;
      case 'refresh': tab?.controller.reload(); break;
      case 'history': setState(() => showHistory = true); break;
      case 'return': widget.onReturn(); break;
      case 'settings': widget.onSettings(); break;
      case 'dark': widget.onThemeTap(); break;
      case 'desktop':
        setState(() => desktopMode = !desktopMode);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('drox_browser_desktop_mode', desktopMode);
        await tab?.controller.setUserAgent(desktopMode ? 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' : null);
        tab?.controller.reload(); break;
      case 'about':
        if (mounted) showAboutDialog(context: context, applicationName: 'DROX', applicationVersion: '1.0', children: const [Text('Browser and download manager.')]);
        break;
    }
  }
  @override
  void dispose() { address.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final t = tab;
    return SafeArea(top: true, bottom: false, child: Column(children: [
      Material(color: cs.surface, elevation: 1, child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 6, 8), child: Row(children: [
        Material(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _showTabs,
            child: SizedBox(
              width: 42, height: 42,
              child: Center(child: Text('${tabs.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 46, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(28), border: Border.all(color: cs.outlineVariant.withValues(alpha: .35))), child: TextField(controller: address, onSubmitted: (_) => go(), textInputAction: TextInputAction.go, keyboardType: TextInputType.url, decoration: InputDecoration(hintText: 'Search', prefixIcon: const Icon(Icons.search_rounded, size: 20), suffixIcon: IconButton(onPressed: go, icon: const Icon(Icons.refresh_rounded, size: 22)), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 11), border: InputBorder.none)))),
        IconButton(
          tooltip: 'Downloads',
          onPressed: widget.onReturn,
          icon: const Icon(Icons.download_rounded),
        ),
        PopupMenuButton<String>(tooltip: 'Browser menu', icon: const Icon(Icons.more_vert), onSelected: _action, itemBuilder: (_) => [
          PopupMenuItem(value: 'new', child: ListTile(dense: true, leading: Icon(Icons.add_box_outlined), title: Text('New Tab'))),
          PopupMenuItem(value: 'adblock', child: ListTile(dense: true, leading: Icon(Icons.shield_outlined), title: Text('Ad Block'), trailing: IgnorePointer(child: DroxAnimatedSwitch(value: adBlockEnabled, onChanged: (_) {})))),
          PopupMenuItem(value: 'refresh', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Refresh'))),
          PopupMenuItem(value: 'history', child: ListTile(dense: true, leading: Icon(Icons.history), title: Text('History'))),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'return', child: ListTile(dense: true, leading: Icon(Icons.home_outlined), title: Text('Return to DROX'))),
          PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
          PopupMenuItem(value: 'dark', child: ListTile(dense: true, leading: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: const Text('Dark Mode'), trailing: Icon(widget.isDark ? Icons.check : Icons.circle_outlined))),
          PopupMenuItem(value: 'desktop', child: ListTile(dense: true, leading: const Icon(Icons.desktop_windows_outlined), title: const Text('Desktop Mode'), trailing: IgnorePointer(child: DroxAnimatedSwitch(value: desktopMode, onChanged: (_) {})))),
          PopupMenuItem(value: 'about', child: ListTile(dense: true, leading: Icon(Icons.info_outline), title: Text('About'))),
        ]),
      ]))),
      if (t?.loading == true) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: showHistory ? ListView(children: [
        ListTile(title: Text('BROWSING HISTORY', style: TextStyle(fontWeight: FontWeight.bold))),
        if (history.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No history yet')),
        ...history.map((e) => ListTile(leading: const Icon(Icons.history), title: Text(e['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(e['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () { address.text = e['url'] ?? ''; go(); }, trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { history.remove(e); await _saveHistory(); if (mounted) setState(() {}); }))),
        if (history.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(onPressed: () async { final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Clear history?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear all'))])); if (ok == true) { history.clear(); await _saveHistory(); if (mounted) setState(() {}); } }, icon: const Icon(Icons.delete_sweep_outlined), label: const Text('Clear all history'))),
      ]) : IndexedStack(index: active, children: tabs.map((e) => WebViewWidget(controller: e.controller)).toList())),
      Material(
        color: cs.surface,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: t?.back == true ? () async { await t!.controller.goBack(); } : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: t?.forward == true ? () async { await t!.controller.goForward(); } : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                IconButton(
                  tooltip: 'Home',
                  onPressed: () {
                    address.text = 'https://www.google.com';
                    tab?.controller.loadRequest(Uri.parse('https://www.google.com'));
                  },
                  icon: const Icon(Icons.home_outlined),
                ),
                IconButton(
                  tooltip: 'Downloads',
                  onPressed: widget.onReturn,
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: 'Tabs',
                  onPressed: _showTabs,
                  icon: const Icon(Icons.tab_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    ]));
  }
}

