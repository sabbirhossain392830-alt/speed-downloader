import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  final controller = TextEditingController();
  final List<DownloadEntry> entries = [];
  StreamSubscription<TaskUpdate>? subscription;
  DownloadFilter filter = DownloadFilter.all;
  bool adding = false;
  int selectedTab = 0;
  final GlobalKey<_BrowserPageState> browserKey = GlobalKey<_BrowserPageState>();
  static const _historyKey = 'drox_download_history';

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
    subscription = FileDownloader().updates.listen(_onUpdate);
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
      retries: 3,
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
      retries: 3,
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
        title: Row(children: [
          const DroxLogoMark(size: 42),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DROX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 20)),
            Text('DOWNLOAD MANAGER', style: TextStyle(fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          ]),
        ]),
        actions: [IconButton(tooltip: 'Theme', onPressed: widget.onThemeTap, icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined))],
      ),
      body: IndexedStack(index: selectedTab, children: [
        ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF087CF0), Color(0xFF07346B), Color(0xFF101C32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [DroxLogoMark(size: 54), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('DROX PREMIUM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.3)), Text('DOWNLOAD • BROWSE • MANAGE', style: TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w700))]))]),
              const SizedBox(height: 16),
              const Text('Your browser.\nYour download manager.', style: TextStyle(color: Colors.white, fontSize: 21, height: 1.15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(onPressed: () => setState(() => selectedTab = 1), icon: const Icon(Icons.public), label: const Text('Open Browser')),
            ]),
          ),
          const SizedBox(height: 18),
          Text('ADD DOWNLOAD LINK', style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: cs.primary)),
          const SizedBox(height: 9),
          Card(
            elevation: 0,
            child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
              TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Paste a download link', hintText: 'https://example.com/file.zip', prefixIcon: Icon(Icons.link), border: OutlineInputBorder())),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: adding ? null : _add, icon: adding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), label: const Text('Add Download'))),
            ])),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _stat('TOTAL', entries.length.toString(), Icons.download_rounded),
            const SizedBox(width: 8), _stat('ACTIVE', active.toString(), Icons.downloading),
            const SizedBox(width: 8), _stat('DONE', done.toString(), Icons.check_circle_outline),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('YOUR DOWNLOADS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            TextButton(onPressed: () => setState(() => selectedTab = 2), child: const Text('View all')),
          ]),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _filterChip('All', DownloadFilter.all), _filterChip('Active', DownloadFilter.active),
            _filterChip('Completed', DownloadFilter.completed), _filterChip('Failed', DownloadFilter.failed),
          ])),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Column(children: [
              Icon(Icons.cloud_download_outlined, size: 48, color: cs.primary.withValues(alpha: .7)),
              const SizedBox(height: 10), const Text('No downloads yet', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4), Text('Paste a direct link above or browse the web.', style: Theme.of(context).textTheme.bodySmall),
            ]))
          else ...visible.map(_downloadCard),
        ]),
        BrowserPage(key: browserKey, isDark: widget.isDark, onThemeTap: widget.onThemeTap, onReturn: () => setState(() => selectedTab = 0), onSettings: () => setState(() => selectedTab = 3), onDownload: (url) { controller.text = url; _add(); }),
        ListView(padding: const EdgeInsets.all(16), children: [
          const Row(children: [DroxLogoMark(size: 34), SizedBox(width: 10), Text('Downloads', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20))]),
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _filterChip('All', DownloadFilter.all), _filterChip('Active', DownloadFilter.active),
            _filterChip('Completed', DownloadFilter.completed), _filterChip('Failed', DownloadFilter.failed),
          ])),
          const SizedBox(height: 10),
          if (visible.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No downloads here yet')))
          else ...visible.map(_downloadCard),
        ]),
        ListView(padding: const EdgeInsets.all(16), children: [
          const Row(children: [DroxLogoMark(size: 34), SizedBox(width: 10), Text('Settings', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20))]),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Appearance'), subtitle: Text(widget.isDark ? 'Dark theme' : 'Light theme'), trailing: Switch(value: widget.isDark, onChanged: (_) => widget.onThemeTap())),
            const Divider(height: 1),
            const ListTile(leading: Icon(Icons.folder_outlined), title: Text('Storage'), subtitle: Text('DROX app storage')),
            const Divider(height: 1),
            const ListTile(leading: Icon(Icons.info_outline), title: Text('About DROX'), subtitle: Text('Powerful Download Manager')),
          ])),
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
    final failed = entry.status == 'ব্যর্থ';
    final color = entry.status == 'সম্পন্ন' ? Colors.green : Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .55))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_fileIcon(entry.task.filename), color: color, size: 30),
            const SizedBox(width: 10),
            Expanded(child: Text(entry.task.filename, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'open') _open(entry);
                if (value == 'redownload') _redownload(entry);
                if (value == 'remove') _remove(entry);
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'open', enabled: entry.status == 'সম্পন্ন', child: const ListTile(dense: true, leading: Icon(Icons.open_in_new), title: Text('Open'))),
                const PopupMenuItem(value: 'redownload', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Redownload'))),
                const PopupMenuItem(value: 'remove', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Remove'))),
              ],
            ),
          ]),
          const SizedBox(height: 4),
          Text('${_fileType(entry.task.filename)}  •  ${_formatBytes(entry.expectedFileSize)}', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(
            entry.expectedFileSize > 0
                ? '${_formatBytes((entry.progress * entry.expectedFileSize).round())} / ${_formatBytes(entry.expectedFileSize)} downloaded'
                : (entry.progress > 0 ? 'মোট সাইজ সার্ভার জানায়নি • ${ (entry.progress * 100).toStringAsFixed(0) }% সম্পন্ন' : 'ডাউনলোডের পরিমাণ হিসাব হচ্ছে…'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: entry.progress),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(entry.error == null ? entry.status : '${entry.status}: ${entry.error}', style: Theme.of(context).textTheme.bodySmall)),
            Text('${(entry.progress * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.bodySmall),
          ]),
          if (running || paused || queued || failed) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (running)
                OutlinedButton.icon(onPressed: () => _pause(entry), icon: const Icon(Icons.pause, size: 18), label: const Text('Pause')),
              if (paused || failed || queued)
                OutlinedButton.icon(onPressed: () => failed ? _redownload(entry) : _resume(entry), icon: Icon(failed ? Icons.refresh : Icons.play_arrow, size: 18), label: Text(failed ? 'Retry' : 'Resume')),
              if (running || paused || queued)
                TextButton.icon(onPressed: () => _cancel(entry), icon: const Icon(Icons.close, size: 18), label: const Text('Cancel')),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Expanded(
    child: Card(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(children: [Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: Theme.of(context).textTheme.labelSmall)]),
    )),
  );
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.onDownload, required this.isDark, required this.onThemeTap, required this.onReturn, required this.onSettings});
  final ValueChanged<String> onDownload;
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
          function send(raw){var u=valid(raw);if(!u||seen[u])return;seen[u]=1;DroxDownload.postMessage(u);setTimeout(function(){delete seen[u]},8000)}
          function mediaSources(v){var list=[v.currentSrc,v.src];v.querySelectorAll('source[src]').forEach(function(s){list.push(s.src)});list.forEach(function(u){if(u)send(u)})}
          function scan(){document.querySelectorAll('video,audio').forEach(function(v){
            if(v.__droxBound)return;v.__droxBound=true;
            v.addEventListener('play',function(){mediaSources(v)});
            v.addEventListener('loadedmetadata',function(){mediaSources(v)});
            v.addEventListener('canplay',function(){mediaSources(v)});
            v.addEventListener('loadstart',function(){mediaSources(v)});
            mediaSources(v);
          })}
          function scanResources(){try{performance.getEntriesByType('resource').forEach(function(e){if(exts.test(e.name))send(e.name)})}catch(_){}}
          function scanFrames(){document.querySelectorAll('iframe').forEach(function(f){try{if(f.contentDocument){f.contentDocument.querySelectorAll('video,audio').forEach(function(v){mediaSources(v)})}}catch(_){}})}
          if(window.fetch){var originalFetch=window.fetch;window.fetch=function(){var p=originalFetch.apply(this,arguments);try{var u=typeof arguments[0]==='string'?arguments[0]:arguments[0].url; p.then(function(r){var ct=r.headers.get('content-type')||'';if(mediaTypes.test(ct)||exts.test(u||''))send(u)})}catch(_){}return p}}
          if(window.XMLHttpRequest){var originalOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){this.__droxUrl=u;return originalOpen.apply(this,arguments)};var originalSend=XMLHttpRequest.prototype.send;XMLHttpRequest.prototype.send=function(){this.addEventListener('load',function(){var ct=this.getResponseHeader('content-type')||'';if(mediaTypes.test(ct)||exts.test(this.__droxUrl||''))send(this.responseURL||this.__droxUrl)});return originalSend.apply(this,arguments)}}
          scan();new MutationObserver(function(){scan();scanResources();scanFrames()}).observe(document.documentElement,{childList:true,subtree:true});
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
      Material(color: cs.surface, elevation: 2, child: Padding(padding: const EdgeInsets.fromLTRB(8, 6, 2, 6), child: Row(children: [
        Material(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), child: InkWell(onTap: _showTabs, borderRadius: BorderRadius.circular(10), child: SizedBox(width: 40, height: 42, child: Center(child: Text(tabs.length.toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))))),
        const SizedBox(width: 7),
        Expanded(child: Container(height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)), child: TextField(controller: address, onSubmitted: (_) => go(), textInputAction: TextInputAction.go, keyboardType: TextInputType.url, decoration: InputDecoration(hintText: 'Search or enter URL', prefixIcon: const Icon(Icons.search, size: 19), suffixIcon: IconButton(onPressed: go, icon: const Icon(Icons.arrow_forward, size: 19)), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10), border: InputBorder.none)))),
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
    ]));
  }
}

