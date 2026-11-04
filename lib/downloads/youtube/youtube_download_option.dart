/// Pure data models for YouTube downloads. They deliberately do not import the
/// extractor package so they can be persisted, retried and unit-tested without
/// network access.

enum YoutubeOptionKind {
  /// One stream that already contains video and audio.
  muxed,

  /// A video-only stream and an audio-only stream merged into one file.
  merged,

  /// Audio only.
  audioOnly,
}

/// A quality the user can pick in the bottom sheet.
class YoutubeDownloadOption {
  const YoutubeDownloadOption({
    required this.kind,
    required this.label,
    required this.detail,
    required this.extension,
    required this.estimatedBytes,
    this.videoTag,
    this.audioTag,
  });

  final YoutubeOptionKind kind;

  /// Short headline such as `1080p60` or `Audio`.
  final String label;

  /// Secondary line such as `MP4 · video + audio`.
  final String detail;

  /// Output file extension without the dot (`mp4`, `webm`, `m4a`).
  final String extension;

  /// Sum of the selected streams' sizes; 0 when YouTube did not report it.
  final int estimatedBytes;

  /// itag of the video (or muxed) stream.
  final int? videoTag;

  /// itag of the separate audio stream (merged / audio-only).
  final int? audioTag;

  bool get hasVideo => kind != YoutubeOptionKind.audioOnly;

  YoutubeJob toJob(String videoId) => YoutubeJob(
        videoId: videoId,
        kind: kind,
        extension: extension,
        videoTag: videoTag,
        audioTag: audioTag,
        estimatedBytes: estimatedBytes,
      );
}

/// Everything needed to (re)start a YouTube download later. Stored with the
/// download item so a failed or interrupted item can be retried.
class YoutubeJob {
  const YoutubeJob({
    required this.videoId,
    required this.kind,
    required this.extension,
    required this.estimatedBytes,
    this.videoTag,
    this.audioTag,
  });

  final String videoId;
  final YoutubeOptionKind kind;
  final String extension;
  final int estimatedBytes;
  final int? videoTag;
  final int? audioTag;

  bool sameTarget(YoutubeJob other) =>
      videoId == other.videoId &&
      kind == other.kind &&
      videoTag == other.videoTag &&
      audioTag == other.audioTag;

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'kind': kind.name,
        'extension': extension,
        'estimatedBytes': estimatedBytes,
        'videoTag': videoTag,
        'audioTag': audioTag,
      };

  static YoutubeJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final videoId = raw['videoId'];
    final extension = raw['extension'];
    if (videoId is! String || extension is! String) return null;
    var kind = YoutubeOptionKind.muxed;
    for (final candidate in YoutubeOptionKind.values) {
      if (candidate.name == raw['kind']) kind = candidate;
    }
    final estimated = raw['estimatedBytes'];
    final video = raw['videoTag'];
    final audio = raw['audioTag'];
    return YoutubeJob(
      videoId: videoId,
      kind: kind,
      extension: extension,
      estimatedBytes: estimated is num ? estimated.toInt() : 0,
      videoTag: video is num ? video.toInt() : null,
      audioTag: audio is num ? audio.toInt() : null,
    );
  }
}

/// Builds a safe local filename such as `My video - 720p.mp4`.
String youtubeFilename({
  required String title,
  required String label,
  required String extension,
}) {
  var clean = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Names starting with a dot are hidden files on Android.
  clean = clean.replaceFirst(RegExp(r'^\.+'), '').trim();
  if (clean.length > 80) clean = clean.substring(0, 80).trim();
  if (clean.isEmpty) clean = 'YouTube video';
  final quality = label.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '').trim();
  final suffix = quality.isEmpty ? '' : ' - $quality';
  return '$clean$suffix.$extension';
}

/// Pixel height from a label such as `1080p60` or `720p`; 0 when unknown.
int youtubeLabelHeight(String label) =>
    int.tryParse(RegExp(r'^(\d+)p').firstMatch(label)?.group(1) ?? '') ?? 0;

/// Frame rate from a label such as `1080p60`; 30 when the label has none.
int youtubeLabelFps(String label) =>
    int.tryParse(RegExp(r'^\d+p(\d+)').firstMatch(label)?.group(1) ?? '') ?? 30;

String formatYoutubeBytes(int bytes) {
  if (bytes <= 0) return 'Size unknown';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String formatYoutubeDuration(Duration? duration) {
  if (duration == null || duration == Duration.zero) return '';
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${duration.inMinutes}:$s';
}
