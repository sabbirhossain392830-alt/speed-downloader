import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const DroxApp());

class DroxApp extends StatefulWidget {
  const DroxApp({super.key});

  @override
  State<DroxApp> createState() => _DroxAppState();
}

class _DroxAppState extends State<DroxApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00BFA6);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DROX',
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: DownloadHome(
        isDark: _mode == ThemeMode.dark,
        onThemeTap: () => setState(() {
          _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
      ),
    );
  }
}

enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

class DownloadTask {
  DownloadTask(this.url, this.fileName)
      : id = DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String url;
  final String fileName;
  String? path;
  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int total = -1;
  double speed = 0;
  String? error;

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
}

class DownloadHome extends StatefulWidget {
  const DownloadHome({
    super.key,
    required this.isDark,
    required this.onThemeTap,
  });

  final bool isDark;
  final VoidCallback onThemeTap;

  @override
  State<DownloadHome> createState() => _DownloadHomeState();
}

class _DownloadHomeState extends State<DownloadHome> {
  final _url = TextEditingController();
  final _dio = Dio();
  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _tokens = {};
  bool _queueRunning = false;

  @override
  void dispose() {
    _url.dispose();
    for (final token in _tokens.values) {
      token.cancel('App closed');
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _nameFor(String value) {
    final uri = Uri.parse(value);
    var name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (name.isEmpty) {
      name = 'drox_${DateTime.now().millisecondsSinceEpoch}.bin';
    }
    return Uri.decodeComponent(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  void _add() {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সঠিক HTTP/HTTPS direct link দিন')),
      );
      return;
    }
    setState(() {
      _tasks.insert(0, DownloadTask(value, _nameFor(value)));
      _url.clear();
    });
    _runQueue();
  }

  Future<void> _runQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    try {
      while (mounted) {
        final index = _tasks.indexWhere((t) => t.status == DownloadStatus.queued);
        if (index < 0) break;
        await _download(_tasks[index]);
      }
    } finally {
      _queueRunning = false;
      _refresh();
    }
  }

  Future<void> _download(DownloadTask task) async {
    final token = CancelToken();
    _tokens[task.id] = token;
    task.status = DownloadStatus.downloading;
    task.error = null;
    _refresh();

    RandomAccessFile? output;
    try {
      final dir = await getApplicationDocumentsDirectory();
      var file = File(task.path ?? '${dir.path}/${task.fileName}');
      if (task.path == null && await file.exists()) {
        final dot = task.fileName.lastIndexOf('.');
        final base = dot > 0 ? task.fileName.substring(0, dot) : task.fileName;
        final ext = dot > 0 ? task.fileName.substring(dot) : '';
        file = File('${dir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext');
      }
      task.path = file.path;
      var existing = await file.exists() ? await file.length() : 0;

      Future<Response<ResponseBody>> request({required bool range}) {
        return _dio.get<ResponseBody>(
          task.url,
          cancelToken: token,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            headers: range && existing > 0 ? {'Range': 'bytes=$existing-'} : null,
          ),
        );
      }

      var response = await request(range: true);
      if (existing > 0 && response.statusCode != HttpStatus.partialContent) {
        await file.delete();
        existing = 0;
        response = await request(range: false);
      }

      final code = response.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        throw Exception('Server response: $code');
      }

      final contentLength = int.tryParse(
            response.headers.value(Headers.contentLengthHeader) ?? '',
          ) ??
          -1;
      task.total = contentLength > 0 ? existing + contentLength : -1;
      task.received = existing;
      output = await file.open(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );

      var lastTime = DateTime.now();
      var lastBytes = task.received;
      await for (final chunk in response.data!.stream) {
        if (token.isCancelled) break;
        await output.writeFrom(chunk);
        task.received += chunk.length;
        final now = DateTime.now();
        final ms = now.difference(lastTime).inMilliseconds;
        if (ms >= 500) {
          task.speed = (task.received - lastBytes) * 1000 / ms;
          lastTime = now;
          lastBytes = task.received;
          _refresh();
        }
      }
      await output.close();
      output = null;

      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.cancelled) return;

