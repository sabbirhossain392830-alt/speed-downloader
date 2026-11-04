import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/return_code.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../youtube/youtube_download_option.dart';
import '../youtube/youtube_link_info.dart';

class YoutubeDownloadException implements Exception {
  const YoutubeDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class YoutubeDownloadCancelled implements Exception {
  const YoutubeDownloadCancelled();
  @override
  String toString() => 'Download was cancelled.';
}

/// Lets the controller stop a running download (network read or FFmpeg merge).
class YoutubeCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }

  void attach(void Function()? hook) => _onCancel = hook;
}

class YoutubeVideoDetails {
  const YoutubeVideoDetails({
    required this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.options,
  });

  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final List<YoutubeDownloadOption> options;
}

/// Reads the public stream list of a YouTube video and downloads the stream(s)
/// the user picked. It only uses streams YouTube serves without signing in. It
/// does not sign in, and videos that need a purchase, membership, age check or
/// DRM are reported as unavailable instead of being worked around.
class YoutubeStreamService {
  YoutubeStreamService({YoutubeExplode? client}) : _client = client ?? YoutubeExplode();

  final YoutubeExplode _client;

  Future<YoutubeVideoDetails> load(YoutubeLinkInfo link) async {
    final video = await _client.videos.get(link.videoId);
    if (video.isLive) {
      throw const YoutubeDownloadException('Live streams cannot be downloaded.');
    }
    final manifest = await _client.videos.streams.getManifest(link.videoId);
    final options = buildYoutubeOptions(manifest);
    if (options.isEmpty) {
      throw const YoutubeDownloadException('No downloadable streams were found for this video.');
    }
    return YoutubeVideoDetails(
      videoId: link.videoId,
      title: video.title,
      author: video.author,
      duration: video.duration,
      thumbnailUrl: video.thumbnails.highResUrl,
      options: options,
    );
  }

  /// Downloads [job] to [outputPath] and returns the final file size in bytes.
  Future<int> download({
    required YoutubeJob job,
    required String outputPath,
    required YoutubeCancelToken cancel,
    void Function(double progress, int bytes, double elapsedSeconds)? onProgress,
  }) async {
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    if (await output.exists()) await output.delete();

    final stopwatch = Stopwatch()..start();
    final parts = <File>[];
    var received = 0;
    final expected = job.estimatedBytes;

    void report([double? override]) {
      final progress = override ??
          (expected > 0 ? (received / expected).clamp(0.0, 0.97).toDouble() : 0.0);
      onProgress?.call(progress, received, stopwatch.elapsedMilliseconds / 1000.0);
    }

    // YouTube often refuses a second download from the same manifest, so every
    // stream gets its own freshly fetched manifest.
    Future<File> fetch(int? tag, String suffix, bool Function(StreamInfo) accepts) async {
      if (tag == null) throw const YoutubeDownloadException('This download is missing its stream id. Pick the quality again.');
      _throwIfCancelled(cancel);
      final info = await _freshStream(job.videoId, tag, accepts);
      final part = File('$outputPath.$suffix.part');
      parts.add(part);
      await _writeStream(info, part, cancel, (bytes) {
        received += bytes;
        report();
      });
      return part;
    }

    try {
      switch (job.kind) {
        case YoutubeOptionKind.muxed:
          final muxedFile = await fetch(job.videoTag, 'media', (s) => s is MuxedStreamInfo);
          await muxedFile.rename(outputPath);
          parts.remove(muxedFile);
        case YoutubeOptionKind.audioOnly:
          final audioFile = await fetch(job.audioTag, 'audio', (s) => s is AudioOnlyStreamInfo);
          await audioFile.rename(outputPath);
          parts.remove(audioFile);
        case YoutubeOptionKind.merged:
          final videoPart = await fetch(job.videoTag, 'video', (s) => s is VideoOnlyStreamInfo);
          final audioPart = await fetch(job.audioTag, 'audio', (s) => s is AudioOnlyStreamInfo);
          report(0.98);
          await _merge(videoPart.path, audioPart.path, outputPath, cancel);
      }
      _throwIfCancelled(cancel);
      final size = await output.exists() ? await output.length() : 0;
      if (size < 1024) {
        throw const YoutubeDownloadException('YouTube returned an empty or incomplete file. Try again.');
      }
      onProgress?.call(1, size, stopwatch.elapsedMilliseconds / 1000.0);
      return size;
    } catch (_) {
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      rethrow;
    } finally {
      for (final part in parts) {
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
      }
    }
  }

