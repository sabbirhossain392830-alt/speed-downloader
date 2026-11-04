import 'package:flutter_test/flutter_test.dart';
import 'package:speed_downloader/downloads/youtube/youtube_download_option.dart';

void main() {
  group('youtubeFilename', () {
    test('builds title - quality.ext', () {
      expect(
        youtubeFilename(title: 'My video', label: '720p', extension: 'mp4'),
        'My video - 720p.mp4',
      );
    });

    test('removes characters that are invalid in file names', () {
      final name = youtubeFilename(title: 'a/b\\c:d*e?f"g<h>i|j', label: '1080p60', extension: 'mp4');
      expect(name, 'a b c d e f g h i j - 1080p60.mp4');
    });

    test('falls back for empty titles and trims hidden-file dots', () {
      expect(youtubeFilename(title: '   ', label: 'Audio only', extension: 'm4a'), 'YouTube video - Audio only.m4a');
      expect(youtubeFilename(title: '...secret', label: '360p', extension: 'mp4'), 'secret - 360p.mp4');
    });

    test('limits very long titles', () {
      final name = youtubeFilename(title: 'x' * 300, label: '720p', extension: 'mp4');
      expect(name.length, lessThanOrEqualTo(80 + ' - 720p.mp4'.length));
    });
  });

  group('quality labels', () {
    test('reads height and frame rate', () {
      expect(youtubeLabelHeight('1080p60'), 1080);
      expect(youtubeLabelFps('1080p60'), 60);
      expect(youtubeLabelHeight('720p'), 720);
      expect(youtubeLabelFps('720p'), 30);
      expect(youtubeLabelHeight('Audio only'), 0);
    });
  });

  group('formatting', () {
    test('formats sizes', () {
      expect(formatYoutubeBytes(0), 'Size unknown');
      expect(formatYoutubeBytes(2048), '2 KB');
      expect(formatYoutubeBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatYoutubeBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('formats durations', () {
      expect(formatYoutubeDuration(null), '');
      expect(formatYoutubeDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(formatYoutubeDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });

  group('YoutubeJob', () {
    test('survives a JSON round trip', () {
      const option = YoutubeDownloadOption(
        kind: YoutubeOptionKind.merged,
        label: '1080p',
        detail: 'MP4 · merged video + audio',
        extension: 'mp4',
        estimatedBytes: 1234,
        videoTag: 137,
        audioTag: 140,
      );
      final job = option.toJob('dQw4w9WgXcQ');
      final restored = YoutubeJob.fromJson(job.toJson());
      expect(restored, isNotNull);
      expect(restored!.sameTarget(job), isTrue);
      expect(restored.extension, 'mp4');
      expect(restored.estimatedBytes, 1234);
    });

    test('different quality of the same video is a different target', () {
      const a = YoutubeJob(videoId: 'x', kind: YoutubeOptionKind.muxed, extension: 'mp4', estimatedBytes: 1, videoTag: 18);
      const b = YoutubeJob(videoId: 'x', kind: YoutubeOptionKind.muxed, extension: 'mp4', estimatedBytes: 1, videoTag: 22);
      expect(a.sameTarget(b), isFalse);
    });

    test('ignores damaged saved data', () {
      expect(YoutubeJob.fromJson(null), isNull);
      expect(YoutubeJob.fromJson('nope'), isNull);
      expect(YoutubeJob.fromJson({'videoId': 5}), isNull);
    });
  });
}
