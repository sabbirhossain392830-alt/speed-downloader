import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FileDownloader().start();
  FileDownloader().configure(
    androidConfig: [(Config.runInForeground, Config.always)],
  );
  FileDownloader().configureNotification(
    running: const TaskNotification('DROX • Downloading', '{filename} • {progress}'),
    paused: const TaskNotification('DROX • Paused', '{filename}'),
    complete: const TaskNotification('DROX • Download complete', '{filename}'),
    error: const TaskNotification('DROX • Download failed', '{filename}'),
    canceled: const TaskNotification('DROX • Canceled', '{filename}'),
    progressBar: true,
    tapOpensFile: true,
  );
  runApp(const DroxApp());
}

class DroxApp extends StatefulWidget {
  const DroxApp({super.key});
  @override
  State<DroxApp> createState() => _DroxAppState();
}

class _DroxAppState extends State<DroxApp> {
  ThemeMode mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF168BFF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DROX',
      themeMode: mode,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFF050B18), colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark, surface: const Color(0xFF101C32))),
      home: DownloadHome(
        isDark: mode == ThemeMode.dark,
        onThemeTap: () => setState(() => mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}

class DroxLogoMark extends StatelessWidget {
  const DroxLogoMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF16D9FF), Color(0xFF0878F9), Color(0xFF071B43)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(size * .29),
      border: Border.all(color: Colors.white.withValues(alpha: .22)),
      boxShadow: [BoxShadow(color: const Color(0xFF078BFF).withValues(alpha: .28), blurRadius: size * .28, offset: const Offset(0, 4))],
    ),
    child: Stack(alignment: Alignment.center, children: [
      Icon(Icons.bolt_rounded, color: Colors.white, size: size * .72),
      Positioned(right: size * .12, bottom: size * .08, child: Icon(Icons.download_rounded, color: const Color(0xFFB8F6FF), size: size * .30)),
    ]),
  );
}

class DownloadEntry {
  DownloadEntry(this.task);
  final DownloadTask task;
  double progress = 0;
  int expectedFileSize = -1;
  String status = 'কিউতে আছে';
  String? error;
  String? sharedPath;
}

enum DownloadFilter { all, active, paused, completed, failed }

class DownloadHome extends StatefulWidget {
  const DownloadHome({super.key, required this.isDark, required this.onThemeTap});
  final bool isDark;
  final VoidCallback onThemeTap;
  @override
  State<DownloadHome> createState() => _DownloadHomeState();
}

class _DownloadHomeState extends State<DownloadHome> {
  static const MethodChannel _shareMethod = MethodChannel('drox/share');
  static const EventChannel _shareEvents = EventChannel('drox/share_events');
  StreamSubscription<dynamic>? _shareSubscription;

