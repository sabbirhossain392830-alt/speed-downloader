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

  /// Accepts a URL shared from Android or detected by the built-in browser.
  Future<void> acceptSharedUrl(String value) async {
    _url.text = value.trim();
    if (!mounted) return;
    setState(() {});
    if (YoutubeLinkInfo.parse(_url.text) != null) {
      await _inspectLink();
    } else {
      _message('Link added. Review it, then choose Download direct link.');
    }
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
    final isYouTube = _youtubeLink != null;
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Paste a link',
              hintText: 'Paste a cloud share or file link',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _url.text = data!.text!.trim();
                },
              ),
            ),
            onChanged: (value) {
              final link = YoutubeLinkInfo.parse(value);
              if (link == null) {
                if (_youtubeLink != null) {
                  setState(() { _youtubeLink = null; _preview = null; _previewVideoId = null; });
                }
              } else if (link.videoId != _previewVideoId) {
                _inspectLink();
              }
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _checkingLink ? null : _inspectLink,
              icon: const Icon(Icons.preview_outlined),
              label: Text(_checkingLink ? 'Checking…' : 'Check link'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _adding ? null : isYouTube
                  ? () => _openExternal(_youtubeLink!.canonicalUrl, 'YouTube')
                  : _addDirectMedia,
              icon: Icon(isYouTube ? Icons.open_in_new_rounded : Icons.download_rounded),
              label: Text(_adding ? 'Adding…' : isYouTube ? 'Open YouTube' : 'Download'),
            )),
          ]),
          if (_checkingLink || _checkingPreview) const LinearProgressIndicator(),
          if (_resolution != null && !isYouTube)
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Detected: ${_resolution!.provider}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4), Text(_resolution!.message),
              if (_resolution!.contentType != null) Text('Type: ${_resolution!.contentType}'),
              if (_resolution!.contentLength != null) Text('Size: ${(_resolution!.contentLength! / 1048576).toStringAsFixed(2)} MB'),
            ]))),
          if (_preview != null) _youtubePreviewCard(_preview!),
          if (_youtubeLink != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YouTube options', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Open this video in YouTube and use the official Download option when it is available. If this is your own upload, manage or download it through YouTube Studio. DROX does not bypass YouTube download restrictions.'),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: _youtubeLink!.canonicalUrl)),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy YouTube link'),
                  ),
                  TextButton.icon(
                    onPressed: () => _openExternal(_youtubeLink!.canonicalUrl, 'YouTube'),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Open video'),
                  ),
                  TextButton.icon(
                    onPressed: () => _openExternal('https://studio.youtube.com/', 'YouTube Studio'),
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('YouTube Studio'),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('Download queue', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            Text('${items.length} items'),
          ]),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: Text('Your download queue is empty.')),
            ),
          ...items.map(_downloadCard),
        ],
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
    final state = item.state.name;
    final percent = (item.progress * 100).toStringAsFixed(0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: item.state == DroxDownloadState.complete ? 1 : item.progress),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(child: Text('$state • $percent%')),
            if (item.state == DroxDownloadState.running)
              IconButton(onPressed: () => _runAction(() => _downloads.pause(item)), icon: const Icon(Icons.pause_rounded)),
            if (item.state == DroxDownloadState.paused || item.state == DroxDownloadState.failed)
              IconButton(onPressed: () => _runAction(() => _downloads.resume(item)), icon: const Icon(Icons.play_arrow_rounded)),
            IconButton(onPressed: () => _runAction(() => _downloads.remove(item)), icon: const Icon(Icons.delete_outline_rounded)),
          ]),
          if (item.error != null) Text(item.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    );
  }
}
