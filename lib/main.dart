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
  FileDownloader().configureNotification(
    running: const TaskNotification('DROX • Downloading', '{filename}'),
    paused: const TaskNotification('DROX • Paused', '{filename}'),
    complete: const TaskNotification('DROX • Complete', '{filename}'),
    error: const TaskNotification('DROX • Failed', '{filename}'),
    progressBar: true,
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

enum DownloadFilter { all, active, completed, failed }

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
    if (raw == null) return;
    try {
      final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final restored = data.map((item) {
        final task = DownloadTask(
          url: item['url'] as String,
          filename: item['filename'] as String,
          directory: 'DROX',
          baseDirectory: BaseDirectory.applicationSupport,
          updates: Updates.statusAndProgress,
          allowPause: true,
          retries: 3,
        );
        final entry = DownloadEntry(task)
          ..progress = (item['progress'] as num?)?.toDouble() ?? 0
          ..expectedFileSize = (item['expectedFileSize'] as num?)?.toInt() ?? -1
          ..status = (item['status'] as String?) ?? 'ইতিহাসে সংরক্ষিত'
          ..error = item['error'] as String?
          ..sharedPath = item['sharedPath'] as String?;
        if (entry.status == 'ডাউনলোড হচ্ছে' || entry.status == 'কিউতে আছে' || entry.status == 'আবার চেষ্টা করছে') {
          entry.status = 'অ্যাপ পুনরায় খুলুন—ডাউনলোডের অবস্থা যাচাই করুন';
        }
        return entry;
      }).toList();
      if (mounted) setState(() => entries.addAll(restored));
    } catch (_) {
      await prefs.remove(_historyKey);
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

  Future<void> _add({String? suggestedFilename, int retries = 5}) async {
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
      filename: suggestedFilename == null || suggestedFilename.trim().isEmpty ? details.$2 : _safeFileName(suggestedFilename.trim()),
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: retries,
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
    final details = await _downloadDetails(entry.task.url);
    final task = DownloadTask(
      url: details.$1,
      filename: details.$2,
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
        titleSpacing: 20,
        title: const Text(
          'DROX',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 22),
        ),
        actions: [
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
        ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
          const SizedBox(height: 4),
          Row(children: [
            _homeCategory('All', entries.length, DownloadFilter.all, Icons.apps_rounded),
            _homeCategory('Downloading', active, DownloadFilter.active, Icons.downloading_rounded),
            _homeCategory('Finished', done, DownloadFilter.completed, Icons.check_circle_outline_rounded),
            _homeCategory('Error', entries.where((e) => ['ব্যর্থ','বাতিল','কিউতে যোগ করা যায়নি','যাচাই ব্যর্থ'].contains(e.status)).length, DownloadFilter.failed, Icons.error_outline_rounded),
          ]),
          const SizedBox(height: 14),
          TextField(controller: controller, keyboardType: TextInputType.url, onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              hintText: 'Paste download link or URL',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(tooltip: 'Quick download', onPressed: adding ? null : _add, icon: adding ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.download_rounded)),
              filled: true, fillColor: cs.surfaceContainerHighest.withValues(alpha: .45),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            )),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('${entries.length} files', style: Theme.of(context).textTheme.labelSmall),
          ]),
          if (visible.isEmpty)
            Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .28), borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant.withValues(alpha: .5))),
              child: Column(children: [
                Icon(Icons.downloading_rounded, size: 46, color: cs.primary),
                const SizedBox(height: 10),
                const Text('No downloads yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 5),
                Text('Browse websites or paste a direct link to start.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),

              ]),
            )
          else ...visible.map(_downloadCard),
        ]),
        BrowserPage(key: browserKey, isDark: widget.isDark, onThemeTap: widget.onThemeTap, onReturn: () => setState(() => selectedTab = 0), onSettings: () => setState(() => selectedTab = 3), onDownload: (url, filename, wifiOnly, retry) async { if (wifiOnly) await _setWifiOnly(true); controller.text = url; await _add(suggestedFilename: filename, retries: retry ? 5 : 0); }),
        ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Text('Downloads', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
            const Spacer(),
            Text('${entries.length} files', style: Theme.of(context).textTheme.labelMedium),
            IconButton(tooltip: 'Quick download', onPressed: _quickDownloadDialog, icon: const Icon(Icons.add_link_rounded)),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _filterChip('All', DownloadFilter.all), _filterChip('Active', DownloadFilter.active),
            _filterChip('Completed', DownloadFilter.completed), _filterChip('Failed', DownloadFilter.failed),
          ])),
          const SizedBox(height: 10),
          if (visible.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No downloads here yet')))
          else ...visible.map(_downloadCard),
        ]),
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

  Widget _homeCategory(String label, int count, DownloadFilter value, IconData icon) {
    final selected = filter == value;
    final cs = Theme.of(context).colorScheme;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => filter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
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
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_fileIcon(entry.task.filename), color: statusColor, size: 26),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.task.filename, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 5),
              Text('${_fileType(entry.task.filename)}  •  ${_formatBytes(entry.expectedFileSize)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ])),
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'open') _open(entry);
                if (value == 'redownload') _redownload(entry);
                if (value == 'remove') _remove(entry);
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'open', enabled: completed, child: const ListTile(dense: true, leading: Icon(Icons.open_in_new), title: Text('Open file'))),
                const PopupMenuItem(value: 'redownload', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Download again'))),
                const PopupMenuItem(value: 'remove', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Remove from list'))),
              ],
            ),
          ]),
          const SizedBox(height: 15),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 9, letterSpacing: .8, fontWeight: FontWeight.w900)),
            ),
            const Spacer(),
            Text('$percent%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: statusColor)),
          ]),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: completed ? 1 : entry.progress,
              minHeight: 7,
              backgroundColor: cs.surfaceContainerHighest,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
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
            const SizedBox(height: 12),
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
              width: 42,
              height: 42,
              child: Icon(
                icon,
                size: 22,
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
  final Future<void> Function(String url, String filename, bool wifiOnly, bool retry) onDownload;
  final bool isDark;
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
  void initState() { super.initState(); _loadHistory(); _newTab(); }
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
          function downloadIntent(el){
            if(!el)return false;
            var label=((el.innerText||el.textContent||'')+' '+(el.getAttribute('aria-label')||'')+' '+(el.getAttribute('title')||'')).toLowerCase();
            var attrs=['href','data-href','data-url','data-download-url','data-download','data-file','data-link','data-target','data-src','data-id','onclick'];
            var hasTarget=attrs.some(function(k){return !!el.getAttribute(k)});
            return el.hasAttribute('download')||(/download|save file|get file|direct link|one click|fastest|high.?speed|fsl|gp high|server/i.test(label)&&(hasTarget||el.tagName==='BUTTON'||el.getAttribute('role')==='button'||getComputedStyle(el).cursor==='pointer'));
          }
          function candidate(el){
            if(!el)return null;
            var attrs=['href','data-href','data-url','data-download-url','data-download','data-file','data-link','data-target','data-src','data-id'];
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
            for(var i=0;i<nodes.length&&i<8;i++){
              var el=nodes[i];if(!el||el.nodeType!==1)continue;
              if(!downloadIntent(el))continue;
              var u=candidate(el);
              if(u)send(u);
              setTimeout(scanResources,250);
              setTimeout(scanResources,900);
              break;
            }
          },true);
          document.addEventListener('submit',function(e){
            var f=e.target;if(!f||!f.action)return;
            var label=((f.innerText||'')+' '+(f.getAttribute('aria-label')||'')).toLowerCase();
            if(/download|save file|get file/i.test(label))send(f.action);
          },true);
          if(window.open){var originalOpen=window.open;window.open=function(u){if(u)send(u);return originalOpen.apply(this,arguments)}}
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
    if (bytes == null || bytes <= 0) return 'অজানা';
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
      if (!isHlsManifest && !isDashManifest) {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        validateStatus: (s) => s != null && s < 500,
      ));
      final response = await dio.head(url);
      final responseType = (response.headers.value('content-type') ?? '').toLowerCase();
      if ((response.statusCode ?? 200) >= 400) {
        // HEAD is only a metadata probe. Many file hosts reject HEAD while
        // still allowing GET; keep the original URL and allow a download try.
        statusNote = 'Metadata check blocked (HTTP ${response.statusCode}). You can still try START; the file server will decide whether GET is allowed.';
      } else if (responseType.contains('text/html')) {
        statusNote = 'This link returned a web page, not a direct downloadable file.';
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
        statusNote = 'File information is unavailable. The server may require a session or may not support metadata requests.';
      }
    }
    // Intermediate landing pages are not downloadable files. Let the browser
    // continue normally; the page detector can inspect the next download action.
    if (statusNote == 'This link returned a web page, not a direct downloadable file.') {
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
                  TextButton(onPressed: (statusNote.isEmpty || statusNote.startsWith('Metadata check blocked')) && filenameController.text.trim().isNotEmpty
                    ? () => Navigator.pop(ctx, (filenameController.text.trim(), wifiOnly, retry)) : null, child: const Text('ADD')),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: (statusNote.isEmpty || statusNote.startsWith('Metadata check blocked')) && filenameController.text.trim().isNotEmpty
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
      await widget.onDownload(finalUrl, result.$1, result.$2, result.$3);
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
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: SizedBox(height: 350, child: Column(children: [
      ListTile(title: Text('Open pages (' + tabs.length.toString() + ')'), trailing: IconButton(onPressed: () { Navigator.pop(ctx); _newTab(); }, icon: const Icon(Icons.add))),
      Expanded(child: ListView.builder(itemCount: tabs.length, itemBuilder: (_, i) => ListTile(selected: i == active, leading: const Icon(Icons.language), title: Text(tabs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(tabs[i].url, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () { Navigator.pop(ctx); _select(i); }, trailing: IconButton(onPressed: () { Navigator.pop(ctx); _close(i); }, icon: const Icon(Icons.close))))),
    ]))));
  }
  Future<void> _action(String v) async {
    switch (v) {
      case 'new': _newTab(); break;
      case 'adblock': setState(() => adBlockEnabled = !adBlockEnabled); break;
      case 'refresh': tab?.controller.reload(); break;
      case 'history': setState(() => showHistory = true); break;
      case 'return': widget.onReturn(); break;
      case 'settings': widget.onSettings(); break;
      case 'dark': widget.onThemeTap(); break;
      case 'desktop':
        setState(() => desktopMode = !desktopMode);
        await tab?.controller.setUserAgent(desktopMode ? 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' : null);
        tab?.controller.reload(); break;
      case 'about':
        if (mounted) showAboutDialog(context: context, applicationName: 'DROX', applicationVersion: '1.0', children: const [Text('A simple Android download manager.')]);
        break;
    }
  }
  @override
  void dispose() { address.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final t = tab;
    return SafeArea(top: true, bottom: false, child: Column(children: [
      Material(color: cs.surface, elevation: 1, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 6, 8), child: Row(children: [
        Expanded(child: Container(height: 46, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: .45))), child: TextField(controller: address, onSubmitted: (_) => go(), textInputAction: TextInputAction.go, keyboardType: TextInputType.url, decoration: InputDecoration(hintText: 'Search or enter URL', prefixIcon: const Icon(Icons.search_rounded, size: 20), suffixIcon: IconButton(onPressed: go, icon: const Icon(Icons.arrow_forward_rounded, size: 20)), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 11), border: InputBorder.none)))),
        PopupMenuButton<String>(tooltip: 'Browser menu', icon: const Icon(Icons.more_vert), onSelected: _action, itemBuilder: (_) => [
          const PopupMenuItem(value: 'new', child: ListTile(dense: true, leading: Icon(Icons.add_box_outlined), title: Text('New Tab'))),
          PopupMenuItem(value: 'adblock', child: ListTile(dense: true, leading: Icon(Icons.shield_outlined), title: Text('Ad Block'), trailing: Icon(adBlockEnabled ? Icons.toggle_on : Icons.toggle_off))),
          const PopupMenuItem(value: 'refresh', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Refresh'))),
          const PopupMenuItem(value: 'history', child: ListTile(dense: true, leading: Icon(Icons.history), title: Text('History'))),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'return', child: ListTile(dense: true, leading: Icon(Icons.home_outlined), title: Text('Return to DROX'))),
          const PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
          PopupMenuItem(value: 'dark', child: ListTile(dense: true, leading: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: const Text('Dark Mode'), trailing: Icon(widget.isDark ? Icons.check : Icons.circle_outlined))),
          PopupMenuItem(value: 'desktop', child: ListTile(dense: true, leading: const Icon(Icons.desktop_windows_outlined), title: const Text('Desktop Mode'), trailing: Icon(desktopMode ? Icons.check_box : Icons.check_box_outline_blank))),
          const PopupMenuItem(value: 'about', child: ListTile(dense: true, leading: Icon(Icons.info_outline), title: Text('About'))),
        ]),
      ]))),
      if (t?.loading == true) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: showHistory ? ListView(children: [
        const ListTile(title: Text('BROWSING HISTORY', style: TextStyle(fontWeight: FontWeight.bold))),
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

