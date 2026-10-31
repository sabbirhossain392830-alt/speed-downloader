import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
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
    const seed = Color(0xFF00BFA6);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DROX',
      themeMode: mode,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
      home: DownloadHome(
        isDark: mode == ThemeMode.dark,
        onThemeTap: () => setState(() => mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}

class DownloadEntry {
  DownloadEntry(this.task);
  final DownloadTask task;
  double progress = 0;
  String status = 'কিউতে আছে';
  String? error;
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
  static const _historyKey = 'drox_download_history';

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = entries.map((e) => {
      'url': e.task.url,
      'filename': e.task.filename,
      'progress': e.progress,
      'status': e.status,
      'error': e.error,
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
          ..status = (item['status'] as String?) ?? 'ইতিহাসে সংরক্ষিত'
          ..error = item['error'] as String?;
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
      } else if (update is TaskStatusUpdate) {
        entry.status = _statusText(update.status);
        if (update.status == TaskStatus.failed) {
          entry.error = update.exception?.description ?? 'ডাউনলোড ব্যর্থ';
        }
        if (update.status == TaskStatus.complete) {
          entry.progress = 1;
          entry.error = null;
        }
      }
    });
    _saveHistory();
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

  String _fileName(String url) {
    final uri = Uri.parse(url);
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final decoded = Uri.decodeComponent(last);
    if (decoded.isEmpty) return 'drox_${DateTime.now().millisecondsSinceEpoch}.bin';
    return decoded.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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
    final task = DownloadTask(
      url: value,
      filename: _fileName(value),
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

  Future<void> _open(DownloadEntry entry) async {
    if (entry.status != 'সম্পন্ন') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডাউনলোড সম্পন্ন হলে ফাইল Open করা যাবে')));
      return;
    }
    final support = await getApplicationSupportDirectory();
    final path = '${support.path}/DROX/${entry.task.filename}';
    final result = await FileDownloader().openFile(filePath: path);
    if (!result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ফাইলটি খোলা যায়নি')));
    }
  }

  Future<void> _redownload(DownloadEntry entry) async {
    final task = DownloadTask(
      url: entry.task.url,
      filename: entry.task.filename,
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.bolt, color: Colors.white)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DROX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 20)),
            Text('DOWNLOAD MANAGER', style: TextStyle(fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          ]),
        ]),
        actions: [IconButton(tooltip: 'Theme', onPressed: widget.onThemeTap, icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined))],
      ),
      body: IndexedStack(index: selectedTab, children: [
        ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DOWNLOAD SMARTER', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Everything you save.\nAll in one place.', style: TextStyle(color: Colors.white, fontSize: 23, height: 1.15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(onPressed: () => setState(() => selectedTab = 1), icon: const Icon(Icons.public), label: const Text('Open Browser')),
            ]),
          ),
          const SizedBox(height: 18),
          Text('QUICK DOWNLOAD', style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: cs.primary)),
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
        const BrowserPage(),
        ListView(padding: const EdgeInsets.all(16), children: [
          const Text('DOWNLOADS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
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
          const Text('SETTINGS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (i) => setState(() => selectedTab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.public), label: 'Browser'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
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

  Widget _downloadCard(DownloadEntry entry) {
    final running = entry.status == 'ডাউনলোড হচ্ছে';
    final paused = entry.status == 'বিরতি';
    final queued = ['কিউতে আছে', 'আবার চেষ্টা করছে'].contains(entry.status);
    final failed = entry.status == 'ব্যর্থ';
    final color = entry.status == 'সম্পন্ন' ? Colors.green : Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                OutlinedButton.icon(onPressed: () => _resume(entry), icon: const Icon(Icons.play_arrow, size: 18), label: Text(failed ? 'Retry' : 'Resume')),
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
\nclass BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController web;
  final address = TextEditingController(text: 'https://www.google.com');
  bool loading = true;
  @override
  void initState() {
    super.initState();
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => loading = true),
        onPageFinished: (url) { address.text = url; if (mounted) setState(() => loading = false); },
        onWebResourceError: (_) { if (mounted) setState(() => loading = false); },
      ))
      ..loadRequest(Uri.parse('https://www.google.com'));
  }
  void go() {
    var value = address.text.trim();
    if (!value.contains('://')) {
      value = value.contains(' ') ? 'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}' : 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) web.loadRequest(uri);
  }
  @override
  void dispose() { address.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: Row(children: [
      IconButton(onPressed: () => web.goBack(), icon: const Icon(Icons.arrow_back)),
      IconButton(onPressed: () => web.goForward(), icon: const Icon(Icons.arrow_forward)),
      Expanded(child: TextField(controller: address, onSubmitted: (_) => go(), keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Search Google or enter URL', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()))),
      IconButton(onPressed: go, icon: const Icon(Icons.arrow_circle_right)),
    ])),
    if (loading) const LinearProgressIndicator(minHeight: 2),
    Expanded(child: WebViewWidget(controller: web)),
    SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      IconButton(onPressed: () => web.loadRequest(Uri.parse('https://www.google.com')), icon: const Icon(Icons.home_outlined)),
      IconButton(onPressed: () => web.reload(), icon: const Icon(Icons.refresh)),
    ])),
  ]);
}

