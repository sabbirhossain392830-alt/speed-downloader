import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    subscription = FileDownloader().updates.listen(_onUpdate);
    FileDownloader().resumeFromBackground();
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
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
    );
    setState(() {
      entries.insert(0, DownloadEntry(task));
      controller.clear();
    });
    final ok = await FileDownloader().enqueue(task);
    if (!ok && mounted) {
      setState(() => entries.firstWhere((e) => e.task.taskId == task.taskId).status = 'কিউতে যোগ করা যায়নি');
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.downloading, size: 28), SizedBox(width: 8), Text('DROX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5))]),
        actions: [IconButton(tooltip: 'Theme', onPressed: widget.onThemeTap, icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('POWERFUL DOWNLOAD MANAGER', textAlign: TextAlign.center, style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 16),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Download URL', hintText: 'https://example.com/file.zip', prefixIcon: Icon(Icons.link), border: OutlineInputBorder()),
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: adding ? null : _add,
                icon: adding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                label: const Text('Add to Download Queue'),
              )),
            ]),
          )),
          const SizedBox(height: 12),
          Row(children: [
            _stat('TOTAL', entries.length.toString(), Icons.download),
            const SizedBox(width: 8),
            _stat('ACTIVE', active.toString(), Icons.sync),
            const SizedBox(width: 8),
            _stat('DONE', done.toString(), Icons.check_circle_outline),
          ]),
          const SizedBox(height: 18),
          const Text('MY DOWNLOADS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip('All', DownloadFilter.all),
              _filterChip('Active', DownloadFilter.active),
              _filterChip('Completed', DownloadFilter.completed),
              _filterChip('Failed', DownloadFilter.failed),
            ]),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Column(children: [Icon(Icons.cloud_download_outlined, size: 54), SizedBox(height: 10), Text('এই তালিকায় কোনো ডাউনলোড নেই'), Text('উপরে direct link যোগ করুন')]))
          else
            ...visible.map(_downloadCard),
          const SizedBox(height: 16),
          Text('Background downloads use Android system services. Pause/Resume depends on server Range support. Files are stored in DROX app storage.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _filterChip(String label, DownloadFilter value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(label: Text(label), selected: filter == value, onSelected: (_) => setState(() => filter = value)),
  );

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
            Icon(entry.status == 'সম্পন্ন' ? Icons.check_circle : Icons.insert_drive_file, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(entry.task.filename, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (running)
              IconButton(onPressed: () => _pause(entry), icon: const Icon(Icons.pause_circle_outline), tooltip: 'Pause'),
            if (paused || failed)
              IconButton(onPressed: () => _resume(entry), icon: const Icon(Icons.play_circle_outline), tooltip: 'Resume / Retry'),
            if (running || paused || queued)
              IconButton(onPressed: () => _cancel(entry), icon: const Icon(Icons.close), tooltip: 'Cancel'),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: entry.progress),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(entry.error == null ? entry.status : '${entry.status}: ${entry.error}', style: Theme.of(context).textTheme.bodySmall)),
            Text('${(entry.progress * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.bodySmall),
          ]),
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
