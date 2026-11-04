import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/download_item.dart';
import '../core/download_repository.dart';
import '../engine/download_engine.dart';

/// Owns download state independently of Home and Browser widgets.
class DownloadController extends ChangeNotifier {
  DownloadController({
    DownloadEngine? engine,
    DownloadRepository? repository,
  })  : _engine = engine ?? DownloadEngine(),
        _repository = repository ?? DownloadRepository();

  final DownloadEngine _engine;
  final DownloadRepository _repository;
  final List<DroxDownloadItem> _items = [];
  StreamSubscription<TaskUpdate>? _updates;
  bool _initialized = false;
  bool _busy = false;

  List<DroxDownloadItem> get items => List.unmodifiable(_items);
  bool get isBusy => _busy;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      _updates ??= _engine.updates.listen(_onTaskUpdate);
      await _engine.initialize();
      var saved = await _repository.load();
      var legacyImported = false;
      if (saved.isEmpty) {
        // Import the previous manager's history once. Keep the legacy key
        // until the migrated v2 snapshot has been persisted successfully.
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('drox_download_history');
        if (raw != null && raw.isNotEmpty) {
          try {
            final legacy = (jsonDecode(raw) as List)
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry));
            saved = legacy.map((entry) {
              final status = entry['status'] as String? ?? '';
              final state = switch (status) {
                'সম্পন্ন' => 'complete',
                'ব্যর্থ' || 'যাচাই ব্যর্থ' || 'কিউতে যোগ করা যায়নি' => 'failed',
                'বাতিল' => 'cancelled',
                _ => 'paused',
              };
              return <String, dynamic>{
                'id': entry['taskId'],
                'url': entry['url'],
                'filename': entry['filename'],
                'state': state,
                'progress': entry['progress'],
                'expectedBytes': entry['expectedFileSize'],
                'error': entry['error'],
              };
            }).where((entry) => entry['url'] is String && entry['filename'] is String).toList();
            legacyImported = true;
          } catch (_) {
            // Preserve unreadable legacy data for manual recovery.
          }
        }
      }
      for (final data in saved) {
        final url = data['url'] as String?;
        final filename = data['filename'] as String?;
        if (url == null || filename == null) continue;
        final task = await _engine.createTask(url: url, filename: filename, taskId: data['id'] as String?);
        final item = DroxDownloadItem(task: task);
        final progress = data['progress'];
        if (progress is num) item.progress = progress.toDouble().clamp(0, 1).toDouble();
        final expected = data['expectedBytes'];
        if (expected is num) item.expectedBytes = expected.toInt();
        final savedState = data['state'] as String?;
        item.state = DroxDownloadState.paused;
        for (final candidate in DroxDownloadState.values) {
          if (candidate.name == savedState) item.state = candidate;
        }
        if (item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued) {
          item.state = DroxDownloadState.paused;
        }
        item.error = data['error'] as String?;
        _items.add(item);
      }
      _initialized = true;
      await _persist();
      if (legacyImported) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('drox_download_history');
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> addDirectMedia({
    required String url,
    required String filename,
  }) async {
    final task = await _engine.createTask(url: url, filename: filename);
    final item = DroxDownloadItem.fromTask(task);
    _items.insert(0, item);
    notifyListeners();
    await _persist();
    try {
      await _engine.enqueue(task);
    } catch (error) {
      item.state = DroxDownloadState.failed;
      item.error = error.toString();
      await _persist();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> pause(DroxDownloadItem item) async {
    final paused = await _engine.pause(item.task);
    if (!paused) throw StateError('The server may not support pause/resume.');
    item.state = DroxDownloadState.paused;
    await _persist();
    notifyListeners();
  }

  Future<void> resume(DroxDownloadItem item) async {
    final resumed = await _engine.resume(item.task);
    if (!resumed) throw StateError('This download could not be resumed.');
    item.state = DroxDownloadState.running;
    item.error = null;
    await _persist();
    notifyListeners();
  }

  Future<void> cancel(DroxDownloadItem item) async {
    await _engine.cancel(item.task);
    item.state = DroxDownloadState.cancelled;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(DroxDownloadItem item) async {
    if (item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued) {
      await _engine.cancel(item.task);
    }
    _items.removeWhere((candidate) => candidate.id == item.id);
    await _persist();
    notifyListeners();
  }

  void _onTaskUpdate(TaskUpdate update) {
    final index = _items.indexWhere((item) => item.id == update.task.taskId);
    if (index < 0) return;
    final item = _items[index];
    if (update is TaskProgressUpdate) {
      item.progress = update.progress.clamp(0, 1).toDouble();
      if (update.hasExpectedFileSize) item.expectedBytes = update.expectedFileSize;
      if (item.expectedBytes > 0) {
        final now = DateTime.now();
        final currentBytes = (item.progress * item.expectedBytes).round();
        item.downloadedBytes = currentBytes;
        final sampleAt = item.speedSampleAt;
        if (sampleAt == null) {
          item.speedSampleAt = now;
          item.speedSampleBytes = currentBytes;
        } else {
          final elapsedMs = now.difference(sampleAt).inMilliseconds;
          if (elapsedMs >= 700) {
            final delta = currentBytes - item.speedSampleBytes;
            if (delta >= 0) {
              item.speedBytesPerSecond = delta * 1000 / elapsedMs;
              item.speedSampleAt = now;
              item.speedSampleBytes = currentBytes;
            }
          }
        }
      }
    } else if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.enqueued:
        case TaskStatus.waitingToRetry:
          item.state = DroxDownloadState.queued;
          break;
        case TaskStatus.running:
          item.state = DroxDownloadState.running;
          break;
        case TaskStatus.paused:
          item.state = DroxDownloadState.paused;
          break;
        case TaskStatus.complete:
          item.state = DroxDownloadState.complete;
          item.progress = 1;
          item.error = null;
          break;
        case TaskStatus.failed:
        case TaskStatus.notFound:
          item.state = DroxDownloadState.failed;
          item.error = update.exception?.description ?? 'Download failed.';
          break;
        case TaskStatus.canceled:
          item.state = DroxDownloadState.cancelled;
          break;
      }
    }
    notifyListeners();
    _persist();
  }

  Future<void> _persist() => _repository.save(_items);

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }
}
