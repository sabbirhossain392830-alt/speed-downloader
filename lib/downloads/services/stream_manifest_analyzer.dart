class DroxStreamVariant {
  const DroxStreamVariant({
    required this.url,
    this.width,
    this.height,
    this.bandwidth,
    this.codecs,
    this.audioGroup,
  });

  final String url;
  final int? width;
  final int? height;
  final int? bandwidth;
  final String? codecs;
  final String? audioGroup;

  String get qualityLabel {
    if (height != null) return '${height}p';
    if (bandwidth != null) return '${(bandwidth! / 1000).round()} kbps';
    return 'Unknown quality';
  }
}

class DroxStreamManifest {
  const DroxStreamManifest({
    required this.isHls,
    required this.isMaster,
    required this.variants,
    required this.segmentUrls,
    this.durationSeconds,
    this.isLive = false,
  });

  final bool isHls;
  final bool isMaster;
  final List<DroxStreamVariant> variants;
  final List<String> segmentUrls;
  final double? durationSeconds;
  final bool isLive;
}

/// Lightweight manifest inspection. This only describes publicly accessible
/// manifests; it does not bypass DRM, authentication, or site access controls.
class DroxStreamManifestAnalyzer {
  DroxStreamManifest analyzeHls(String source, {required String manifestUrl}) {
    final lines = source.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
    final variants = <DroxStreamVariant>[];
    final segments = <String>[];
    var pending = <String, String>{};
    var duration = 0.0;
    var live = true;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      if (line == '#EXT-X-ENDLIST') live = false;
      if (line.startsWith('#EXTINF:')) {
        final value = line.substring(8).split(',').first;
        duration += double.tryParse(value) ?? 0;
      }
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pending = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
        var next = i + 1;
        while (next < lines.length && (lines[next].isEmpty || lines[next].startsWith('#'))) {
          next++;
        }
        if (next < lines.length) {
          final resolution = pending['RESOLUTION']?.split('x');
          variants.add(DroxStreamVariant(
            url: _resolve(manifestUrl, lines[next]),
            width: resolution != null && resolution.length == 2 ? int.tryParse(resolution[0]) : null,
            height: resolution != null && resolution.length == 2 ? int.tryParse(resolution[1]) : null,
            bandwidth: int.tryParse(pending['AVERAGE-BANDWIDTH'] ?? pending['BANDWIDTH'] ?? ''),
            codecs: pending['CODECS'],
            audioGroup: pending['AUDIO'],
          ));
          i = next;
        }
      } else if (!line.startsWith('#')) {
        segments.add(_resolve(manifestUrl, line));
      }
    }

    return DroxStreamManifest(
      isHls: true,
      isMaster: variants.isNotEmpty,
      variants: variants,
      segmentUrls: segments,
      durationSeconds: duration > 0 ? duration : null,
      isLive: live,
    );
  }

  List<DroxStreamVariant> analyzeDash(String xml, {required String manifestUrl}) {
    final variants = <DroxStreamVariant>[];
    final adaptationSets = RegExp(r'<AdaptationSet\b([^>]*)>([\s\S]*?)</AdaptationSet>', caseSensitive: false);
    for (final adaptation in adaptationSets.allMatches(xml)) {
      final body = adaptation.group(2) ?? '';
      final reps = RegExp(r'<Representation\b([^>]*)/?>', caseSensitive: false);
      for (final rep in reps.allMatches(body)) {
        final attrs = _attributes(rep.group(1) ?? '');
        final width = int.tryParse(attrs['width'] ?? '');
        final height = int.tryParse(attrs['height'] ?? '');
        final bandwidth = int.tryParse(attrs['bandwidth'] ?? '');
        variants.add(DroxStreamVariant(
          url: _resolve(manifestUrl, attrs['BaseURL'] ?? ''),
          width: width,
          height: height,
          bandwidth: bandwidth,
          codecs: attrs['codecs'],
        ));
      }
    }
    return variants;
  }

  Map<String, String> _attributes(String input) {
    final result = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)', caseSensitive: false);
    for (final match in pattern.allMatches(input)) {
      result[match.group(1)!.toUpperCase()] =
          match.group(2)!.replaceAll('"', '').trim();
    }
    return result;
  }

  String _resolve(String base, String value) {
    if (value.isEmpty) return base;
    return Uri.tryParse(base)?.resolve(value).toString() ?? value;
  }
}
