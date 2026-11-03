import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browser/browser_page.dart';
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
    setState(() => selectedTab = 0);
    await downloadCenterKey.currentState?.acceptSharedUrl(shared);
  }

  bool _fabExpanded = false;
  bool wifiOnly = false;
  bool notificationsEnabled = false;
  int selectedTab = 0;
  final GlobalKey<BrowserPageState> browserKey = GlobalKey<BrowserPageState>();
  final GlobalKey<DownloadCenterScreenState> downloadCenterKey = GlobalKey<DownloadCenterScreenState>();

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

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          title: const Text('DROX', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: .2, fontSize: 20)),
          actions: [
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
                    setState(() => selectedTab = 2);
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
          BrowserPage(key: browserKey, isDark: widget.isDark, isBangla: widget.isBangla, onThemeTap: widget.onThemeTap, onReturn: () => setState(() => selectedTab = 0), onSettings: () => setState(() => selectedTab = 2), onDownload: (url) { downloadCenterKey.currentState?.acceptSharedUrl(url); setState(() => selectedTab = 0); }),
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


