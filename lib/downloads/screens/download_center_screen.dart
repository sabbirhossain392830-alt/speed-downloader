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
          child: Row(children: [
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
    final ink = Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF202020);
    return Container(
      height: 98,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          if (running || paused)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: item.progress.clamp(0.0, 1.0),
                  heightFactor: 0.30,
                  child: Container(color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4FC3F7) : const Color(0xFF8A5636)).withValues(alpha: .18)),
                ),
              ),
            ),
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
                    if (item.error != null)
                      Text(item.error!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (running)
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