  void dispose() => _client.close();

  Future<StreamInfo> _freshStream(String videoId, int tag, bool Function(StreamInfo) accepts) async {
    final manifest = await _client.videos.streams.getManifest(videoId);
    final matches = manifest.streams.where((s) => s.tag == tag && accepts(s)).toList();
    if (matches.isEmpty) {
      throw const YoutubeDownloadException(
        'That quality is no longer offered by YouTube. Open the link again and pick another.',
      );
    }
    // An itag can exist once per dubbed language; prefer the default track.
    for (final stream in matches) {
      if (stream is AudioStreamInfo) {
        final track = stream.audioTrack;
        if (track == null || track.audioIsDefault) return stream;
      }
    }
    return matches.first;
  }

  void _throwIfCancelled(YoutubeCancelToken cancel) {
    if (cancel.isCancelled) throw const YoutubeDownloadCancelled();
  }

  Future<void> _writeStream(
    StreamInfo info,
    File file,
    YoutubeCancelToken cancel,
    void Function(int bytes) onBytes,
  ) async {
    final sink = file.openWrite();
    try {
      await for (final chunk in _client.videos.streams.get(info)) {
        _throwIfCancelled(cancel);
        sink.add(chunk);
        onBytes(chunk.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _merge(String videoPath, String audioPath, String outputPath, YoutubeCancelToken cancel) async {
    final faststart = outputPath.toLowerCase().endsWith('.mp4') ? '-movflags +faststart ' : '';
    final command = '-y -hide_banner -loglevel error '
        '-i ${_quote(videoPath)} -i ${_quote(audioPath)} '
        '-map 0:v:0 -map 1:a:0 -c copy $faststart${_quote(outputPath)}';
    final completer = Completer<void>();
    final session = await FFmpegKit.executeAsync(command, (session) async {
      if (completer.isCompleted) return;
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code)) {
        completer.complete();
      } else if (ReturnCode.isCancel(code)) {
        completer.completeError(const YoutubeDownloadCancelled());
      } else {
        final logs = await session.getOutput() ?? '';
        final tail = logs.length > 600 ? logs.substring(logs.length - 600) : logs;
        completer.completeError(YoutubeDownloadException('Could not merge video and audio. $tail'));
      }
    });
    final id = await session.getSessionId();
    if (id != null) {
      cancel.attach(() => unawaited(FFmpegKit.cancel(id)));
      if (cancel.isCancelled) unawaited(FFmpegKit.cancel(id));
    }
    try {
      await completer.future;
    } finally {
      cancel.attach(null);
    }
  }

  String _quote(String value) => '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

/// Builds the quality list shown to the user from a stream manifest.
///
/// * Muxed MP4 streams (video + audio in one file, usually up to 720p).
/// * Higher qualities that need a separate video and audio stream merged.
/// * One audio-only option.
List<YoutubeDownloadOption> buildYoutubeOptions(StreamManifest manifest) {
  final videoOptions = <YoutubeDownloadOption>[];
  final seenLabels = <String>{};

  final muxed = manifest.muxed.where((s) => s.container.name == 'mp4').toList().sortByVideoQuality();
  for (final stream in muxed) {
    if (!seenLabels.add(stream.qualityLabel)) continue;
    videoOptions.add(YoutubeDownloadOption(
      kind: YoutubeOptionKind.muxed,
      label: stream.qualityLabel,
      detail: 'MP4 · video + audio',
      extension: 'mp4',
      estimatedBytes: stream.size.totalBytes,
      videoTag: stream.tag,
    ));
  }

  final audioMp4 = _bestAudio(manifest.audioOnly, container: 'mp4');
  final audioWebm = _bestAudio(manifest.audioOnly, container: 'webm');

  // Several video-only streams can share a label (for example H.264 and VP9);
  // keep the most widely playable one for each label.
  final videoOnly = manifest.videoOnly.toList().sortByVideoQuality();
  final bestByLabel = <String, VideoOnlyStreamInfo>{};
  for (final stream in videoOnly) {
    final current = bestByLabel[stream.qualityLabel];
    if (current == null || _videoRank(stream) > _videoRank(current)) {
      bestByLabel[stream.qualityLabel] = stream;
    }
  }
  final emitted = <String>{};
  for (final stream in videoOnly) {
    final label = stream.qualityLabel;
    if (seenLabels.contains(label) || !emitted.add(label)) continue;
    final chosen = bestByLabel[label]!;
    final isMp4 = chosen.container.name == 'mp4';
    final audio = isMp4 ? audioMp4 : audioWebm;
    if (audio == null) continue;
    videoOptions.add(YoutubeDownloadOption(
      kind: YoutubeOptionKind.merged,
      label: label,
      detail: '${isMp4 ? 'MP4' : 'WebM'} · merged video + audio',
      extension: isMp4 ? 'mp4' : 'webm',
      estimatedBytes: chosen.size.totalBytes + audio.size.totalBytes,
      videoTag: chosen.tag,
      audioTag: audio.tag,
    ));
  }

  videoOptions.sort((a, b) {
    final byHeight = youtubeLabelHeight(b.label).compareTo(youtubeLabelHeight(a.label));
    return byHeight != 0 ? byHeight : youtubeLabelFps(b.label).compareTo(youtubeLabelFps(a.label));
  });

  final options = <YoutubeDownloadOption>[...videoOptions];
  final audio = audioMp4 ?? _bestAudio(manifest.audioOnly);
  if (audio != null) {
    final isMp4 = audio.container.name == 'mp4';
    options.add(YoutubeDownloadOption(
      kind: YoutubeOptionKind.audioOnly,
      label: 'Audio only',
      detail: '${isMp4 ? 'M4A' : 'WebM'} · ${audio.bitrate.kiloBitsPerSecond.round()} kbps',
      extension: isMp4 ? 'm4a' : 'webm',
      estimatedBytes: audio.size.totalBytes,
      audioTag: audio.tag,
    ));
  }
  return options;
}

AudioOnlyStreamInfo? _bestAudio(Iterable<AudioOnlyStreamInfo> all, {String? container}) {
  final matching = all.where((a) {
    final isDefaultTrack = a.audioTrack == null || a.audioTrack!.audioIsDefault;
    return isDefaultTrack && (container == null || a.container.name == container);
  }).toList();
  if (matching.isEmpty) return null;
  matching.sort((a, b) => b.bitrate.compareTo(a.bitrate));
  return matching.first;
}

int _videoRank(VideoOnlyStreamInfo stream) {
  if (stream.container.name != 'mp4') return 1;
  return stream.videoCodec.toLowerCase().startsWith('avc1') ? 3 : 2;
}

/// Maps an extractor failure to a short message a user can act on.
String describeYoutubeError(Object error) {
  if (error is YoutubeDownloadException) return error.message;
  if (error is VideoRequiresPurchaseException) {
    return 'This video must be bought or rented on YouTube, so it cannot be downloaded.';
  }
  if (error is VideoUnavailableException) {
    return 'This video is unavailable. It may be private, removed or blocked in your region.';
  }
  if (error is VideoUnplayableException) {
    return 'YouTube will not play this video here (for example age-restricted or members-only), so it cannot be downloaded.';
  }
  if (error is SocketException) {
    return 'Could not reach YouTube. Check your internet connection and try again.';
  }
  return 'Could not read this video: $error';
}
