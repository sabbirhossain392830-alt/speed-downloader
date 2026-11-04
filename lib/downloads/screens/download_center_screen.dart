import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/download_controller.dart';
import '../core/download_item.dart';
import '../services/youtube_metadata_service.dart';
import '../services/link_resolver.dart';
import '../youtube/youtube_link_info.dart';

/// Standalone v2 download screen. It does not modify BrowserPage.
class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});
  @override
  DownloadCenterScreenState createState() => DownloadCenterScreenState();
}

class DownloadCenterScreenState extends State<DownloadCenterScreen> {
  final DownloadController _downloads = DownloadController();
  final YoutubeMetadataService _youtube = YoutubeMetadataService();
  final DroxLinkResolver _resolver = DroxLinkResolver();
  DroxLinkResolution? _resolution;
  bool _checkingLink = false;
  final TextEditingController _url = TextEditingController();
  YoutubePreview? _preview;
  YoutubeLinkInfo? _youtubeLink;
  bool _checkingPreview = false;
  bool _adding = false;
  String? _previewVideoId;
  int _selectedFilter = 0;
  final Set<String> _selectedIds = <String>{};

  /// Starts a browser-detected direct file/media download and shows it in the home queue.
  Future<void> downloadDetectedUrl(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) return;
    final existing = _downloads.items.where((item) => item.url == clean &&
        (item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued ||
         item.state == DroxDownloadState.paused)).firstOrNull;
    if (existing != null) {
      _message('This download is already in the list.');
      return;
    }
    try {
      final result = await _resolver.resolve(clean);
      if (!result.canQueue) {
        _message(result.message);
        return;
      }
      final uri = Uri.tryParse(result.downloadUrl);
      final filename = result.filename ??
          (uri == null || uri.pathSegments.isEmpty || !uri.pathSegments.last.contains('.')
              ? 'drox_${DateTime.now().millisecondsSinceEpoch}.bin'
              : Uri.decodeComponent(uri.pathSegments.last));
      await _downloads.addDirectMedia(url: result.downloadUrl, filename: filename);
      if (mounted) {
        setState(() => _selectedFilter = 0);
        _message('Download started.');
      }
    } catch (error) {
      _message('Could not start download: $error');
    }
  }

  /// Accepts a URL shared from Android or detected by the built-in browser.
  Future<void> acceptSharedUrl(String value) async {
    _url.text = value.trim();
    if (!mounted) return;
    setState(() {});
    await _inspectLink();
  }

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_refresh);
    _downloads.initialize().catchError((error) {
      _message('Download manager could not start: $error');
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _inspectLink() async {
    final value = _url.text.trim();
    if (value.isEmpty) { _message('Paste a link first.'); return; }
    setState(() => _checkingLink = true);
    try {
      final result = await _resolver.resolve(value);
      if (mounted) setState(() => _resolution = result);
    } catch (error) {
      if (mounted) _message('Link check failed: $error');
    } finally {
      if (mounted) setState(() => _checkingLink = false);
    }
    final link = YoutubeLinkInfo.parse(value);
    if (link == null) {
      if (mounted) setState(() { _youtubeLink = null; _preview = null; _previewVideoId = null; });
      return;
    }
    if (_previewVideoId == link.videoId && (_preview != null || _checkingPreview)) return;
    _previewVideoId = link.videoId;
    setState(() { _checkingPreview = true; _youtubeLink = link; _preview = null; });
    try {
      final preview = await _youtube.fetch(link);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (mounted) _message('Could not load YouTube preview: $error');
    } finally {
      if (mounted) setState(() => _checkingPreview = false);
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _message('Action failed: $error');
    }
  }

  Future<void> _openExternal(String value, String label) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('Could not open $label. Please check your internet connection.');
    }
  }

  Future<void> _addDirectMedia() async {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      _message('Enter a valid HTTP/HTTPS link.');
      return;
    }
    if (YoutubeLinkInfo.parse(value) != null) {
      _message('Opening YouTube. Use its official Download option where available.');
      await _openExternal(_youtubeLink?.canonicalUrl ?? value, 'YouTube');
      return;
    }
    setState(() => _adding = true);
    try {
      final result = _resolution?.originalUrl == value ? _resolution! : await _resolver.resolve(value);
      if (!result.canQueue) {
        _message(result.message);
        await _openExternal(result.originalUrl, result.provider);
        return;
      }
      final filename = result.filename ?? (uri.pathSegments.isEmpty || !uri.pathSegments.last.contains('.')
          ? 'drox_${DateTime.now().millisecondsSinceEpoch}.bin'
          : Uri.decodeComponent(uri.pathSegments.last));
      await _downloads.addDirectMedia(url: result.downloadUrl, filename: filename);
      _url.clear();
      setState(() => _resolution = null);
      _message('Added ${result.provider} download to queue.');
    } catch (error) {
      _message('Could not add download: $error');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _downloads.removeListener(_refresh);
    _downloads.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _downloads.items;
    final allCount = items.length;
    final activeCount = items.where((e) => e.state == DroxDownloadState.running || e.state == DroxDownloadState.queued || e.state == DroxDownloadState.paused).length;
    final finishedCount = items.where((e) => e.state == DroxDownloadState.complete).length;
    final errorCount = items.where((e) => e.state == DroxDownloadState.failed || e.state == DroxDownloadState.cancelled).length;
    final filtered = items.where((item) {
      switch (_selectedFilter) {
        case 1: return item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued || item.state == DroxDownloadState.paused;
        case 2: return item.state == DroxDownloadState.complete;
        case 3: return item.state == DroxDownloadState.failed || item.state == DroxDownloadState.cancelled;
        default: return true;
      }
    }).toList();
    return Column(
      children: [
        Material(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF151A22) : const Color(0xFF6B351B),
          child: _selectedIds.isNotEmpty
              ? Row(children: [
                  IconButton(onPressed: () => setState(() => _selectedIds.clear()), icon: const Icon(Icons.close, color: Colors.white)),
                  Expanded(child: Text('${_selectedIds.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  TextButton(onPressed: () => setState(() => _selectedIds.addAll(filtered.map((e) => e.id))), child: const Text('SELECT ALL', style: TextStyle(color: Colors.white))),
                  IconButton(onPressed: () => _showBulkActions(filtered), icon: const Icon(Icons.more_vert, color: Colors.white)),
                ])
              : Row(children: [
                  _categoryTab('ALL', allCount, 0),
                  _categoryTab('DOWNLOADING', activeCount, 1),
                  _categoryTab('FINISHED', finishedCount, 2),
                  _categoryTab('ERROR', errorCount, 3),
                ]),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const SizedBox.expand()
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1),
                  itemBuilder: (_, index) => _downloadCard(filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _categoryTab(String label, int count, int index) {
    final selected = _selectedFilter == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedFilter = index),
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: selected ? Colors.white : Colors.transparent,
              width: 3,
            )),
          ),
          child: Text('$label ($count)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.white70),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _youtubePreviewCard(YoutubePreview preview) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(preview.thumbnailUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.ondemand_video_rounded, size: 48))),
      ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(preview.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(preview.authorName, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ]),
  );

  Future<void> _showItemMenu(DroxDownloadItem item, String action) async {
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: item.url));
        _message('Download link copied.');
        break;
      case 'redownload':
        await _runAction(() => _downloads.redownload(item));
        break;
      case 'rename':
        final controller = TextEditingController(text: item.filename);
        final name = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
          title: const Text('Rename file'),
          content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'File name')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('SAVE')),
          ],
        ));
        if (name != null && name.trim().isNotEmpty) await _runAction(() => _downloads.rename(item, name));
        controller.dispose();
        break;
      case 'folder':
        try {
          final path = await item.task.filePath();
          final slash = path.lastIndexOf('/');
          final folder = slash > 0 ? path.substring(0, slash) : path;
          final opened = await launchUrl(Uri.file(folder), mode: LaunchMode.externalApplication);
          if (!opened && mounted) {
            await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
              title: const Text('File location'),
              content: SelectableText(folder),
              actions: [
                TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: folder)); Navigator.pop(dialogContext); }, child: const Text('COPY PATH')),
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE')),
              ],
            ));
          }
        } catch (error) { _message('Could not open folder: $error'); }
        break;
    }
  }

  Future<void> _showBulkActions(List<DroxDownloadItem> visible) async {
    final selected = visible.where((item) => _selectedIds.contains(item.id)).toList();
    if (selected.isEmpty) return;
    final action = await showModalBottomSheet<String>(context: context, builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete selected'), onTap: () => Navigator.pop(sheetContext, 'delete')),
        ListTile(leading: const Icon(Icons.download), title: const Text('Redownload selected'), onTap: () => Navigator.pop(sheetContext, 'redownload')),
        ListTile(leading: const Icon(Icons.link), title: const Text('Copy selected links'), onTap: () => Navigator.pop(sheetContext, 'copy')),
      ]),
    ));
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: selected.map((item) => item.url).join('\\n')));
      _message('Selected links copied.');
    } else if (action == 'redownload') {
      for (final item in selected) { await _runAction(() => _downloads.redownload(item)); }
      if (mounted) setState(() => _selectedIds.clear());
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF14243A) : const Color(0xFFF3F8FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF2878D0), width: 1.2)),
        icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFF2878D0), size: 38),
        title: const Text('Delete selected files?', textAlign: TextAlign.center),
        content: Text('Are you sure you want to delete ${selected.length} selected file(s)?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL', style: TextStyle(color: Color(0xFF2878D0), fontWeight: FontWeight.w700))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2878D0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE'),
          ),
        ],
      ));
      if (confirmed == true) await _runAction(() => _downloads.removeMany(selected));
      if (mounted) setState(() => _selectedIds.clear());
    }
  }

  Widget _downloadCard(DroxDownloadItem item) {
    final running = item.state == DroxDownloadState.running || item.state == DroxDownloadState.queued;
    final paused = item.state == DroxDownloadState.paused;
    final failed = item.state == DroxDownloadState.failed || item.state == DroxDownloadState.cancelled;
    final complete = item.state == DroxDownloadState.complete;
    final percent = complete ? 100 : (item.progress * 100).round();
    final bytes = item.expectedBytes > 0 ? item.expectedBytes : 0;
    String sizeLabel() {
      if (bytes <= 0) return 'Size unknown';
      final value = bytes / (1024 * 1024);
      return value >= 1024 ? '${(value / 1024).toStringAsFixed(2)}GB' : '${value.toStringAsFixed(1)}MB';
    }
    final status = complete ? 'Finished' : failed ? 'Error' : paused ? 'Paused' : item.state == DroxDownloadState.queued ? 'Queued' : 'Downloading';
    String speedLabel() { final v = item.speedBytesPerSecond; if (!running || v <= 0) return running ? 'Calculating speed...' : ''; if (v >= 1048576) return (v / 1048576).toStringAsFixed(2) + ' MB/s'; return (v / 1024).toStringAsFixed(1) + ' KB/s'; }
    String etaLabel() { if (!running || item.expectedBytes <= 0 || item.speedBytesPerSecond <= 0) return running ? 'Time left: calculating...' : ''; final n = ((item.expectedBytes - item.downloadedBytes).clamp(0, item.expectedBytes) / item.speedBytesPerSecond).ceil(); if (n >= 3600) return 'Time left: ' + (n ~/ 3600).toString() + 'h ' + ((n % 3600) ~/ 60).toString() + 'm'; if (n >= 60) return 'Time left: ' + (n ~/ 60).toString() + 'm ' + (n % 60).toString() + 's'; return 'Time left: ' + n.toString() + 's'; }
    final ink = Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF202020);
    return Container(
      height: 116,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned.fill(child: Material(
            color: Colors.transparent,
            child: InkWell(
              onLongPress: () => setState(() => _selectedIds.add(item.id)),
              onTap: _selectedIds.isEmpty ? null : () => setState(() {
                if (_selectedIds.contains(item.id)) { _selectedIds.remove(item.id); } else { _selectedIds.add(item.id); }
              }),
            ),
          )),
          if (running || paused)
            Positioned(left: 0, right: 0, bottom: 0,
              child: Container(height: 3, color: ink.withValues(alpha: .10))),
          if (running || paused)
            Positioned(left: 0, bottom: 0,
              child: SizedBox(width: MediaQuery.of(context).size.width * item.progress.clamp(0.0, 1.0), height: 3,
                child: Container(color: const Color(0xFF2878D0)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 5, 7),
            child: Row(children: [
              SizedBox(
                width: 42,
                child: Icon(
                  item.filename.toLowerCase().endsWith('.mkv') || item.filename.toLowerCase().endsWith('.mp4')
                      ? Icons.movie_creation_outlined : Icons.insert_drive_file_outlined,
                  size: 34,
                  color: ink.withValues(alpha: .8),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
                    const SizedBox(height: 7),
                    Row(children: [
                      Expanded(child: Text('$percent% | ${sizeLabel()}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: ink))),
                      Text(status, style: TextStyle(fontSize: 12, color: ink.withValues(alpha: .85))),
                    ]),
                    if (running && item.state == DroxDownloadState.running) Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [Expanded(child: Text(speedLabel(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink.withValues(alpha: .85)))), Text(etaLabel(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: ink.withValues(alpha: .75)))])),
                    if (item.error != null)
                      Text(item.error!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (_selectedIds.contains(item.id))
                const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.check_circle, color: Color(0xFF2878D0), size: 28))
              else if (complete)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: ink),
                  onSelected: (action) => _showItemMenu(item, action),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'folder', child: Text('Open folder')),
                    PopupMenuItem(value: 'redownload', child: Text('Redownload')),
                    PopupMenuItem(value: 'rename', child: Text('Rename file')),
                    PopupMenuItem(value: 'copy', child: Text('Copy link')),
                  ],
                )
              else if (running)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Pause',
                  onPressed: () => _runAction(() => _downloads.pause(item)),
                  icon: Icon(Icons.pause_circle_outline_rounded, size: 32, color: ink),
                )
              else if (paused || failed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Resume',
                  onPressed: () => _runAction(() => _downloads.resume(item)),
                  icon: Icon(Icons.play_circle_outline_rounded, size: 32, color: ink),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove',
                  onPressed: () => _runAction(() => _downloads.remove(item)),
                  icon: Icon(Icons.check_circle_outline_rounded, size: 29, color: ink),
                ),
            ]),
          ),
        ],
      ),
    );
  }

}
