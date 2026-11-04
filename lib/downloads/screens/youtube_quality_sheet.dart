import 'package:flutter/material.dart';

import '../services/youtube_stream_service.dart';
import '../youtube/youtube_download_option.dart';

/// Bottom sheet that shows the video and lets the user pick a quality.
/// Returns the chosen option, or null when dismissed.
Future<YoutubeDownloadOption?> showYoutubeQualitySheet(
  BuildContext context,
  YoutubeVideoDetails details,
) {
  return showModalBottomSheet<YoutubeDownloadOption>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
    builder: (_) => _YoutubeQualitySheet(details: details),
  );
}

class _YoutubeQualitySheet extends StatelessWidget {
  const _YoutubeQualitySheet({required this.details});

  final YoutubeVideoDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = formatYoutubeDuration(details.duration);
    final subtitle = [details.author, if (duration.isNotEmpty) duration].join(' · ');
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    details.thumbnailUrl,
                    width: 120,
                    height: 68,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 120,
                      height: 68,
                      child: Icon(Icons.smart_display_outlined, size: 36),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: details.options.length,
              itemBuilder: (context, index) {
                final option = details.options[index];
                return ListTile(
                  leading: Icon(option.hasVideo ? Icons.movie_outlined : Icons.audiotrack_outlined),
                  title: Text(option.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(option.detail),
                  trailing: Text(formatYoutubeBytes(option.estimatedBytes)),
                  onTap: () => Navigator.pop(context, option),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Only save videos you own or have permission to download.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}
