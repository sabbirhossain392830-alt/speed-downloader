import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/download_item.dart';
import '../core/download_repository.dart';
import '../engine/download_engine.dart';
import '../services/stream_download_service.dart';

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
  final DroxStreamDownloadService _streamService = DroxStreamDownloadService();
  final Map<String, int> _streamSessions = <String, int>{};

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
        final downloaded = data['downloadedBytes'];
        if (downloaded is num) item.downloadedBytes = downloaded.toInt();
        final savedState = data['state'] as String?;
        item.state = DroxDownloadState.paused;
        for (final candidate in DroxDownloadState.values) {
          if (candidate.name == savedState) item.state = candidate;
        }
        if (item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued) {
          item.state = DroxDownloadState.paused;
        }
        item.error = data['error'] as String?;
        item.isStream = data['isStream'] == true;
        if (item.isStream && item.state != DroxDownloadState.complete) {
          item.state = DroxDownloadState.failed;
          item.error = 'Stream task stopped when DROX was closed. Start it again.';
        }
        item.renamedFilename = data['displayFilename'] as String?;
        item.renamedPath = data['renamedPath'] as String?;
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

  Future<void> addStreamMedia({required String url, required String filename, DroxDownloadItem? existingItem}) async {
    final task = existingItem?.task ?? await _engine.createTask(url: url, filename: filename);
    final item = existingItem ?? (DroxDownloadItem.fromTask(task)..isStream = true);
    if (existingItem == null) _items.insert(0, item);
    item.state = DroxDownloadState.running;
    notifyListeners();
    await _persist();
    try {
      final outputPath = await _engine.filePath(task);
      final resultFuture = _streamService.download(
        manifestUrl: url,
        outputPath: outputPath,
        onSessionId: (id) => _streamSessions[item.id] = id,
        onProgress: (progress, bytes, elapsed) {
          if (item.state != DroxDownloadState.running) return;
          item.progress = progress.clamp(0.0, 1.0).toDouble();
          item.downloadedBytes = bytes;
          item.speedBytesPerSecond = elapsed > 0 ? bytes / elapsed : 0;
          notifyListeners();
          unawaited(_persist());
        },
      );
      final result = await resultFuture;
      if (item.state == DroxDownloadState.cancelled) return;
      final file = File(result.outputPath);
      if (!await file.exists() || await file.length() < 1024) {
        throw StateError('Stream output is empty or incomplete.');
      }
      final handle = await file.open();
      List<int> prefix;
      try { prefix = await handle.read(2048); } finally { await handle.close(); }
      if (_isHtmlOrChallenge(prefix)) {
        await file.delete();
        throw StateError('The server returned an HTML/security page, not media.');
      }
      final sharedPath = await _engine.moveFileToSharedDownloads(result.outputPath);
      if (sharedPath == null || sharedPath.isEmpty) {
        throw StateError('Downloaded, but could not publish to phone Downloads.');
      }
      item.renamedPath = sharedPath;
      item.progress = 1;
      item.expectedBytes = result.bytes;
      item.downloadedBytes = result.bytes;
      item.state = DroxDownloadState.complete;
      item.error = null;
    } catch (error) {
      if (item.state != DroxDownloadState.cancelled) {
        item.state = DroxDownloadState.failed;
        item.error = error.toString();
      }
    } finally {
      _streamSessions.remove(item.id);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> pause(DroxDownloadItem item) async {
    final paused = await _engine.pause(item.task);
    if (!paused) throw StateError('The server may not support pause/resume.');
    item.state = DroxDownloadState.paused;
    await _refreshDownloadedBytes(item);
    await _persist();
    notifyListeners();
  }

  Future<void> _refreshDownloadedBytes(DroxDownloadItem item) async {
    try {
      final path = item.renamedPath ?? await item.task.filePath();
      final file = File(path);
      if (!await file.exists()) return;
      final length = await file.length();
      item.downloadedBytes = length;
      if (item.expectedBytes > 0) {
        item.progress = (length / item.expectedBytes).clamp(0.0, 1.0).toDouble();
      }
    } catch (_) {
      // Keep the last progress update if the platform does not expose the
      // partial file path while a task is paused.
    }
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

  Future<void> rename(DroxDownloadItem item, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty || clean.contains('/') || clean.contains('\\')) {
      throw const FormatException('Enter a valid filename.');
    }
    final oldPath = await item.task.filePath();
    final oldFile = File(oldPath);
    if (await oldFile.exists()) {
      final dot = clean.lastIndexOf('.');
      final hasExtension = dot > 0;
      final targetName = hasExtension ? clean : clean + _extension(item.filename);
      await oldFile.rename(oldFile.parent.path + Platform.pathSeparator + targetName);
      item.renamedFilename = targetName;
      item.renamedPath = oldFile.parent.path + Platform.pathSeparator + targetName;
    } else {
      item.renamedFilename = clean.contains('.') ? clean : clean + _extension(item.filename);
    }
    await _persist();
    notifyListeners();
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  Future<void> redownload(DroxDownloadItem item) async {
    // Restart this exact list item instead of inserting a duplicate row.
    if (item.state == DroxDownloadState.running ||
        item.state == DroxDownloadState.queued ||
        item.state == DroxDownloadState.paused) {
      await _engine.cancel(item.task);
    }
    try {
      final oldPath = item.renamedPath ?? await item.task.filePath();
      final oldFile = File(oldPath);
      if (await oldFile.exists()) await oldFile.delete();
    } catch (_) {
      // A missing partial file is fine; the task will start from zero.
    }
    final filename = item.task.filename;
    final task = await _engine.createTask(url: item.url, filename: filename);
    item.task = task;
    item.renamedFilename = null;
    item.renamedPath = null;
    item.progress = 0;
    item.expectedBytes = -1;
    item.downloadedBytes = 0;
    item.speedBytesPerSecond = 0;
    item.speedSampleAt = null;
    item.speedSampleBytes = 0;
    item.error = null;
    item.state = DroxDownloadState.queued;
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

  Future<void> removeMany(List<DroxDownloadItem> selected, {bool deleteFiles = false}) async {
    for (final item in selected) {
      if (item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued || item.state == DroxDownloadState.paused) {
        await _engine.cancel(item.task);
      }
      if (deleteFiles) {
        final path = item.renamedPath ?? await item.task.filePath();
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        } else {
          throw FileSystemException('Downloaded file was not found; it was not removed from history.', path);
        }
      }
      _items.removeWhere((candidate) => candidate.id == item.id);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(DroxDownloadItem item) async {
    if (item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued || item.state == DroxDownloadState.paused) {
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
      // Negative progress values are plugin sentinels (paused/failed/canceled), not percentages.
      // Preserve the last real percentage instead of clamping a pause sentinel to zero.
      if (update.progress >= 0 && update.progress <= 1) {
        item.progress = update.progress;
      }
      if (update.hasExpectedFileSize && update.expectedFileSize > 0) {
        item.expectedBytes = update.expectedFileSize;
      }
      if (item.expectedBytes > 0 && item.progress >= 0 && item.progress <= 1) {
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
          unawaited(_publishCompletedFile(item));
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

  Future<void> _publishCompletedFile(DroxDownloadItem item) async {
    try {
      // The transfer plugin can report HTTP 200 as "complete" even when a
      // CDN has delivered an HTML login/error/Cloudflare page. Validate the
      // actual local bytes before publishing or keeping the completed state.
      final localPath = item.renamedPath ?? await _engine.filePath(item.task);
      final localFile = File(localPath);
      if (!await localFile.exists()) {
        item.state = DroxDownloadState.failed;
        item.error = 'Download engine reported completion, but the file is missing.';
        await _persist();
        notifyListeners();
        return;
      }
      final fileLength = await localFile.length();
      if (fileLength == 0) {
        item.state = DroxDownloadState.failed;
        item.error = 'The server returned an empty file.';
        await _persist();
        notifyListeners();
        return;
      }
      final handle = await localFile.open();
      List<int> prefix;
      try {
        prefix = await handle.read(2048);
      } finally {
        await handle.close();
      }
      if (_isHtmlOrChallenge(prefix)) {
        await localFile.delete();
        item.state = DroxDownloadState.failed;
        item.progress = 0;
        item.error = 'The server returned an HTML page or security challenge, not the requested file.';
        await _persist();
        notifyListeners();
        return;
      }
      final sharedPath = await _engine.moveToSharedDownloads(item.task);
      if (sharedPath != null && sharedPath.isNotEmpty) {
        item.renamedPath = sharedPath;
        await _persist();
        notifyListeners();
      } else {
        item.error = 'Downloaded, but could not move file to shared Downloads.';
        await _persist();
        notifyListeners();
      }
    } catch (error) {
      item.error = 'Could not publish file to Downloads: $error';
      await _persist();
      notifyListeners();
    }
  }

  bool _isHtmlOrChallenge(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final sample = utf8.decode(bytes.take(2048).toList(), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return sample.startsWith('<!doctype html') ||
        sample.startsWith('<html') ||
        sample.startsWith('<head') ||
        sample.startsWith('<body') ||
        sample.contains('cf-chl-') ||
        (sample.contains('cloudflare') && sample.contains('challenge'));
  }

  Future<void> _persist() => _repository.save(_items);

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }
}