      task.status = DownloadStatus.completed;
      task.speed = 0;
      if (task.total <= 0) task.total = task.received;
    } on DioException catch (e) {
      if (task.status != DownloadStatus.paused &&
          task.status != DownloadStatus.cancelled) {
        task.status = DownloadStatus.failed;
        task.error = e.message ?? 'Network error';
      }
    } catch (e) {
      if (task.status != DownloadStatus.paused &&
          task.status != DownloadStatus.cancelled) {
        task.status = DownloadStatus.failed;
        task.error = e.toString();
      }
    } finally {
      if (output != null) await output.close();
      _tokens.remove(task.id);
      task.speed = 0;
      _refresh();
    }
  }

  void _pause(DownloadTask task) {
    task.status = DownloadStatus.paused;
    _tokens[task.id]?.cancel('Paused by user');
    _refresh();
  }

  void _resume(DownloadTask task) {
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) return;
    setState(() {
      task.status = DownloadStatus.queued;
      task.error = null;
    });
    _runQueue();
  }

  Future<void> _cancel(DownloadTask task) async {
    task.status = DownloadStatus.cancelled;
    _tokens[task.id]?.cancel('Cancelled by user');
    if (task.path != null) {
      final file = File(task.path!);
      if (await file.exists()) await file.delete();
    }
    _refresh();
  }

  Future<void> _remove(DownloadTask task) async {
    if (task.status == DownloadStatus.downloading) return;
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
  }

  String _bytes(num n) {
    if (n < 1024) return '${n.toStringAsFixed(0)} B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _status(DownloadTask t) {
    switch (t.status) {
      case DownloadStatus.queued: return 'কিউতে আছে';
      case DownloadStatus.downloading: return 'ডাউনলোড হচ্ছে';
      case DownloadStatus.paused: return 'বিরতি দেওয়া';
      case DownloadStatus.completed: return 'সম্পন্ন';
      case DownloadStatus.failed: return 'ব্যর্থ: ${t.error ?? 'অজানা সমস্যা'}';
      case DownloadStatus.cancelled: return 'বাতিল';
    }
  }

  Widget _taskCard(DownloadTask task) {
    final active = task.status == DownloadStatus.downloading;
    final completed = task.status == DownloadStatus.completed;
    final resumable = task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                completed ? Icons.check_circle : Icons.insert_drive_file,
                color: completed ? Colors.green : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'remove') _remove(task);
                  if (value == 'cancel') _cancel(task);
                },
                itemBuilder: (_) => [
                  if (task.status != DownloadStatus.downloading)
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  if (task.status == DownloadStatus.downloading ||
                      task.status == DownloadStatus.queued)
                    const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.total > 0 ? task.progress : (active ? null : 0),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(_status(task), style: Theme.of(context).textTheme.bodySmall)),
              Text(
                task.total > 0
                    ? '${(task.progress * 100).toStringAsFixed(0)}%'
                    : _bytes(task.received),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
            if (active || task.received > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_bytes(task.received)} / ${task.total > 0 ? _bytes(task.total) : 'Unknown'}'
                '${active ? '  •  ${_bytes(task.speed)}/s' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (task.path != null && completed) ...[
              const SizedBox(height: 6),
              SelectableText(
                task.path!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (active || resumable || task.status == DownloadStatus.queued) ...[
              const SizedBox(height: 8),
              Row(children: [
                if (active)
                  OutlinedButton.icon(
                    onPressed: () => _pause(task),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (resumable)
                  FilledButton.icon(
                    onPressed: () => _resume(task),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                if (task.status == DownloadStatus.queued)
                  const Text('পরের ডাউনলোড হিসেবে অপেক্ষা করছে'),
                const Spacer(),
                if (active || task.status == DownloadStatus.queued)
                  TextButton(
                    onPressed: () => _cancel(task),
                    child: const Text('Cancel'),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _tasks.where((t) => t.status == DownloadStatus.downloading).length;
    final done = _tasks.where((t) => t.status == DownloadStatus.completed).length;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.downloading, size: 28),
          SizedBox(width: 8),
          Text('DROX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Change theme',
            onPressed: widget.onThemeTap,
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'POWERFUL DOWNLOAD MANAGER',
            textAlign: TextAlign.center,
            style: TextStyle(
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Paste direct download link',
                    hintText: 'https://example.com/file.zip',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Download'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _stat('TOTAL', _tasks.length.toString(), Icons.download),
            const SizedBox(width: 8),
            _stat('ACTIVE', running.toString(), Icons.sync),
            const SizedBox(width: 8),
            _stat('DONE', done.toString(), Icons.check_circle_outline),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(
              child: Text('DOWNLOAD QUEUE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            Text('${_tasks.length} files', style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          if (_tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Column(children: [
                Icon(Icons.cloud_download_outlined, size: 54),
                SizedBox(height: 10),
                Text('এখনো কোনো ডাউনলোড নেই'),
                Text('উপরে একটি direct link দিন'),
              ]),
            )
          else
            ..._tasks.map(_taskCard),
          const SizedBox(height: 16),
          Text(
            'Files are saved in DROX app storage. Resume works when the server supports HTTP Range requests.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(children: [
            Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      ),
    );
  }
}
