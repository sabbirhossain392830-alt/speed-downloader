import 'package:flutter_test/flutter_test.dart';
import 'package:speed_downloader/downloads/services/stream_manifest_analyzer.dart';

void main() {
  const manifestUrl = 'https://cdn.example.com/media/master.m3u8';

  test('parses HLS quality variants and resolves relative URLs', () {
    const playlist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720
720/index.m3u8
''';
    final analyzer = DroxStreamManifestAnalyzer();
    final manifest = analyzer.analyzeHls(playlist, manifestUrl: manifestUrl);
    final options = analyzer.qualityOptions(manifest);

    expect(manifest.isMaster, isTrue);
    expect(options.map((option) => option.label), ['720p', '360p']);
    expect(options.first.url, 'https://cdn.example.com/media/720/index.m3u8');
  });

  test('parses HLS audio renditions and live/end-list state', () {
    const playlist = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",DEFAULT=YES,URI="audio/en.m3u8"
#EXTINF:6.0,
segment-1.ts
#EXT-X-ENDLIST
''';
    final manifest = DroxStreamManifestAnalyzer()
        .analyzeHls(playlist, manifestUrl: manifestUrl);

    expect(manifest.renditions.single.name, 'English');
    expect(manifest.renditions.single.url,
        'https://cdn.example.com/media/audio/en.m3u8');
    expect(manifest.durationSeconds, 6);
    expect(manifest.isLive, isFalse);
  });

  test('parses basic DASH representation quality metadata', () {
    const mpd = '''
<MPD><Period><AdaptationSet mimeType="video/mp4">
<BaseURL>video/</BaseURL>
<Representation id="v1" width="1920" height="1080" bandwidth="4000000" />
</AdaptationSet></Period></MPD>
''';
    final variants = DroxStreamManifestAnalyzer()
        .analyzeDash(mpd, manifestUrl: 'https://cdn.example.com/manifest.mpd');

    expect(variants.single.height, 1080);
    expect(variants.single.bandwidth, 4000000);
    expect(variants.single.url, 'https://cdn.example.com/video/');
  });
}
