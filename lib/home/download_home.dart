import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browser/browser_page.dart';
import '../downloads/download_models.dart';
import '../downloads/screens/download_center_screen.dart';
import '../notifications/download_notifications.dart';
import '../shared/widgets/drox_widgets.dart';

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

  static const MethodChannel _notificationMethod = MethodChannel('drox/notifications');
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
    setState(() => selectedTab = 0);
    await downloadCenterKey.currentState?.acceptSharedUrl(shared);
  }

  final controller = TextEditingController();
  final List<DownloadEntry> entries = [];
  final Set<String> _selectedTaskIds = <String>{};
  StreamSubscription<TaskUpdate>? subscription;
  Timer? _historySaveTimer;
  DateTime? _lastProgressUiUpdateAt;
  DownloadFilter filter = DownloadFilter.all;
  bool searching = false;
  final TextEditingController searchController = TextEditingController();
  bool adding = false;
  bool _fabExpanded = false;
  bool wifiOnly = false;
  bool notificationsEnabled = false;
  int selectedTab = 0;
  final GlobalKey<BrowserPageState> browserKey = GlobalKey<BrowserPageState>();
  final GlobalKey<DownloadCenterScreenState> downloadCenterKey = GlobalKey<DownloadCenterScreenState>();
  static const _historyKey = 'drox_download_history';

  Future<void> _loadNotificationSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSavedChoice = prefs.containsKey('drox_notifications_enabled');
    var enabled = prefs.getBool('drox_notifications_enabled') ?? true;
    // Enable per-download notifications on first launch, asking Android for
    // permission once. Respect an explicit previous user choice thereafter.
    if (enabled) {
      var status = await FileDownloader().permissions.status(PermissionType.notifications);
      if (status != PermissionStatus.granted) {
        status = await FileDownloader().permissions.request(PermissionType.notifications);
      }
      if (status != PermissionStatus.granted) enabled = false;
    }
    if (!hasSavedChoice) await prefs.setBool('drox_notifications_enabled', enabled);
    if (mounted) setState(() => notificationsEnabled = enabled);
    configureDroxNotifications(enabled, bangla: widget.isBangla);
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
    configureDroxNotifications(enabled, bangla: widget.isBangla);
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
    final restoredUrls = <String>{};
    final savedItems = <Map<String, dynamic>>[];
    final savedIdByUrl = <String, String>{};

    // Read the locally saved current task IDs first. Redownload replaces the
    // task ID, so an older native record for the same URL must never be shown
    // beside the new one after the app is reopened.
    if (raw != null) {
      try {
        final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        savedItems.addAll(data);
        for (final item in data) {
          final url = item['url'] as String?;
          final id = item['taskId'] as String?;
          if (url != null && id != null) savedIdByUrl.putIfAbsent(url, () => id);
        }
      } catch (_) {
        // Keep native records available if local history is temporarily unreadable.
      }
    }

    // Reconnect to native records, but discard stale duplicate records for a
    // URL when the saved history points at a newer task ID.
    try {
      final records = await FileDownloader().database.allRecords();
      for (final record in records) {
        if (record.task is! DownloadTask) continue;
        final task = record.task as DownloadTask;
        final savedId = savedIdByUrl[task.url];
        final staleTask = (savedId != null && savedId != task.taskId) ||
            restoredUrls.contains(task.url);
        if (staleTask) {
          try {
            await FileDownloader().cancelTaskWithId(task.taskId);
          } catch (_) {}
          try {
            await FileDownloader().database.deleteRecordWithId(task.taskId);
          } catch (_) {}
          continue;
        }
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
        restoredUrls.add(task.url);
      }
    } catch (_) {
      // Keep the locally saved list available if the native task database
      // cannot be read on this device.
    }

    // Restore local-only history entries once per URL. Active entries without
    // a matching native worker are shown as paused, never silently re-enqueued
    // as a second download.
    for (final item in savedItems) {
      final id = item['taskId'] as String?;
      final url = item['url'] as String?;
      if (url == null || restoredUrls.contains(url) ||
          (id != null && restoredIds.contains(id))) {
        continue;
      }
      final task = DownloadTask(
        url: url,
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
      if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে'].contains(entry.status)) {
        entry.status = 'বিরতি';
      }
      restored.add(entry);
      if (id != null) restoredIds.add(id);
      restoredUrls.add(url);
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
    // The modular DownloadController owns FileDownloader startup and task
    // updates. Home only forwards Android share intents to the download UI.
    _shareSubscription = _shareEvents.receiveBroadcastStream().listen((value) => _acceptSharedText(value?.toString()));
    _shareMethod.invokeMethod<String>('getInitialSharedText').then(_acceptSharedText).catchError((_) {});
  }

  Future<void> _initializeDownloader() async {
    try {
      // Must run after the updates listener is registered.
      await FileDownloader().start(autoCleanDatabase: true);
    } catch (_) {
      // Keep the local download history visible if native startup is delayed.
    }
    await _loadHistory();
  }

  void _onUpdate(TaskUpdate update) {
    final index = entries.indexWhere((e) => e.task.taskId == update.task.taskId);
    if (index < 0) return;
    final entry = entries[index];
    var rebuild = false;

    if (update is TaskProgressUpdate) {
      // Keep the newest values in memory, but limit expensive widget rebuilds
      // while several downloads are producing frequent progress events.
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
      final now = DateTime.now();
      if (_lastProgressUiUpdateAt == null ||
          now.difference(_lastProgressUiUpdateAt!).inMilliseconds >= 300) {
        _lastProgressUiUpdateAt = now;
        rebuild = true;
      }
    } else if (update is TaskStatusUpdate) {
      rebuild = true;
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

    if (rebuild && mounted) setState(() {});
    _scheduleHistorySave();
  }

  void _scheduleHistorySave() {
    // Progress events can arrive many times per second. Persist the latest
    // snapshot in batches instead of writing SharedPreferences on every event.
    _historySaveTimer?.cancel();
    _historySaveTimer = Timer(const Duration(milliseconds: 1200), () {
      _historySaveTimer = null;
      _saveHistory();
    });
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
    final existing = entries.where((e) => e.task.url == details.$1).firstOrNull;
    if (existing != null) {
      controller.clear();
      if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে'].contains(existing.status)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('This download is already in your list', 'এই ডাউনলোডটি আগে থেকেই তালিকায় আছে'))));
      } else {
        await _redownload(existing);
      }
      if (mounted) setState(() => adding = false);
      return;
    }
    final task = DownloadTask(
      url: details.$1,
      filename: details.$2,
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
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
    if (ok && mounted) {
      setState(() {
        entry.status = 'বিরতি';
        entry.speedBytesPerSecond = 0;
      });
      await _saveHistory();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('This server may not support Pause/Resume', 'এই সার্ভার Pause/Resume সমর্থন নাও করতে পারে'))));
    }
  }

  Future<void> _resume(DownloadEntry entry) async {
    var ok = false;
    var activeEntry = entry;
    try {
      // Resume the same native task first so its partial file and HTTP Range
      // state are retained.
      ok = await FileDownloader().resume(entry.task);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      // If Android removed the old worker record, start a fresh task.
      final retryTask = DownloadTask(
        url: entry.task.url,
        filename: entry.task.filename,
        directory: 'DROX',
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        allowPause: true,
        transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
        retries: 10,
      );
      final replacement = DownloadEntry(retryTask);
      final index = entries.indexWhere((e) => e.task.taskId == entry.task.taskId);
      if (index >= 0 && mounted) {
        setState(() => entries[index] = replacement);
        activeEntry = replacement;
        await _saveHistory();
      }
      try {
        await FileDownloader().transfers.start(retryTask);
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!ok && mounted) {
        setState(() => activeEntry.status = 'ব্যর্থ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('Could not restart this download. Check the link and try again.', 'ডাউনলোডটি আবার চালু করা যায়নি। লিংক যাচাই করে চেষ্টা করুন।'))),
        );
      }
    }
    if (ok && mounted) {
      // Update immediately; do not leave the card showing Paused while the
      // native running event is on its way.
      setState(() {
        activeEntry.status = 'ডাউনলোড হচ্ছে';
        activeEntry.error = null;
      });
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

  Future<void> _copyDownloadLink(DownloadEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.task.url));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_tr('Download link copied', 'ডাউনলোড লিংক কপি হয়েছে'))),
    );
  }

  Future<void> _renameDownload(DownloadEntry entry) async {
    if (entry.status != 'সম্পন্ন') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Finish the download before renaming', 'নাম পরিবর্তনের আগে ডাউনলোড সম্পন্ন করুন'))),
      );
      return;
    }
    final nameController = TextEditingController(text: entry.task.filename);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Rename file', 'ফাইলের নাম পরিবর্তন')),
        content: TextField(controller: nameController, autofocus: true, decoration: InputDecoration(labelText: _tr('File name', 'ফাইলের নাম'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_tr('Cancel', 'বাতিল'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameController.text.trim()), child: Text(_tr('Save', 'সেভ'))),
        ],
      ),
    );
    nameController.dispose();
    if (newName == null) return;
    final safeName = _safeFileName(newName);
    if (safeName == entry.task.filename) return;
    try {
      final oldPath = entry.sharedPath ?? await entry.task.filePath();
      final oldFile = File(oldPath);
      if (!await oldFile.exists()) throw Exception('File not found');
      final directory = oldFile.parent.path;
      final targetPath = '$directory/$safeName';
      if (await File(targetPath).exists()) throw Exception('A file with that name already exists');
      final renamed = await oldFile.rename(targetPath);
      entry.task = DownloadTask(
        url: entry.task.url,
        filename: safeName,
        directory: 'DROX',
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 10,
        taskId: entry.task.taskId,
      );
      entry.sharedPath = renamed.path;
      await _saveHistory();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Rename failed: ${e.toString().replaceFirst('Exception: ', '')}', 'নাম পরিবর্তন হয়নি: ${e.toString().replaceFirst('Exception: ', '')}'))),
      );
    }
  }

  Future<void> _showDownloadActions(DownloadEntry entry) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(entry.task.filename, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(_localizedStatus(entry.status))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.check_circle_outline_rounded), title: Text(_tr('Select for bulk actions', 'একসাথে কাজের জন্য নির্বাচন')), onTap: () => Navigator.pop(ctx, 'select')),
          if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(entry.status))
            ListTile(leading: const Icon(Icons.pause_circle_outline_rounded), title: Text(_tr('Cancel download', 'ডাউনলোড বাতিল')), onTap: () => Navigator.pop(ctx, 'cancel')),
          ListTile(leading: const Icon(Icons.refresh_rounded), title: Text(_tr('Redownload', 'আবার ডাউনলোড')), onTap: () => Navigator.pop(ctx, 'redownload')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: Text(_tr('Copy download link', 'ডাউনলোড লিংক কপি')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: const Icon(Icons.drive_file_rename_outline_rounded), title: Text(_tr('Rename file', 'ফাইলের নাম পরিবর্তন')), onTap: () => Navigator.pop(ctx, 'rename')),
          if (entry.status == 'সম্পন্ন')
            ListTile(leading: const Icon(Icons.open_in_new_rounded), title: Text(_tr('Open file', 'ফাইল খুলুন')), onTap: () => Navigator.pop(ctx, 'open')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.red), title: Text(_tr('Remove', 'মুছে ফেলুন')), onTap: () => Navigator.pop(ctx, 'remove')),
        ],
      )),
    );
    switch (selected) {
      case 'select': _toggleSelection(entry); break;
      case 'cancel': await _cancel(entry); break;
      case 'redownload': await _redownload(entry); break;
      case 'copy': await _copyDownloadLink(entry); break;
      case 'rename': await _renameDownload(entry); break;
      case 'open': await _open(entry); break;
      case 'remove': await _remove(entry); break;
    }
  }

  Future<void> _redownload(DownloadEntry entry) async {
    final oldTask = entry.task;
    final oldSharedPath = entry.sharedPath;
    final details = await _downloadDetails(oldTask.url);

    // Stop and forget the old native task before creating a fresh task ID.
    // Reusing the previous ID can reconnect to stale pause/range state.
    try {
      await FileDownloader().cancelTaskWithId(oldTask.taskId);
    } catch (_) {}
    try {
      await FileDownloader().database.deleteRecordWithId(oldTask.taskId);
    } catch (_) {}

    // Remove the old completed/partial destination so this is a true 0% restart.
    final pathsToDelete = <String>{};
    try {
      pathsToDelete.add(await oldTask.filePath());
    } catch (_) {}
    if (oldSharedPath != null && oldSharedPath.isNotEmpty) {
      pathsToDelete.add(oldSharedPath);
    }
    for (final path in pathsToDelete) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A missing or already-cleaned file must not block a fresh download.
      }
    }

    final task = DownloadTask(
      url: details.$1,
      filename: details.$2,
      directory: 'DROX',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause: true,
      transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
      retries: 10,
    );

    if (mounted) {
      setState(() {
        entry.task = task; // Fresh ID prevents reusing the old native resume state.
        entry.progress = 0;
        entry.expectedFileSize = -1;
        entry.status = 'কিউতে আছে';
        entry.error = null;
        entry.sharedPath = null;
        entry.lastDownloadedBytes = 0;
        entry.lastSpeedSampleAt = null;
        entry.speedBytesPerSecond = 0;
      });
    }
    await _saveHistory();

    try {
      await FileDownloader().transfers.start(task);
    } catch (error) {
      if (mounted) {
        setState(() {
          entry.status = 'কিউতে যোগ করা যায়নি';
          entry.error = error.toString();
        });
      }
    }
    await _saveHistory();
  }

  void _toggleSelection(DownloadEntry entry) {
    setState(() {
      final id = entry.task.taskId;
      if (!_selectedTaskIds.add(id)) _selectedTaskIds.remove(id);
    });
  }

  Future<void> _removeSelected() async {
    final ids = _selectedTaskIds.toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Remove downloads?', 'ডাউনলোডগুলো সরাবেন?')),
        content: Text(_tr('Remove ${ids.length} selected item(s) from the list and history?', 'নির্বাচিত ${ids.length}টি আইটেম তালিকা ও ইতিহাস থেকে মুছে ফেলবেন?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Cancel', 'বাতিল'))),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.delete_outline), label: Text(_tr('Remove', 'মুছুন'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final selected = entries.where((e) => ids.contains(e.task.taskId)).toList();
    for (final entry in selected) {
      if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(entry.status)) {
        try { await FileDownloader().cancelTaskWithId(entry.task.taskId); } catch (_) {}
      }
      if (Platform.isAndroid) {
        try { await _notificationMethod.invokeMethod<void>('cancelDownload', entry.task.taskId.hashCode & 0x7fffffff); } catch (_) {}
      }
    }
    try { await FileDownloader().database.deleteRecordsWithIds(ids); } catch (_) {}
    if (mounted) {
      setState(() {
        entries.removeWhere((e) => ids.contains(e.task.taskId));
        _selectedTaskIds.clear();
      });
    }
    await _saveHistory();
  }

  Future<void> _remove(DownloadEntry entry) async {
    if (['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে', 'বিরতি'].contains(entry.status)) {
      await FileDownloader().cancelTaskWithId(entry.task.taskId);
    }
    try { await FileDownloader().database.deleteRecordWithId(entry.task.taskId); } catch (_) {}
    if (Platform.isAndroid) {
      try { await _notificationMethod.invokeMethod<void>('cancelDownload', entry.task.taskId.hashCode & 0x7fffffff); } catch (_) {}
    }
    if (mounted) setState(() {
      entries.removeWhere((e) => e.task.taskId == entry.task.taskId);
      _selectedTaskIds.remove(entry.task.taskId);
    });
    await _saveHistory();
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
    _historySaveTimer?.cancel();
    _historySaveTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = entries.where((e) => ['ডাউনলোড হচ্ছে', 'কিউতে আছে', 'আবার চেষ্টা করছে'].contains(e.status)).length;
    final done = entries.where((e) => e.status == 'সম্পন্ন').length;
    final failed = entries.where((e) => ['ব্যর্থ', 'বাতিল', 'কিউতে যোগ করা যায়নি', 'যাচাই ব্যর্থ'].contains(e.status)).length;
    final visible = entries.where(_matches).toList();
    return PopScope(
      canPop: selectedTab == 0 && _selectedTaskIds.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_selectedTaskIds.isNotEmpty) {
          setState(() => _selectedTaskIds.clear());
          return;
        }
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
          title: Text(_selectedTaskIds.isEmpty ? 'DROX' : _tr('${_selectedTaskIds.length} selected', '${_selectedTaskIds.length}টি নির্বাচিত'), style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: .2, fontSize: 20)),
          actions: [
            if (_selectedTaskIds.isNotEmpty)
              IconButton(tooltip: _tr('Remove selected', 'নির্বাচিতগুলো মুছুন'), onPressed: _removeSelected, icon: const Icon(Icons.delete_sweep_rounded)),
            if (_selectedTaskIds.isNotEmpty)
              IconButton(tooltip: _tr('Select all visible', 'দেখানো সব নির্বাচন'), onPressed: () => setState(() => _selectedTaskIds.addAll(visible.map((e) => e.task.taskId))), icon: const Icon(Icons.select_all_rounded)),
            if (_selectedTaskIds.isNotEmpty)
              IconButton(tooltip: _tr('Clear selection', 'নির্বাচন বাতিল'), onPressed: () => setState(_selectedTaskIds.clear), icon: const Icon(Icons.close_rounded)),
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
        body: Stack(children: [
          IndexedStack(index: selectedTab, children: [
          DownloadCenterScreen(key: downloadCenterKey),
          BrowserPage(key: browserKey, isDark: widget.isDark, isBangla: widget.isBangla, onThemeTap: widget.onThemeTap, onReturn: () => setState(() => selectedTab = 0), onSettings: () => setState(() => selectedTab = 3), onDownload: (url) { downloadCenterKey.currentState?.downloadDetectedUrl(url); }),
          const SizedBox.shrink(), // Reserved legacy tab; the v2 Download Center is the only queue.
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
          if (_fabExpanded && selectedTab == 0)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _fabExpanded = false),
                child: const SizedBox.expand(),
              ),
            ),
        ]),
        floatingActionButton: selectedTab == 0
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _fabExpanded
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _fabAction(
                                label: _tr('Add Link', 'লিংক যোগ করুন'),
                                icon: Icons.link_rounded,
                                color: const Color(0xFF1976D2),
                                onTap: () {
                                  setState(() => _fabExpanded = false);
                                  _quickDownloadDialog();
                                },
                              ),
                              const SizedBox(height: 10),
                              _fabAction(
                                label: _tr('Open Browser', 'ব্রাউজার খুলুন'),
                                icon: Icons.language_rounded,
                                color: const Color(0xFFEF6C00),
                                onTap: () => setState(() {
                                  _fabExpanded = false;
                                  selectedTab = 1;
                                }),
                              ),
                              const SizedBox(height: 10),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: FloatingActionButton(
                      tooltip: _fabExpanded ? 'Close actions' : 'Add download',
                      backgroundColor: widget.isDark ? const Color(0xFF4FC3F7) : const Color(0xFF6B351B),
                      foregroundColor: widget.isDark ? const Color(0xFF101820) : Colors.white,
                      onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
                      child: AnimatedRotation(
                        turns: _fabExpanded ? 0.125 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: const Icon(Icons.add_rounded, size: 29),
                      ),
                    ),
                  ),
                ],
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

  Widget _fabAction({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(
      elevation: 5,
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 9),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
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
    if (value != null && value.isNotEmpty && mounted) {
      await downloadCenterKey.currentState?.acceptSharedUrl(value);
    }
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
    final selected = _selectedTaskIds.contains(entry.task.taskId);
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

    return GestureDetector(
      onLongPress: () => _showDownloadActions(entry),
      onTap: _selectedTaskIds.isNotEmpty ? () => _toggleSelection(entry) : null,
      child: Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected ? Theme.of(context).colorScheme.primary : (isDark ? const Color(0xFF455A64) : const Color(0xFF8A5636)).withValues(alpha: isDark ? .95 : .72),
          width: selected ? 2.2 : 1.15,
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
                  child: selected
                      ? Icon(Icons.check_circle_rounded, size: 34, color: Theme.of(context).colorScheme.primary)
                      : Icon(
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
                if (completed && _selectedTaskIds.isEmpty)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 21,
                    iconColor: ink,
                    tooltip: _tr('More options', 'আরও অপশন'),
                    onSelected: (value) {
                      if (value == 'open') _open(entry);
                      if (value == 'redownload') _redownload(entry);
                      if (value == 'copy') _copyDownloadLink(entry);
                      if (value == 'rename') _renameDownload(entry);
                      if (value == 'remove') _remove(entry);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'open', child: ListTile(dense: true, leading: const Icon(Icons.open_in_new), title: Text(_tr('Open', 'খুলুন')))),
                      PopupMenuItem(value: 'redownload', child: ListTile(dense: true, leading: const Icon(Icons.refresh), title: Text(_tr('Redownload', 'আবার ডাউনলোড')))),
                      PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: const Icon(Icons.copy), title: Text(_tr('Copy download link', 'লিংক কপি')))),
                      PopupMenuItem(value: 'rename', child: ListTile(dense: true, leading: const Icon(Icons.drive_file_rename_outline), title: Text(_tr('Rename file', 'নাম পরিবর্তন')))),
                      PopupMenuItem(value: 'remove', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline), title: Text(_tr('Remove', 'মুছুন')))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ));
  }


}


