import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/download_controller.dart';
import '../core/download_item.dart';
import '../services/youtube_metadata_service.dart';
import '../youtube/youtube_link_info.dart';

/// Standalone v2 download screen. It does not modify BrowserPage.
class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});
  @override
  State<DownloadCenterScreen> createState() => _DownloadCenterScreenState();
}

class _DownloadCenterScreenState extends State<DownloadCenterScreen> {
  final DownloadController _downloads = DownloadController();
  final YoutubeMetadataService _youtube = YoutubeMetadataService();
  final TextEditingController _url = TextEditingController();
  YoutubePreview? _preview;
  YoutubeLinkInfo? _youtubeLink;
  bool _checkingPreview = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_refresh);
    _downloads.initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _inspectLink() async {
    final value = _url.text.trim();
    final link = YoutubeLinkInfo.parse(value);
    if (link == null) {
      setState(() {
        _youtubeLink = null;
        _preview = null;
      });
      return;
    }
    setState(() {
      _checkingPreview = true;
      _youtubeLink = link;
      _preview = null;
    });
    try {
      final preview = await _youtube.fetch(link);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load YouTube preview: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingPreview = false);
    }
  }

  Future<void> _addDirectMedia() async {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      _message('Enter a valid direct media URL.');
      return;
    }
    if (YoutubeLinkInfo.parse(value) != null) {
      _message('YouTube links are previewed here. Use YouTube’s official offline feature where available.');
      return;
    }
    setState(() => _adding = true);
    try {
      final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final filename = segment.isNotEmpty && segment.contains('.')
          ? Uri.decodeComponent(segment)
          : 'drox_${DateTime.now().millisecondsSinceEpoch}.bin';
      await _downloads.addDirectMedia(url: value, filename: filename);
      _url.clear();
      _message('Added to download queue.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('DROX Downloads')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Paste a link',
              hintText: 'YouTube URL or direct media URL',
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
              if (YoutubeLinkInfo.parse(value) != null) _inspectLink();
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _checkingPreview ? null : _inspectLink,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Check link'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _adding ? null : _addDirectMedia,
              icon: const Icon(Icons.download_rounded),
              label: Text(_adding ? 'Adding…' : 'Download direct link'),
            )),
          ]),
          if (_checkingPreview) const LinearProgressIndicator(),
          if (_preview != null) _youtubePreviewCard(_preview!),
          if (_youtubeLink != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YouTube download options', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('DROX can identify the link and show its public preview. It does not extract YouTube video/audio streams or bypass YouTube download restrictions. Where available, use YouTube’s official Download / offline feature in the YouTube app.'),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: _youtubeLink!.canonicalUrl)),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy YouTube link'),
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
              IconButton(onPressed: () => _downloads.pause(item), icon: const Icon(Icons.pause_rounded)),
            if (item.state == DroxDownloadState.paused || item.state == DroxDownloadState.failed)
              IconButton(onPressed: () => _downloads.resume(item), icon: const Icon(Icons.play_arrow_rounded)),
            IconButton(onPressed: () => _downloads.remove(item), icon: const Icon(Icons.delete_outline_rounded)),
          ]),
          if (item.error != null) Text(item.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    );
  }
}