  Future<void> _acceptSharedText(String? text) async {
    if (text == null || text.trim().isEmpty || !mounted) return;
    final match = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(text);
    final shared = (match?.group(0) ?? '').replaceAll(RegExp(r'[),.;]+$'), '');
    if (shared.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('শেয়ার করা লেখায় কোনো HTTP/HTTPS লিংক পাওয়া যায়নি')),
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
  bool adding = false;
  bool wifiOnly = false;
  int selectedTab = 0;
  final GlobalKey<_BrowserPageState> browserKey = GlobalKey<_BrowserPageState>();
  static const _historyKey = 'drox_download_history';

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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? 'শুধু Wi‑Fi দিয়ে ডাউনলোড হবে' : 'মোবাইল ডেটাতেও ডাউনলোড হবে')));
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = entries.map((e) => {
      'url': e.task.url,
      'filename': e.task.filename,
      'post': e.task.post,
      'httpRequestMethod': e.task.httpRequestMethod,
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
    try {
      // The downloader's own persistent database is the source of truth.
      // It records native background progress even while the Flutter UI is closed.
      final records = await FileDownloader().database.allRecords();
      final restored = <DownloadEntry>[];
      for (final record in records) {
        final task = record.task;
        if (task is! DownloadTask) continue;
        final entry = DownloadEntry(task)
          ..progress = record.progress.clamp(0.0, 1.0)
          ..expectedFileSize = record.expectedFileSize
          ..status = _statusText(record.status)
          ..error = record.exception?.description;
        restored.add(entry);
      }

      // Keep the existing user-visible shared-storage path metadata.
      final raw = prefs.getString(_historyKey);
      if (raw != null) {
        final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final item in data) {
          final id = item['taskId'] as String?;
          final entry = restored.where((e) => e.task.taskId == id).firstOrNull;
          if (entry != null) {
            entry.sharedPath = item['sharedPath'] as String?;
          }
        }
      }
      if (mounted) {
        setState(() {
          for (final entry in restored) {
            final index = entries.indexWhere((e) => e.task.taskId == entry.task.taskId);
            if (index < 0) {
              entries.add(entry);
            } else {
              entries[index]
                ..progress = entry.progress
                ..expectedFileSize = entry.expectedFileSize
                ..status = entry.status
                ..error = entry.error;
            }
          }
          entries.sort((a, b) => b.task.creationTime.compareTo(a.task.creationTime));
        });
      }
      await _saveHistory();
    } catch (_) {
      // Older app versions may have only SharedPreferences history.
      final raw = prefs.getString(_historyKey);
      if (raw == null) return;
      try {
        final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final restored = data.map((item) {
          final task = DownloadTask(
            url: item['url'] as String,
            filename: item['filename'] as String,
            post: item['post'] as String?,
            httpRequestMethod: item['httpRequestMethod'] as String?,
            directory: 'DROX',
            baseDirectory: BaseDirectory.applicationSupport,
            updates: Updates.statusAndProgress,
            allowPause: true,
            retries: 3,
          );
          return DownloadEntry(task)
            ..progress = (item['progress'] as num?)?.toDouble() ?? 0
            ..expectedFileSize = (item['expectedFileSize'] as num?)?.toInt() ?? -1
            ..status = (item['status'] as String?) ?? 'ইতিহাসে সংরক্ষিত'
            ..error = item['error'] as String?
            ..sharedPath = item['sharedPath'] as String?;
        }).toList();
        if (mounted) setState(() => entries.addAll(restored));
      } catch (_) {
        await prefs.remove(_historyKey);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWifiOnly();
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
      } else if (update is TaskStatusUpdate) {
        if (update.status == TaskStatus.complete) {
          entry.status = 'ফাইল যাচাই হচ্ছে';
          entry.progress = 1;
          entry.error = null;
          _verifyCompletedFile(entry);
        } else {
          entry.status = _statusText(update.status);
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
      if (entry.expectedFileSize > 0 && actualSize != entry.expectedFileSize) {
        throw Exception('ফাইলের সাইজ অসম্পূর্ণ');
      }
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

  Future<(String, String)> _downloadDetails(String url, {Map<String, String> headers = const {}}) async {
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
      response = await dio.head(url, options: Options(headers: headers));
    } catch (_) {
      response = null;
    }
    if (response != null) {
      final responseType = (response.headers.value('content-type') ?? '').toLowerCase();
      // Some hosts reject HEAD requests but allow the actual GET download.
      // Keep the original URL and let the download engine attempt the transfer.
      if (responseType.contains('text/html')) {
        throw Exception('সার্ভার ভিডিওর বদলে HTML/Cloudflare পেজ পাঠিয়েছে');
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

  Future<void> _add({String? suggestedFilename, int retries = 5, Map<String, String> requestHeaders = const {}, String? postBody}) async {
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
      details = postBody == null
          ? await _downloadDetails(value, headers: requestHeaders)
          : (value, suggestedFilename == null || suggestedFilename.trim().isEmpty ? _fileName(value) : _safeFileName(suggestedFilename.trim()));
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
      headers: requestHeaders,
      filename: suggestedFilename == null || suggestedFilename.trim().isEmpty ? details.$2 : _safeFileName(suggestedFilename.trim()),
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: retries,
      post: postBody,
      httpRequestMethod: postBody == null ? 'GET' : 'POST',
    );
    setState(() {
      entries.insert(0, DownloadEntry(task));
      controller.clear();
    });
    _saveHistory();
    final ok = await FileDownloader().enqueue(task);
    if (!ok && mounted) {
      setState(() => entries.firstWhere((e) => e.task.taskId == task.taskId).status = 'কিউতে যোগ করা যায়নি');
    }
    _saveHistory();
    if (mounted) setState(() => adding = false);
  }

  Future<void> _pause(DownloadEntry entry) async {
    final ok = await FileDownloader().pause(entry.task);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('এই সার্ভার Pause/Resume সমর্থন নাও করতে পারে')));
    }
  }

  Future<void> _resume(DownloadEntry entry) async {
    final ok = await FileDownloader().resume(entry.task);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডাউনলোডটি Resume করা যায়নি')));
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ফোনের Downloads ফোল্ডারে কপি করা যায়নি')));
    }
  }

  Future<void> _open(DownloadEntry entry) async {
    if (entry.status != 'সম্পন্ন') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডাউনলোড সম্পন্ন হলে ফাইল Open করা যাবে')));
      return;
    }
    if (entry.sharedPath == null) await _publishToPhone(entry);
    final result = entry.sharedPath != null
        ? await FileDownloader().openFile(filePath: entry.sharedPath!)
        : await FileDownloader().openFile(task: entry.task);
    if (!result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ফাইলটি খোলা যায়নি')));
    }
  }

  Future<void> _redownload(DownloadEntry entry) async {
    final details = entry.task.post == null
        ? await _downloadDetails(entry.task.url, headers: entry.task.headers)
        : (entry.task.url, entry.task.filename);
    final task = DownloadTask(
      url: details.$1,
      filename: details.$2,
      headers: entry.task.headers,
      post: entry.task.post,
      httpRequestMethod: entry.task.httpRequestMethod,
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 5,
    );
    setState(() => entries.insert(0, DownloadEntry(task)));
    _saveHistory();
    final ok = await FileDownloader().enqueue(task);
    if (!ok && mounted) {
      setState(() => entries.firstWhere((e) => e.task.taskId == task.taskId).status = 'কিউতে যোগ করা যায়নি');
    }
  }

  Future<void> _showDownloadProperties(DownloadEntry entry) async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.task.filename, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('Status: ${entry.status}'),
            Text('Progress: ${(entry.progress * 100).toStringAsFixed(1)}%'),
            Text('Size: ${_formatBytes(entry.expectedFileSize)}'),
            const SizedBox(height: 8),
            SelectableText(entry.task.url, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _remove(DownloadEntry entry) async {
    if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(entry.status)) {
      await FileDownloader().cancelTaskWithId(entry.task.taskId);
    }
    if (mounted) setState(() => entries.removeWhere((e) => e.task.taskId == entry.task.taskId));
    _saveHistory();
  }

  bool _matches(DownloadEntry e) {
    switch (filter) {
      case DownloadFilter.all: return true;
      case DownloadFilter.active: return ['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(e.status);
      case DownloadFilter.completed: return e.status == 'সম্পন্ন';
      case DownloadFilter.failed: return ['ব্যর্থ', 'বাতিল', 'কিউতে যোগ করা যায়নি'].contains(e.status);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    subscription?.cancel();
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = entries.where((e) => ['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে'].contains(e.status)).length;
    final done = entries.where((e) => e.status == 'সম্পন্ন').length;
    final visible = entries.where(_matches).toList();
    final cs = Theme.of(context).colorScheme;
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
        toolbarHeight: 48,
        titleSpacing: 16,
        title: const Text(
          'DROX',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.0, fontSize: 19),
        ),
        actions: [
          IconButton(tooltip: 'Download statistics', onPressed: _showDownloadStats, icon: const Icon(Icons.insights_rounded)),
          PopupMenuButton<String>(
            tooltip: 'Main menu',
            icon: const Icon(Icons.menu_rounded, size: 28),
            onSelected: (v) {
              if (v == 'theme') widget.onThemeTap();
              if (v == 'wifi') _setWifiOnly(!wifiOnly);
              if (v == 'quick') _quickDownloadDialog();
              if (v == 'browser') setState(() => selectedTab = 1);
              if (v == 'settings') setState(() => selectedTab = 3);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'theme', child: ListTile(dense: true, leading: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: const Text('Dark Mode'), trailing: Icon(widget.isDark ? Icons.check : Icons.circle_outlined))),
              PopupMenuItem(value: 'wifi', child: ListTile(dense: true, leading: const Icon(Icons.wifi_rounded), title: const Text('Wi‑Fi Only'), trailing: Icon(wifiOnly ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color: wifiOnly ? Theme.of(context).colorScheme.primary : null))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'quick', child: ListTile(dense: true, leading: Icon(Icons.add_link_rounded), title: Text('Quick Download'))),
              const PopupMenuItem(value: 'browser', child: ListTile(dense: true, leading: Icon(Icons.public_rounded), title: Text('Browser'))),
              const PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: selectedTab, children: [
        _homeDashboard(visible, active, done, cs),
        BrowserPage(key: browserKey, isDark: widget.isDark, onThemeTap: widget.onThemeTap, onReturn: () => setState(() => selectedTab = 0), onSettings: () => setState(() => selectedTab = 3), onDownload: (url, filename, wifiOnly, retry, headers, postBody) async { if (wifiOnly) await _setWifiOnly(true); controller.text = url; await _add(suggestedFilename: filename, retries: retry ? 5 : 0, requestHeaders: headers, postBody: postBody); }),
        _downloadsDashboard(visible, active, done, cs),
        ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
          const SizedBox(height: 14),
          Text('GENERAL', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.3, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(clipBehavior: Clip.antiAlias, child: Column(children: [
            ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Appearance'), subtitle: Text(widget.isDark ? 'Dark theme' : 'Light theme'), trailing: Switch(value: widget.isDark, onChanged: (_) => widget.onThemeTap())),
            const Divider(height: 1, indent: 56),
            ListTile(leading: const Icon(Icons.wifi_rounded), title: const Text('Wi‑Fi Only'), subtitle: const Text('Mobile data দিয়ে download বন্ধ রাখবে'), trailing: Switch(value: wifiOnly, onChanged: _setWifiOnly)),
            const Divider(height: 1, indent: 56),
            const ListTile(leading: Icon(Icons.folder_outlined), title: Text('Download folder'), subtitle: Text('Phone storage / Downloads / DROX')),
          ])),
          const SizedBox(height: 18),
          Text('ABOUT', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.3, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(child: const ListTile(leading: Icon(Icons.info_outline), title: Text('About DROX'), subtitle: Text('Browser and download manager'), trailing: Icon(Icons.chevron_right_rounded))),
        ]),
      ]),
      bottomNavigationBar: selectedTab == 1 ? null : NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (i) => setState(() => selectedTab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.public), label: 'Browser'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    ));
  }

  Widget _downloadsDashboard(List<DownloadEntry> visible, int active, int done, ColorScheme cs) {
    final failed = entries.where((e) => ['ব্যর্থ','বাতিল','কিউতে যোগ করা যায়নি','যাচাই ব্যর্থ'].contains(e.status)).length;
    final completed = entries.where((e) => e.status == 'সম্পন্ন').length;
    final paused = entries.where((e) => e.status == 'বিরতি').length;
    final totalBytes = entries.where((e) => e.status == 'সম্পন্ন').fold<int>(0, (sum, e) => sum + (e.expectedFileSize > 0 ? e.expectedFileSize : 0));
    return ListView(padding: const EdgeInsets.fromLTRB(15, 10, 15, 20), children: [
      Row(children: [
        const Expanded(child: Text('Downloads', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
        Text('${entries.length} files', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700)),
        IconButton(tooltip: 'Quick download', onPressed: _quickDownloadDialog, icon: const Icon(Icons.add_link_rounded)),
        IconButton(tooltip: 'Statistics', onPressed: _showDownloadStats, icon: const Icon(Icons.insights_rounded)),
      ]),
      const SizedBox(height: 5),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .38),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .45)),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TOTAL DOWNLOADED', style: TextStyle(fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w900, color: cs.onSurfaceVariant)),
            const SizedBox(height: 5),
            Text(_statsSize(totalBytes), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('$completed completed  •  $active active', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ])),
          Container(width: 52, height: 52, decoration: BoxDecoration(color: cs.primary.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(Icons.downloading_rounded, color: cs.primary, size: 27)),
        ]),
      ),
      const SizedBox(height: 15),
      Row(children: [
        _downloadCategory('All', entries.length, DownloadFilter.all, Icons.apps_rounded, cs),
        _downloadCategory('Active', active, DownloadFilter.active, Icons.downloading_rounded, cs),
        _downloadCategory('Paused', paused, DownloadFilter.paused, Icons.pause_circle_outline_rounded, cs),
        _downloadCategory('Done', completed, DownloadFilter.completed, Icons.check_circle_outline_rounded, cs),
        _downloadCategory('Failed', failed, DownloadFilter.failed, Icons.error_outline_rounded, cs),
      ]),
      const SizedBox(height: 17),
      Row(children: [
        const Expanded(child: Text('File list', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        PopupMenuButton<String>(
          tooltip: 'Sort downloads',
          onSelected: (v) => setState(() {
            if (v == 'name') entries.sort((a,b) => a.task.filename.toLowerCase().compareTo(b.task.filename.toLowerCase()));
            if (v == 'newest') entries.sort((a,b) => b.task.creationTime.compareTo(a.task.creationTime));
            if (v == 'largest') entries.sort((a,b) => b.expectedFileSize.compareTo(a.expectedFileSize));
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'newest', child: Text('Newest first')),
            PopupMenuItem(value: 'name', child: Text('Name A–Z')),
            PopupMenuItem(value: 'largest', child: Text('Largest first')),
          ],
          icon: const Icon(Icons.sort_rounded),
        ),
      ]),
      const SizedBox(height: 7),
      if (visible.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .22), borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant.withValues(alpha: .4))),
          child: Column(children: [
            Icon(Icons.folder_open_rounded, size: 42, color: cs.onSurfaceVariant.withValues(alpha: .65)),
            const SizedBox(height: 9),
            const Text('No files in this category', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Your downloads will appear here.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        )
      else ...visible.map(_downloadCard),
    ]);
  }

  Widget _downloadCategory(String label, int count, DownloadFilter value, IconData icon, ColorScheme cs) {
    final selected = filter == value;
    return Expanded(child: Padding(
      padding: const EdgeInsets.only(right: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => setState(() => filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: .32),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? cs.primary.withValues(alpha: .5) : cs.outlineVariant.withValues(alpha: .35)),
          ),
          child: Column(children: [
            Icon(icon, size: 17, color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text('$count', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: selected ? cs.onPrimaryContainer : cs.onSurface)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
          ]),
        ),
      ),
    ));
  }

  Widget _homeDashboard(List<DownloadEntry> visible, int active, int done, ColorScheme cs) {
    final failed = entries.where((e) => ['ব্যর্থ','বাতিল','কিউতে যোগ করা যায়নি','যাচাই ব্যর্থ'].contains(e.status)).length;
    final totalBytes = entries.where((e) => e.status == 'সম্পন্ন').fold<int>(0, (sum, e) => sum + (e.expectedFileSize > 0 ? e.expectedFileSize : 0));
    return ListView(padding: const EdgeInsets.fromLTRB(15, 10, 15, 20), children: [
      Row(children: [
        const DroxLogoMark(size: 42),
        const SizedBox(width: 11),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DROX', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 2)),
          Text('DOWNLOAD MANAGER', style: TextStyle(fontSize: 9, letterSpacing: 1.7, fontWeight: FontWeight.w800, color: Colors.grey)),
        ])),
        IconButton(tooltip: 'Browser', onPressed: () => setState(() => selectedTab = 1), icon: const Icon(Icons.language_rounded)),
        IconButton(tooltip: 'Statistics', onPressed: _showDownloadStats, icon: const Icon(Icons.insights_rounded)),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0757B8), Color(0xFF087DE0), Color(0xFF11A9D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(23),
          boxShadow: [BoxShadow(color: const Color(0xFF087DE0).withValues(alpha: .22), blurRadius: 20, offset: const Offset(0, 9))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Your downloads', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)), child: Text('$active ACTIVE', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .8))),
          ]),
          const SizedBox(height: 5),
          Text('$done completed', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('Total saved  •  ${_statsSize(totalBytes)}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 15),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .55)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
              onPressed: _quickDownloadDialog, icon: const Icon(Icons.add_link_rounded, size: 18), label: const Text('Add link'),
            )),
            const SizedBox(width: 9),
            Expanded(child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0757B8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
              onPressed: () => setState(() => selectedTab = 1), icon: const Icon(Icons.public_rounded, size: 18), label: const Text('Browser'),
            )),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      const Text('CATEGORIES', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
      const SizedBox(height: 9),
      Row(children: [
        _homeCategory('All', entries.length, DownloadFilter.all, Icons.apps_rounded),
        _homeCategory('Active', active, DownloadFilter.active, Icons.downloading_rounded),
        _homeCategory('Finished', done, DownloadFilter.completed, Icons.check_circle_outline_rounded),
        _homeCategory('Failed', failed, DownloadFilter.failed, Icons.error_outline_rounded),
      ]),
      const SizedBox(height: 19),
      Row(children: [
        const Expanded(child: Text('Recent downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        TextButton(onPressed: () => setState(() => selectedTab = 2), child: const Text('View all')),
      ]),
      if (visible.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 31, horizontal: 18),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .25), borderRadius: BorderRadius.circular(19), border: Border.all(color: cs.outlineVariant.withValues(alpha: .45))),
          child: Column(children: [
            Container(width: 62, height: 62, decoration: BoxDecoration(color: cs.primary.withValues(alpha: .10), shape: BoxShape.circle), child: Icon(Icons.downloading_rounded, size: 31, color: cs.primary)),
            const SizedBox(height: 12),
            const Text('Nothing downloading yet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 5),
            Text('Paste a direct link or browse a website to get started.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        )
      else ...visible.take(4).map(_downloadCard),
    ]);
  }

  Widget _homeCategory(String label, int count, DownloadFilter value, IconData icon) {
    final selected = filter == value;
    final cs = Theme.of(context).colorScheme;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => filter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? cs.primary.withValues(alpha: .45) : cs.outlineVariant.withValues(alpha: .35)),
        ),
        child: Column(children: [
          Icon(icon, size: 19, color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(height: 4),
          Text('$count', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: selected ? cs.onPrimaryContainer : cs.onSurface)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
        ]),
      ),
    ));
  }

  String _statsSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble(); var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _showDownloadStats() async {
    final completed = entries.where((e) => e.status == 'সম্পন্ন').toList();
    final active = entries.where((e) => ['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(e.status)).length;
    final failed = entries.where((e) => ['ব্যর্থ', 'বাতিল', 'কিউতে যোগ করা যায়নি', 'যাচাই ব্যর্থ'].contains(e.status)).length;
    final bytes = completed.fold<int>(0, (sum, e) => sum + (e.expectedFileSize > 0 ? e.expectedFileSize : 0));
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Download statistics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5), Text('Your DROX activity at a glance', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 18),
        Row(children: [
          _statTile(ctx, 'Total', entries.length.toString(), Icons.download_rounded),
          _statTile(ctx, 'Active', active.toString(), Icons.downloading_rounded),
          _statTile(ctx, 'Done', completed.length.toString(), Icons.check_circle_outline_rounded),
          _statTile(ctx, 'Failed', failed.toString(), Icons.error_outline_rounded),
        ]),
        const SizedBox(height: 16),
        Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .35), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [Icon(Icons.storage_rounded, color: cs.primary), const SizedBox(width: 12), const Expanded(child: Text('Completed file size')), Text(_statsSize(bytes), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))])),
      ]),
    )));
  }

  Widget _statTile(BuildContext context, String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(child: Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 5), decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(13)), child: Column(children: [
      Icon(icon, size: 19, color: cs.primary), const SizedBox(height: 7), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
    ])));
  }

  Future<void> _quickDownloadDialog() async {
    controller.clear();
    final value = await showDialog<String>(context: context, builder: (ctx) {
      final field = TextEditingController();
      return AlertDialog(
        title: const Text('Quick download'),
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
    if (bytes <= 0) return 'Size অজানা';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return value >= 100 || unit == 0 ? '${value.toStringAsFixed(0)} ${units[unit]}' : '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  String _fileType(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'FILE' : name.substring(dot + 1).toUpperCase() + ' FILE';
  }

  Widget _downloadCard(DownloadEntry entry) {
    final running = entry.status == 'ডাউনলোড হচ্ছে';
    final paused = entry.status == 'বিরতি';
    final queued = ['কিউতে আছে', 'আবার চেষ্টা করছে'].contains(entry.status);
    final completed = entry.status == 'সম্পন্ন';
    final failed = ['ব্যর্থ', 'বাতিল', 'কিউতে যোগ করা যায়নি', 'যাচাই ব্যর্থ'].contains(entry.status);
    final cs = Theme.of(context).colorScheme;
    final statusColor = completed ? Colors.green : failed ? cs.error : cs.primary;
    final percent = (entry.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final statusLabel = completed ? 'COMPLETED' : running ? 'DOWNLOADING' : paused ? 'PAUSED' : failed ? 'FAILED' : queued ? 'QUEUED' : 'WAITING';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_fileIcon(entry.task.filename), color: statusColor, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.task.filename, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text('${_fileType(entry.task.filename)}  •  ${_formatBytes(entry.expectedFileSize)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ])),
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'open') _open(entry);
                if (value == 'redownload') _redownload(entry);
                if (value == 'remove') _remove(entry);
                if (value == 'copy') Clipboard.setData(ClipboardData(text: entry.task.url));
                if (value == 'properties') _showDownloadProperties(entry);
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'open', enabled: completed, child: const ListTile(dense: true, leading: Icon(Icons.open_in_new), title: Text('Open'))),
                const PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.link_rounded), title: Text('Copy download link'))),
                const PopupMenuItem(value: 'redownload', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Download again'))),
                const PopupMenuItem(value: 'properties', child: ListTile(dense: true, leading: Icon(Icons.info_outline), title: Text('Properties'))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Remove from list'))),
              ],
            ),
          ]),
          const SizedBox(height: 7),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 8, letterSpacing: .5, fontWeight: FontWeight.w900)),
            ),
            const Spacer(),
            Text('$percent%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: statusColor)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: completed ? 1 : entry.progress),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.expectedFileSize > 0
                ? '${_formatBytes((entry.progress * entry.expectedFileSize).round())} of ${_formatBytes(entry.expectedFileSize)}'
                : (entry.progress > 0 ? '${percent}% downloaded • Total size unavailable' : 'Waiting for download information…'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          if (entry.error != null || (!completed && !running && !paused && !queued)) ...[
            const SizedBox(height: 7),
            Text(entry.error ?? entry.status, style: TextStyle(fontSize: 11, color: failed ? cs.error : cs.onSurfaceVariant)),
          ],
          if (running || paused || queued || failed || completed) ...[
            const SizedBox(height: 6),
            Row(children: [
              if (running)
                _actionIcon(icon: Icons.pause_rounded, label: 'Pause', onTap: () => _pause(entry), primary: true),
              if (paused || queued)
                _actionIcon(icon: Icons.play_arrow_rounded, label: 'Resume', onTap: () => _resume(entry), primary: true),
              if (failed)
                _actionIcon(icon: Icons.refresh_rounded, label: 'Retry', onTap: () => _redownload(entry), primary: true),
              if (completed)
                _actionIcon(icon: Icons.open_in_new_rounded, label: 'Open', onTap: () => _open(entry), primary: true),
              if (running || paused || queued)
                _actionIcon(icon: Icons.close_rounded, label: 'Cancel', onTap: () => _cancel(entry)),
              const Spacer(),
              if (completed) Icon(Icons.check_circle_rounded, color: statusColor, size: 20),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _actionIcon({required IconData icon, required String label, required VoidCallback onTap, bool primary = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Tooltip(
        message: label,
        child: Material(
          color: primary ? cs.primaryContainer : cs.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                icon,
                size: 18,
                color: primary ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

}


class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.onDownload, required this.isDark, required this.onThemeTap, required this.onReturn, required this.onSettings});
  final Future<void> Function(String url, String filename, bool wifiOnly, bool retry, Map<String, String> headers, String? postBody) onDownload;
  final bool isDark;
  final VoidCallback onThemeTap, onReturn, onSettings;
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}
class _DroxTab {
  _DroxTab(this.controller, this.url, {this.isPrivate = false});
  final WebViewController controller;
  final bool isPrivate;
  String url;
  String title = 'New tab';
  bool loading = false, back = false, forward = false;
}
class _BrowserPageState extends State<BrowserPage> {
  static const MethodChannel _sessionChannel = MethodChannel('drox/browser_session');
  final address = TextEditingController(text: 'https://www.google.com');
  final tabs = <_DroxTab>[];
  final history = <Map<String,String>>[];
  int active = 0;
  bool showHistory = false, adBlockEnabled = true, desktopMode = false;
  bool _downloadIntentPending = false;
  Timer? _downloadIntentTimer;
  Future<void> _blobQueue = Future<void>.value();
  final bookmarks = <Map<String, String>>[];
  final shortcuts = <Map<String, String>>[];
  bool showBookmarks = false;
  bool privateModeNext = false;
  _DroxTab? get tab => tabs.isEmpty ? null : tabs[active];
  @override
  void initState() { super.initState(); _loadHistory(); _newTab(); }
  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString('drox_browser_history');
      if (raw != null) history.addAll((jsonDecode(raw) as List).cast<Map<String,dynamic>>().map((e) => <String,String>{'title': (e['title'] ?? '').toString(), 'url': (e['url'] ?? '').toString()}));
      final saved = p.getString('drox_browser_bookmarks');
      if (saved != null) bookmarks.addAll((jsonDecode(saved) as List).cast<Map<String,dynamic>>().map((e) => <String,String>{'title': (e['title'] ?? '').toString(), 'url': (e['url'] ?? '').toString()}));
      final savedShortcuts = p.getString('drox_browser_shortcuts');
      if (savedShortcuts != null) shortcuts.addAll((jsonDecode(savedShortcuts) as List).cast<Map<String,dynamic>>().map((e) => <String,String>{'title': (e['title'] ?? '').toString(), 'url': (e['url'] ?? '').toString()}));
      if (mounted) setState(() {});
    } catch (_) {}
  }
  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('drox_browser_history', jsonEncode(history.take(100).toList()));
    await p.setString('drox_browser_bookmarks', jsonEncode(bookmarks));
    await p.setString('drox_browser_shortcuts', jsonEncode(shortcuts));
  }
  Future<void> _bookmarkCurrent() async {
    final current = tab;
    if (current == null || !current.url.startsWith('http')) return;
    bookmarks.removeWhere((item) => item['url'] == current.url);
    bookmarks.insert(0, {'title': current.title, 'url': current.url});
    await _saveHistory();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmark saved')));
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
  String get _homePageHtml {
    final custom = shortcuts.map((item) {
      final rawTitle = item['title'] ?? 'Website';
      final title = const HtmlEscape().convert(rawTitle);
      final url = const HtmlEscape().convert(item['url'] ?? '');
      final letter = const HtmlEscape().convert(rawTitle.trim().isEmpty ? 'W' : rawTitle.trim()[0].toUpperCase());
      return '<a class="shortcut" href="$url"><span class="app-icon custom-icon">$letter</span><small>$title</small></a>';
    }).join();
    final recent = history.where((item) => (item['url'] ?? '').startsWith('http')).take(4).map((item) {
      final title = const HtmlEscape().convert(item['title'] ?? 'Website');
      final url = const HtmlEscape().convert(item['url'] ?? '');
      final host = const HtmlEscape().convert(Uri.tryParse(item['url'] ?? '')?.host ?? '');
      return '<a class="recent-item" href="$url"><span>↗</span><div><b>$title</b><small>$host</small></div></a>';
    }).join();
    return r'''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
*{box-sizing:border-box}body{margin:0;background:#101010;color:#f5f5f5;font-family:Arial,sans-serif;min-height:100vh}
main{padding:10px 14px 14px;display:flex;flex-direction:column;align-items:center}
.brand{font-size:clamp(44px,11vw,56px);font-weight:700;letter-spacing:-3.5px;margin:3px 0 16px;line-height:1.08}
.b{color:#4285f4}.r{color:#ea4335}.y{color:#fbbc05}.g{color:#34a853}
form{width:100%;max-width:560px;height:46px;border:1px solid #454545;border-radius:25px;display:flex;align-items:center;padding:0 6px 0 14px;background:#171717}
form:focus-within{background:#202020;border-color:#777}
input{min-width:0;flex:1;background:transparent;border:0;outline:0;color:white;font-size:15px;padding:8px}
input::placeholder{color:#aaa}
button{border:0;border-radius:50%;width:36px;height:36px;background:#a87912;color:white;font-size:21px}
.shortcuts{width:100%;max-width:560px;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:20px;justify-items:center}
.shortcut{width:100%;max-width:76px;min-height:78px;border-radius:15px;background:#202633;color:#eee;text-decoration:none;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;font-size:11px;font-weight:600;text-align:center;padding:6px 3px;overflow-wrap:anywhere;border:1px solid #30394a}
.app-icon{width:38px;height:38px;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;font-weight:800;color:white;background:linear-gradient(145deg,#287cff,#152c62);box-shadow:0 3px 10px #0008}
.custom-icon{background:linear-gradient(145deg,#7c5cff,#1d397c)}
.shortcut small{font-size:10px;line-height:1.15;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.add{border:1px dashed #65718a;background:#171e2b;cursor:pointer}
.add .app-icon{background:linear-gradient(145deg,#348cff,#1754ba);font-size:25px}
.recent{width:100%;max-width:560px;margin-top:25px}.recent-title{font-size:12px;font-weight:700;color:#aaa;margin:0 0 8px 3px}.recent-item{display:flex;align-items:center;gap:11px;padding:10px 12px;margin:6px 0;border-radius:13px;background:#1a1a1a;color:#eee;text-decoration:none;border:1px solid #292929}.recent-item>span{width:30px;height:30px;border-radius:10px;background:#26354d;color:#9cc4ff;display:flex;align-items:center;justify-content:center}.recent-item div{min-width:0;display:flex;flex-direction:column;gap:3px}.recent-item b{font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.recent-item small{font-size:10px;color:#888;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.hint{color:#777;font-size:10px;margin-top:14px;text-align:center}
</style></head><body><main>
<div class="brand"><span class="b">G</span><span class="r">o</span><span class="y">o</span><span class="b">g</span><span class="g">l</span><span class="r">e</span></div>
<form onsubmit="event.preventDefault();var q=document.getElementById('q').value.trim();if(q)location.href='https://www.google.com/search?q='+encodeURIComponent(q)">
<input id="q" type="search" placeholder="Search Google or type a URL" autocomplete="off" aria-label="Search Google"><button type="submit" aria-label="Search">→</button>
</form>
<div class="shortcuts">__CUSTOM_SHORTCUTS__
<a class="shortcut" href="https://www.youtube.com/"><span class="app-icon" style="background:#e62117">▶</span><small>YouTube</small></a>
<a class="shortcut" href="https://www.facebook.com/"><span class="app-icon" style="background:#1877f2">f</span><small>Facebook</small></a>
<a class="shortcut add" href="#" onclick="event.preventDefault();DroxDownload.postMessage('ADD_SHORTCUT')"><span class="app-icon">＋</span><small>Add</small></a>
</div><section class="recent"><div class="recent-title">RECENTLY VISITED</div>__RECENT_SITES__</section><div class="hint">Your favourite sites, one tap away</div>
</main></body></html>'''.replaceAll('__CUSTOM_SHORTCUTS__', custom).replaceAll('__RECENT_SITES__', recent.isEmpty ? '<div class="hint">Your visited sites will appear here</div>' : recent);
  }

  Future<void> _newTab([String url = 'https://www.google.com', bool? private]) async {
    final makePrivate = private ?? privateModeNext;
    privateModeNext = false;
    final t = _DroxTab(WebViewController(), url, isPrivate: makePrivate);
    tabs.add(t); active = tabs.length - 1; showHistory = false;
    final ctrl = t.controller;
    await ctrl.setJavaScriptMode(JavaScriptMode.unrestricted);
    await ctrl.addJavaScriptChannel('DroxDownload', onMessageReceived: (m) async {
      if (m.message == '__DROX_DOWNLOAD_INTENT__') {
        _downloadIntentPending = true;
        _downloadIntentTimer?.cancel();
        _downloadIntentTimer = Timer(const Duration(seconds: 20), () => _downloadIntentPending = false);
      } else if (m.message.startsWith('{')) {
        try {
          final payload = jsonDecode(m.message);
          if (payload is Map && payload['type'] == 'blobStart') {
            _blobQueue = _blobQueue.then<void>((_) async { await _sessionChannel.invokeMethod('blobStart', {'id': payload['id'], 'filename': payload['filename'], 'size': payload['size']}); });
          } else if (payload is Map && payload['type'] == 'blobChunk') {
            _blobQueue = _blobQueue.then<void>((_) async { await _sessionChannel.invokeMethod('blobChunk', {'id': payload['id'], 'data': payload['data']}); });
          } else if (payload is Map && payload['type'] == 'blobEnd') {
            _blobQueue = _blobQueue.then((_) async {
              final saved = await _sessionChannel.invokeMethod<String>('blobEnd', {'id': payload['id']});
              if (mounted && saved != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Blob file saved: $saved')));
            });
          } else {
            if (payload is Map && payload['url'] is String) {
              final headers = <String, String>{};
              if (payload['headers'] is Map) (payload['headers'] as Map).forEach((k, v) { if (k is String && v is String && v.isNotEmpty) headers[k] = v; });
              _downloadPrompt(payload['url'] as String, headers: headers, force: payload['force'] == true, postBody: payload['post'] is String ? payload['post'] as String : null);
            }
          }
        } catch (_) {}
      } else if (m.message == 'ADD_SHORTCUT') {
        _addHomeShortcut();
      } else if (m.message.startsWith('__DROX_NEW_TAB__:')) {
        final target = m.message.substring('__DROX_NEW_TAB__:'.length);
        final parsed = Uri.tryParse(target);
        if (parsed != null && ['http', 'https'].contains(parsed.scheme) && parsed.host.isNotEmpty) _newTab(target);
      }
    });
    await ctrl.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (r) {
        if (_downloadable(r.url)) { _downloadPrompt(r.url); return NavigationDecision.prevent; }
        final navUri = Uri.tryParse(r.url);
        if (_downloadIntentPending && navUri != null && ['http', 'https'].contains(navUri.scheme) && r.url != t.url) {
          _downloadIntentPending = false;
          _downloadIntentTimer?.cancel();
          _downloadPrompt(r.url);
          return NavigationDecision.prevent;
        }
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
          var mediaTypes=/^(video\/|audio\/|image\/|application\/(octet-stream|pdf|zip|x-rar-compressed|vnd\.rar|x-7z-compressed|vnd\.android\.package-archive|vnd\.apple\.mpegurl|x-mpegurl|dash\+xml|msword|vnd\.openxmlformats-officedocument|vnd\.ms-|vnd\.oasis\.opendocument))/i;
          function valid(raw){try{var u=new URL(raw,location.href);return /^https?:$/.test(u.protocol)?u.href:null}catch(_){return null}}
          function requestHeaders(){var h={};try{h['User-Agent']=navigator.userAgent||'';h['Referer']=location.href;var ck=document.cookie;if(ck)h['Cookie']=ck}catch(_){}return h}
          function send(raw,extra,force,post){var u=valid(raw);if(!u)return;var h=requestHeaders();if(extra)Object.keys(extra).forEach(function(k){if(extra[k])h[k]=extra[k]});var key=u+'|'+(h.Cookie||'')+'|'+(force?'1':'0')+'|'+(post||'');if(seen[key])return;seen[key]=1;DroxDownload.postMessage(JSON.stringify({url:u,headers:h,force:!!force,post:post||null}))}
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
          if(window.fetch){var originalFetch=window.fetch;window.fetch=function(){var args=arguments;var p=originalFetch.apply(this,args);try{var u=typeof args[0]==='string'?args[0]:args[0].url;var init=args[1]||{};var method=String(init.method||(args[0]&&args[0].method)||'GET').toUpperCase();var body=typeof init.body==='string'?init.body:(init.body instanceof URLSearchParams?init.body.toString():null);p.then(function(r){var ct=r.headers.get('content-type')||'';var cd=r.headers.get('content-disposition')||'';var target=r.url||u;if(mediaTypes.test(ct)||exts.test(target||'')||/attachment/i.test(cd))send(target,{'Content-Type':ct,'Content-Disposition':cd},true,method==='POST'?body:null)})}catch(_){}return p}}
          if(window.XMLHttpRequest){var originalOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){this.__droxUrl=u;this.__droxMethod=String(m||'GET').toUpperCase();return originalOpen.apply(this,arguments)};var originalSend=XMLHttpRequest.prototype.send;XMLHttpRequest.prototype.send=function(body){this.__droxBody=typeof body==='string'?body:(body instanceof URLSearchParams?body.toString():null);this.addEventListener('load',function(){var ct=this.getResponseHeader('content-type')||'';var cd=this.getResponseHeader('content-disposition')||'';if(mediaTypes.test(ct)||exts.test(this.__droxUrl||'')||/attachment/i.test(cd))send(this.responseURL||this.__droxUrl,{'Content-Type':ct,'Content-Disposition':cd},true,this.__droxMethod==='POST'?this.__droxBody:null)});return originalSend.apply(this,arguments)}}
          scan();new MutationObserver(function(){scan();scanResources();scanFrames()}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
          setInterval(function(){scan();scanResources();scanFrames()},2500);
          document.addEventListener('play',function(e){if(e.target&&(e.target.tagName==='VIDEO'||e.target.tagName==='AUDIO'))mediaSources(e.target)},true);
          function downloadIntent(el){
            if(!el)return false;
            var label=((el.innerText||el.textContent||'')+' '+(el.getAttribute('aria-label')||'')+' '+(el.getAttribute('title')||'')).toLowerCase();
            var attrs=['href','data-href','data-url','data-download-url','data-download','data-file','data-link','data-target','data-src','data-id','onclick'];
            var hasTarget=attrs.some(function(k){return !!el.getAttribute(k)});
            return el.hasAttribute('download')||(/download|save file|get file|direct link|one click|fastest|high.?speed|fsl|gp high|server/i.test(label)&&(hasTarget||el.tagName==='BUTTON'||el.getAttribute('role')==='button'||getComputedStyle(el).cursor==='pointer'));
          }
          function candidate(el){
            if(!el)return null;
            var attrs=['href','data-href','data-url','data-download-url','data-download','data-file','data-link','data-target','data-src'];
            var raw=null;
            for(var i=0;i<attrs.length&&!raw;i++){var v=el.getAttribute(attrs[i]);if(v&&v.trim())raw=v.trim()}
            if(!raw&&el.querySelector){var a=el.querySelector('a[href], [data-url], [data-href], [data-download-url]');if(a){for(var j=0;j<attrs.length&&!raw;j++){var av=a.getAttribute(attrs[j]);if(av&&av.trim())raw=av.trim()}}}
            if(!raw&&el.form)raw=el.form.action;
            if(!raw){var oc=(el.getAttribute('onclick')||'')+' '+(el.getAttribute('data-onclick')||'');var m=oc.match(/https?:[^\\s'"\\x60]+|['"]((?:\\/|\\.\\.\\/)[^'"]+)['"]/i);if(m)raw=m[1]||m[0]}
            if(!raw)return null;
            return valid(raw);
          }
          document.addEventListener('click',function(e){
            var path=e.composedPath?e.composedPath():[];
            var nodes=path.length?path:(function(){var a=[],n=e.target;while(n){a.push(n);n=n.parentElement}return a})();
            if(nodes.length){var n=nodes[nodes.length-1];while(n&&n.parentElement&&nodes.length<24){n=n.parentElement;nodes.push(n)}}
            var actionable=null;
            for(var ai=0;ai<nodes.length;ai++){var candidateNode=nodes[ai];if(candidateNode&&candidateNode.nodeType===1&&(candidateNode.matches('a,button,[role="button"],input[type="submit"],input[type="button"]'))){actionable=candidateNode;break}}
            if(actionable&&downloadIntent(actionable)){
              var direct=candidate(actionable);
              if(direct){send(direct,{'Content-Disposition':'attachment'},true)}
              else {DroxDownload.postMessage('__DROX_DOWNLOAD_INTENT__')}
            }
            for(var i=0;i<nodes.length&&i<24;i++){
              var el=nodes[i];if(!el||el.nodeType!==1)continue;
              if(!downloadIntent(el))continue;
              DroxDownload.postMessage('__DROX_DOWNLOAD_INTENT__');
              var u=candidate(el);
              if(u)send(u);
              setTimeout(scanResources,150);
              setTimeout(scanResources,500);
              setTimeout(scanResources,1200);
              setTimeout(scanResources,2500);
              break;
            }
          },true);
          document.addEventListener('click',function(){setTimeout(scanResources,350);setTimeout(scanResources,1000);setTimeout(scanResources,2200)},false);
          document.addEventListener('submit',function(e){
            var f=e.target;if(!f||!f.action)return;
            var submitter=e.submitter;
            var label=((f.innerText||'')+' '+(f.getAttribute('aria-label')||'')+' '+(submitter?(submitter.innerText||submitter.value||''):'')).toLowerCase();
            if(!/download|save file|get file|direct link|continue|generate/i.test(label))return;
            var method=String((submitter&&submitter.formMethod)||f.method||'get').toLowerCase();
            if(method==='get'){send(f.action,{},true);return;}
            if(method==='post'){
              try{
                var params=new URLSearchParams();var data=new FormData(f);
                data.forEach(function(v,k){if(typeof v==='string')params.append(k,v)});
                send(f.action,{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8'},true,params.toString());
              }catch(_){DroxDownload.postMessage('__DROX_DOWNLOAD_INTENT__')}
            }
          },true);
          if(window.open){window.open=function(u){if(u){try{var target=new URL(u,location.href);if(/^https?:$/.test(target.protocol))DroxDownload.postMessage('__DROX_NEW_TAB__:'+target.href)}catch(_){}}return null}}
          function saveBlobUrl(raw,name){try{fetch(raw).then(function(r){return r.blob()}).then(function(blob){var reader=new FileReader();reader.onload=function(){var data=String(reader.result||'').split(',')[1]||'';var id='blob_'+Date.now()+'_'+Math.random().toString(36).slice(2);DroxDownload.postMessage(JSON.stringify({type:'blobStart',id:id,filename:name||'drox_blob.bin',size:blob.size}));var chunk=128*1024;for(var i=0;i<data.length;i+=chunk)DroxDownload.postMessage(JSON.stringify({type:'blobChunk',id:id,data:data.slice(i,i+chunk)}));DroxDownload.postMessage(JSON.stringify({type:'blobEnd',id:id}))};reader.readAsDataURL(blob)})}catch(_){}}
          document.addEventListener('click',function(e){var a=e.target&&e.target.closest?e.target.closest('a[download]'):null;if(a){if(/^blob:/i.test(a.href)){e.preventDefault();saveBlobUrl(a.href,a.download||'drox_blob.bin')}else send(a.href,{'Content-Disposition':'attachment; filename="'+(a.download||'')+'"'},true)}},true);
        })();''');
        final title = await ctrl.getTitle();
        t.title = title == null || title.isEmpty ? (Uri.tryParse(u)?.host ?? 'Website') : title;
        t.loading = false; t.back = await ctrl.canGoBack(); t.forward = await ctrl.canGoForward();
        if (!mounted) return;
        setState(() { if (tab == t) address.text = u; });
        if (u.startsWith('http') && !t.isPrivate) { history.removeWhere((e) => e['url'] == u); history.insert(0, {'title': t.title, 'url': u}); if (history.length > 100) history.removeLast(); _saveHistory(); }
      },
      onWebResourceError: (_) { t.loading = false; if (mounted) setState(() {}); },
    ));
    if (mounted) setState(() {});
    if (url == 'https://www.google.com' || url == 'https://www.google.com/') {
      await ctrl.loadHtmlString(_homePageHtml, baseUrl: 'https://www.google.com/');
    } else {
      await ctrl.loadRequest(Uri.parse(url));
    }
  }
  final Set<String> _promptedDownloadUrls = <String>{};
  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'অজানা';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<Map<String, String>> _withBrowserSession(String url, Map<String, String> supplied) async {
    final merged = <String, String>{...supplied};
    try {
      final cookie = await _sessionChannel.invokeMethod<String>('getCookies', {'url': url});
      if (cookie != null && cookie.isNotEmpty && !merged.keys.any((k) => k.toLowerCase() == 'cookie')) {
        merged['Cookie'] = cookie;
      }
      final nativeAgent = await _sessionChannel.invokeMethod<String>('getUserAgent');
      if (nativeAgent != null && nativeAgent.isNotEmpty && !merged.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        merged['User-Agent'] = nativeAgent;
      }
    } on PlatformException {
      // Continue with the headers captured by the page if native session access fails.
    } on MissingPluginException {
      // Older installed builds may not have the native session bridge.
    }
    return merged;
  }

  Future<void> _downloadPrompt(String url, {Map<String, String> headers = const {}, bool force = false, String? postBody}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return;
    if (_promptedDownloadUrls.contains(url)) return;
    _promptedDownloadUrls.add(url);
    if (!mounted) { _promptedDownloadUrls.remove(url); return; }

    final requestHeaders = await _withBrowserSession(url, headers);
    var finalUrl = url;
    var name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'download_file';
    try { name = Uri.decodeComponent(name); } catch (_) {}
    if (name.isEmpty || !name.contains('.')) name = 'download_file';
    var sizeBytes = -1;
    var type = 'Unknown';
    var statusNote = '';
    final manifestPath = uri.path.toLowerCase();
    final isHlsManifest = manifestPath.endsWith('.m3u8');
    final isDashManifest = manifestPath.endsWith('.mpd');
    if (isHlsManifest) {
      type = 'HLS streaming playlist';
      statusNote = 'HLS stream detected. This is a playlist, not the complete video. Full stream download and file packaging are not enabled yet.';
    } else if (isDashManifest) {
      type = 'DASH streaming manifest';
      statusNote = 'DASH stream detected. This is a manifest, not the complete video. Full stream download and file packaging are not enabled yet.';
    }
    try {
      if (!isHlsManifest && !isDashManifest && postBody == null) {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        validateStatus: (s) => s != null && s < 500,
      ));
      final response = await dio.head(url, options: Options(headers: requestHeaders));
      final responseType = (response.headers.value('content-type') ?? '').toLowerCase();
      if ((response.statusCode ?? 200) >= 400) {
        // HEAD is only a metadata probe. Many file hosts reject HEAD while
        // still allowing GET; keep the original URL and allow a download try.
        statusNote = 'Metadata check blocked (HTTP ${response.statusCode}). You can still try START; the file server will decide whether GET is allowed.';
      } else if (responseType.contains('text/html')) {
        statusNote = force
            ? 'The clicked website action returned an HTML page. START will try this URL, but it may be a landing page rather than the file.'
            : 'This link returned a web page, not a direct downloadable file.';
      } else {
        if (response.realUri.toString().startsWith('http')) finalUrl = response.realUri.toString();
        sizeBytes = int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
        type = responseType.split(';').first.isEmpty ? 'Unknown' : responseType.split(';').first;
      }
      final disposition = response.headers.value('content-disposition') ?? '';
      final encoded = RegExp(r"filename\*\s*=\s*(?:UTF-8'')?([^;]+)", caseSensitive: false).firstMatch(disposition);
      final plain = RegExp(r'filename\s*=\s*"([^"]+)"|filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(disposition);
      final headerName = encoded?.group(1) ?? plain?.group(1) ?? plain?.group(2);
      if (headerName != null && headerName.trim().isNotEmpty) {
        final raw = headerName.trim().replaceAll('"', '');
        try { name = Uri.decodeComponent(raw); } catch (_) { name = raw; }
      }
      }
    } catch (_) {
      if (!isHlsManifest && !isDashManifest) {
        statusNote = 'Metadata unavailable. The server may require a session or block HEAD; you can still try START using captured browser headers.';
      }
    }
    // Intermediate landing pages are not downloadable files. Let the browser
    // continue normally; the page detector can inspect the next download action.
    if (statusNote == 'This link returned a web page, not a direct downloadable file.' && !force && postBody == null) {
      _promptedDownloadUrls.remove(url);
      return;
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!mounted) { _promptedDownloadUrls.remove(url); return; }

    final filenameController = TextEditingController(text: name);
    var wifiOnly = false;
    var retry = true;
    var showAdvanced = false;
    final result = await showDialog<(String, bool, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) {
        final cs = Theme.of(ctx).colorScheme;
        Widget detail(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 68, child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
        );
        Widget option(String label, bool value, ValueChanged<bool> onChanged) => InkWell(
          onTap: () => refresh(() => onChanged(!value)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 30, height: 30, child: Checkbox(value: value, onChanged: (v) => refresh(() => onChanged(v ?? false)), visualDensity: VisualDensity.compact)),
              const SizedBox(width: 5),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        );
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(ctx).size.height * .88),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                child: Row(children: [
                  Expanded(child: Text('Download file!', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                  Icon(Icons.dns_outlined, color: cs.onSurfaceVariant),
                ]),
              ),
              Flexible(child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Link  •  ${uri.host}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(tooltip: 'Copy link', visualDensity: VisualDensity.compact, onPressed: () => Clipboard.setData(ClipboardData(text: finalUrl)), icon: const Icon(Icons.copy_rounded, size: 19)),
                  ]),
                  Text(finalUrl, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 14),
                  Text('Save as:', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(controller: filenameController, decoration: const InputDecoration(isDense: true, hintText: 'File name', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  detail('Type', type),
                  detail('Size', sizeBytes > 0 ? _formatFileSize(sizeBytes) : 'Unknown'),
                  detail('Website', uri.host),
                  const Divider(height: 18),
                  detail('Storage', 'Downloads / DROX'),
                  option('Wi-Fi only', wifiOnly, (v) => wifiOnly = v),
                  option('Retry if download fails', retry, (v) => retry = v),
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                    onPressed: () => refresh(() => showAdvanced = !showAdvanced),
                    icon: Icon(showAdvanced ? Icons.expand_less : Icons.tune_rounded, size: 18),
                    label: Text(showAdvanced ? 'Hide advanced info' : 'Advanced options'),
                  )),
                  if (showAdvanced) Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                    child: const Text('DROX uses resumable background downloads when supported by the server. Some websites restrict resume or segmented requests.', style: TextStyle(fontSize: 11)),
                  ),
                  if (statusNote.isNotEmpty) Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                    child: Text(statusNote, style: TextStyle(color: cs.onErrorContainer, fontSize: 12)),
                  ),
                ]),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Row(children: [
                  TextButton(onPressed: (force || statusNote.isEmpty || statusNote.startsWith('Metadata check blocked') || statusNote.startsWith('Metadata unavailable')) && filenameController.text.trim().isNotEmpty
                    ? () => Navigator.pop(ctx, (filenameController.text.trim(), wifiOnly, retry)) : null, child: const Text('ADD')),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: (force || statusNote.isEmpty || statusNote.startsWith('Metadata check blocked')) && filenameController.text.trim().isNotEmpty
                    ? () => Navigator.pop(ctx, (filenameController.text.trim(), wifiOnly, retry)) : null,
                    child: const Text('START')),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    filenameController.dispose();
    _promptedDownloadUrls.remove(url);
    if (result != null && mounted) {
      await widget.onDownload(finalUrl, result.$1, result.$2, result.$3, requestHeaders, postBody);
    }
  }

  Future<void> _addHomeShortcut() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: cs.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.primary.withValues(alpha: .45), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: .65)]),
                    ),
                    child: const Icon(Icons.add_link_rounded, color: Colors.white, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Add shortcut', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Save your favourite website', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ])),
                  IconButton(visualDensity: VisualDensity.compact, tooltip: 'Close', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 20),
                Text('WEBSITE NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurfaceVariant)),
                const SizedBox(height: 7),
                TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g. YouTube',
                    prefixIcon: const Icon(Icons.short_text_rounded),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: .45),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: cs.outlineVariant)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: cs.outlineVariant)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: cs.primary, width: 1.5)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a website name' : null,
                ),
                const SizedBox(height: 15),
                Text('WEBSITE URL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurfaceVariant)),
                const SizedBox(height: 7),
                TextFormField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'https://example.com',
                    prefixIcon: const Icon(Icons.link_rounded),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: .45),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: cs.outlineVariant)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: cs.outlineVariant)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: cs.primary, width: 1.5)),
                  ),
                  validator: (v) {
                    var raw = (v ?? '').trim();
                    if (raw.isEmpty) return 'Enter a website URL';
                    if (!raw.contains('://')) raw = 'https://$raw';
                    final uri = Uri.tryParse(raw);
                    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) return 'Enter a valid website URL';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      var raw = urlController.text.trim();
                      if (!raw.contains('://')) raw = 'https://$raw';
                      final uri = Uri.parse(raw);
                      Navigator.pop(ctx, {'title': nameController.text.trim(), 'url': uri.toString()});
                    },
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save'),
                  )),
                ]),
              ]),
            ),
          ),
        );
      },
    );
    nameController.dispose();
    urlController.dispose();
    if (result == null) return;
    shortcuts.removeWhere((e) => e['url'] == result['url']);
    shortcuts.insert(0, result);
    if (shortcuts.length > 8) shortcuts.removeLast();
    await _saveHistory();
    if (mounted) {
      await tab?.controller.loadHtmlString(_homePageHtml, baseUrl: 'https://www.google.com/');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shortcut saved to your DROX home')));
    }
  }

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
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .72, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 4, 12, 10), child: Row(children: [
        Expanded(child: Text('Your tabs • ${tabs.length}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
        IconButton(tooltip: 'New tab', onPressed: () { Navigator.pop(ctx); _newTab(); }, icon: const Icon(Icons.add_rounded)),
        IconButton(tooltip: 'Private tab', onPressed: () { Navigator.pop(ctx); _newTab('https://www.google.com', true); }, icon: const Icon(Icons.visibility_off_outlined)),
      ])),
      Expanded(child: GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.25), itemCount: tabs.length, itemBuilder: (_, i) {
        final item = tabs[i]; final cs = Theme.of(ctx).colorScheme;
        return InkWell(borderRadius: BorderRadius.circular(16), onTap: () { Navigator.pop(ctx); _select(i); },
          child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: i == active ? cs.primaryContainer.withValues(alpha: .45) : cs.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(16), border: Border.all(color: i == active ? cs.primary : cs.outlineVariant)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(item.isPrivate ? Icons.visibility_off_outlined : Icons.language_rounded, size: 18, color: cs.primary), const Spacer(), IconButton(visualDensity: VisualDensity.compact, onPressed: () { _close(i); refresh(() {}); if (tabs.isEmpty) Navigator.pop(ctx); }, icon: const Icon(Icons.close_rounded, size: 18))]),
              const Spacer(), Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 4), Text(item.isPrivate ? 'Private tab' : (Uri.tryParse(item.url)?.host ?? item.url), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ])));
      })),
    ])))));
  }
  Future<void> _action(String v) async {
    switch (v) {
      case 'new': _newTab(); break;
      case 'private': _newTab('https://www.google.com', true); break;
      case 'adblock': setState(() => adBlockEnabled = !adBlockEnabled); break;
      case 'refresh': tab?.controller.reload(); break;
      case 'history': setState(() { showHistory = true; showBookmarks = false; }); break;
      case 'bookmark': await _bookmarkCurrent(); break;
      case 'bookmarks': setState(() { showBookmarks = true; showHistory = false; }); break;
      case 'return': widget.onReturn(); break;
      case 'settings': widget.onSettings(); break;
      case 'dark': widget.onThemeTap(); break;
      case 'desktop':
        setState(() => desktopMode = !desktopMode);
        await tab?.controller.setUserAgent(desktopMode ? 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' : null);
        tab?.controller.reload(); break;
      case 'about':
        if (mounted) showAboutDialog(context: context, applicationName: 'DROX', applicationVersion: '1.0', children: const [Text('A multi-site browser download manager. Captures supported browser download links and session cookies; some protected or streaming formats may not be downloadable.')]);
        break;
    }
  }
  @override
  void dispose() { _downloadIntentTimer?.cancel(); address.dispose(); super.dispose(); }
  Widget _browserAction(IconData icon, String label, VoidCallback? onTap, {bool selected = false}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 21, color: selected ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? cs.primary : cs.onSurfaceVariant)),
        ]),
      ),
    ));
  }

  Widget _browserListTile(Map<String, String> item, {required bool bookmark}) {
    final cs = Theme.of(context).colorScheme;
    final url = item['url'] ?? '';
    final title = item['title']?.isNotEmpty == true ? item['title']! : (Uri.tryParse(url)?.host ?? 'Website');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: cs.outlineVariant.withValues(alpha: .45))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .65), borderRadius: BorderRadius.circular(13)), child: Icon(bookmark ? Icons.bookmark_rounded : Icons.history_rounded, color: cs.primary)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
        onTap: () { address.text = url; go(); },
        trailing: IconButton(tooltip: bookmark ? 'Remove bookmark' : 'Remove history', icon: const Icon(Icons.close_rounded, size: 19), onPressed: () async { (bookmark ? bookmarks : history).remove(item); await _saveHistory(); if (mounted) setState(() {}); }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = tab;
    final currentUri = Uri.tryParse(t?.url ?? '');
    final secure = currentUri?.scheme == 'https';
    return SafeArea(top: true, bottom: false, child: Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 5, 5),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 7, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Container(
                height: 43,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
                ),
                child: Row(children: [
                  const SizedBox(width: 11),
                  Icon(secure ? Icons.lock_rounded : Icons.search_rounded, size: 17, color: secure ? Colors.green : cs.onSurfaceVariant),
                  const SizedBox(width: 7),
                  Expanded(child: TextField(
                    controller: address,
                    onTap: () {
                      if (address.text.isNotEmpty) {
                        address.selection = TextSelection(baseOffset: 0, extentOffset: address.text.length);
                      }
                    },
                    onSubmitted: (_) => go(),
                    textInputAction: TextInputAction.go,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'Search or enter website address',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 13),
                    ),
                  )),
                  if (t?.loading == true)
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    IconButton(
                      tooltip: 'Go',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: go,
                      icon: Icon(Icons.arrow_forward_rounded, size: 19, color: cs.primary),
                    ),
                  const SizedBox(width: 3),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _showTabs,
                    child: Container(
                      width: 27, height: 27,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.onSurfaceVariant.withValues(alpha: .8), width: 1.4),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text('${tabs.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 3),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
              tooltip: 'Browser options',
              onSelected: _action,
              icon: const Icon(Icons.more_vert_rounded, size: 25),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new', child: ListTile(dense: true, leading: Icon(Icons.add_box_outlined), title: Text('New tab'))),
                const PopupMenuItem(value: 'private', child: ListTile(dense: true, leading: Icon(Icons.visibility_off_outlined), title: Text('New private tab'))),
                PopupMenuItem(value: 'adblock', child: ListTile(dense: true, leading: const Icon(Icons.shield_outlined), title: const Text('Ad blocking'), trailing: Icon(adBlockEnabled ? Icons.toggle_on : Icons.toggle_off))),
                const PopupMenuItem(value: 'refresh', child: ListTile(dense: true, leading: Icon(Icons.refresh_rounded), title: Text('Reload page'))),
                const PopupMenuItem(value: 'history', child: ListTile(dense: true, leading: Icon(Icons.history_rounded), title: Text('History'))),
                const PopupMenuItem(value: 'bookmark', child: ListTile(dense: true, leading: Icon(Icons.bookmark_add_outlined), title: Text('Save bookmark'))),
                const PopupMenuItem(value: 'bookmarks', child: ListTile(dense: true, leading: Icon(Icons.bookmarks_outlined), title: Text('Bookmarks'))),
                const PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.copy_rounded), title: Text('Copy page link'))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'desktop', child: ListTile(dense: true, leading: const Icon(Icons.desktop_windows_outlined), title: const Text('Desktop site'), trailing: Icon(desktopMode ? Icons.check_box : Icons.check_box_outline_blank))),
                PopupMenuItem(value: 'dark', child: ListTile(dense: true, leading: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: const Text('Switch appearance'))),
                const PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
              ],
            ),
          ]),
          if (t?.loading == true) const Padding(padding: EdgeInsets.only(top: 3), child: LinearProgressIndicator(minHeight: 1.5)),
        ]),
      ),
      Expanded(child: showBookmarks ? Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 15, 16, 8), child: Row(children: [
          const Expanded(child: Text('Saved bookmarks', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
          Text('${bookmarks.length}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ])),
        Expanded(child: bookmarks.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bookmarks_outlined, size: 48, color: cs.onSurfaceVariant.withValues(alpha: .55)), const SizedBox(height: 10), const Text('No bookmarks saved', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('Save your favourite websites from the menu.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))]))
          : ListView(children: bookmarks.map((e) => _browserListTile(e, bookmark: true)).toList())),
      ]) : showHistory ? Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 15, 16, 8), child: Row(children: [
          const Expanded(child: Text('Browsing history', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
          Text('${history.length}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          if (history.isNotEmpty) IconButton(tooltip: 'Clear history', onPressed: () async { final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Clear browsing history?'), content: const Text('This removes saved browsing history from this device.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear'))])); if (ok == true) { history.clear(); await _saveHistory(); if (mounted) setState(() {}); } }, icon: const Icon(Icons.delete_sweep_outlined)),
        ])),
        Expanded(child: history.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: .55)), const SizedBox(height: 10), const Text('No browsing history', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('Websites you visit will appear here.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))]))
          : ListView(children: history.map((e) => _browserListTile(e, bookmark: false)).toList())),
      ]) : IndexedStack(index: active, children: tabs.map((e) => WebViewWidget(controller: e.controller)).toList())),
      Container(
        decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .5))), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 10, offset: const Offset(0, -3))]),
        child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(7, 5, 7, 4), child: Row(children: [
          _browserAction(Icons.arrow_back_rounded, 'Back', t == null ? null : () async {
            if (await t.controller.canGoBack()) {
              await t.controller.goBack();
              t.back = await t.controller.canGoBack();
              t.forward = await t.controller.canGoForward();
              if (mounted) setState(() {});
            } else {
              _showTabs();
            }
          }),
          _browserAction(Icons.arrow_forward_rounded, 'Forward', t?.forward == true ? () async { await t!.controller.goForward(); } : null),
          _browserAction(Icons.home_rounded, 'Home', () { address.text = 'https://www.google.com'; tab?.controller.loadRequest(Uri.parse('https://www.google.com')); }),
          _browserAction(Icons.bookmark_outline_rounded, 'Saved', () => setState(() { showBookmarks = true; showHistory = false; }), selected: showBookmarks),
          _browserAction(Icons.download_rounded, 'Downloads', widget.onReturn),
        ]))),
      ),
    ]));
  }
}

