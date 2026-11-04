class DroxStreamVariant {
  const DroxStreamVariant({
    required this.url,
    this.width,
    this.height,
    this.bandwidth,
    this.codecs,
    this.audioGroup,
    this.segmentTemplate,
    this.initializationTemplate,
    this.startNumber,
    this.timescale,
  });

  final String url;
  final int? width;
  final int? height;
  final int? bandwidth;
  final String? codecs;
  final String? audioGroup;
  final String? segmentTemplate;
  final String? initializationTemplate;
  final int? startNumber;
  final int? timescale;

  String get qualityLabel {
    if (height != null) return '${height}p';
    if (bandwidth != null) return '${(bandwidth! / 1000).round()} kbps';
    return 'Unknown quality';
  }
}

class DroxStreamRendition {
  const DroxStreamRendition({
    required this.type,
    required this.groupId,
    required this.name,
    required this.url,
    this.language,
    this.isDefault = false,
    this.isAutoselect = false,
  });

  final String type;
  final String groupId;
  final String name;
  final String url;
  final String? language;
  final bool isDefault;
  final bool isAutoselect;
}

class DroxStreamManifest {
  const DroxStreamManifest({
    required this.isHls,
    required this.isMaster,
    required this.variants,
    required this.segmentUrls,
    this.renditions = const [],
    this.durationSeconds,
    this.isLive = false,
  });

  final bool isHls;
  final bool isMaster;
  final List<DroxStreamVariant> variants;
  final List<DroxStreamRendition> renditions;
  final List<String> segmentUrls;
  final double? durationSeconds;
  final bool isLive;
}

/// Inspects public HLS/DASH metadata. It does not bypass DRM or access controls.
class DroxStreamManifestAnalyzer {
  DroxStreamManifest analyzeHls(String source, {required String manifestUrl}) {
    final lines = source.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
    final variants = <DroxStreamVariant>[];
    final renditions = <DroxStreamRendition>[];
    final segments = <String>[];
    var duration = 0.0;
    var live = true;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      if (line == '#EXT-X-ENDLIST') live = false;
      if (line.startsWith('#EXTINF:')) {
        duration += double.tryParse(line.substring(8).split(',').first) ?? 0;
      }
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final attrs = _attributes(line.substring('#EXT-X-MEDIA:'.length));
        final uri = attrs['URI'];
        renditions.add(DroxStreamRendition(
          type: attrs['TYPE'] ?? 'UNKNOWN',
          groupId: attrs['GROUP-ID'] ?? '',
          name: attrs['NAME'] ?? attrs['LANGUAGE'] ?? 'Track',
          url: uri == null ? manifestUrl : _resolve(manifestUrl, uri),
          language: attrs['LANGUAGE'],
          isDefault: attrs['DEFAULT'] == 'YES',
          isAutoselect: attrs['AUTOSELECT'] == 'YES',
        ));
      }
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final attrs = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
        var next = i + 1;
        while (next < lines.length && (lines[next].isEmpty || lines[next].startsWith('#'))) {
          next++;
        }
        if (next < lines.length) {
          final resolution = attrs['RESOLUTION']?.split('x');
          variants.add(DroxStreamVariant(
            url: _resolve(manifestUrl, lines[next]),
            width: resolution != null && resolution.length == 2 ? int.tryParse(resolution[0]) : null,
            height: resolution != null && resolution.length == 2 ? int.tryParse(resolution[1]) : null,
            bandwidth: int.tryParse(attrs['AVERAGE-BANDWIDTH'] ?? attrs['BANDWIDTH'] ?? ''),
            codecs: attrs['CODECS'],
            audioGroup: attrs['AUDIO'],
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
      renditions: renditions,
      segmentUrls: segments,
      durationSeconds: duration > 0 ? duration : null,
      isLive: live,
    );
  }

  List<DroxStreamVariant> analyzeDash(String xml, {required String manifestUrl}) {
    final variants = <DroxStreamVariant>[];
    final mpdBase = _childBaseUrl(xml, manifestUrl);
    final periods = RegExp(r'<Period\b[^>]*>([\s\S]*?)</Period>', caseSensitive: false);
    final periodMatches = periods.allMatches(xml).toList();
    final periodBodies = periodMatches.isEmpty ? [xml] : periodMatches.map((m) => m.group(1) ?? '').toList();

    for (final periodBody in periodBodies) {
      final periodBase = _childBaseUrl(periodBody, mpdBase);
      final adaptations = RegExp(r'<AdaptationSet\b([^>]*)>([\s\S]*?)</AdaptationSet>', caseSensitive: false);
      for (final adaptation in adaptations.allMatches(periodBody)) {
        final adaptationAttrs = _attributes(adaptation.group(1) ?? '');
        final adaptationBody = adaptation.group(2) ?? '';
        final adaptationBase = _childBaseUrl(adaptationBody, periodBase);
        final inheritedTemplate = _firstTagAttributes(adaptationBody, 'SegmentTemplate');
        final reps = RegExp(r'<Representation\b([^>]*?)(?:/\s*>|>([\s\S]*?)</Representation>)', caseSensitive: false);
        for (final rep in reps.allMatches(adaptationBody)) {
          final attrs = _attributes(rep.group(1) ?? '');
          final repBody = rep.group(2) ?? '';
          final repBase = _childBaseUrl(repBody, adaptationBase);
          final template = _firstTagAttributes(repBody, 'SegmentTemplate').isNotEmpty
              ? _firstTagAttributes(repBody, 'SegmentTemplate')
              : inheritedTemplate;
          final width = int.tryParse(attrs['width'] ?? adaptationAttrs['width'] ?? '');
          final height = int.tryParse(attrs['height'] ?? adaptationAttrs['height'] ?? '');
          final bandwidth = int.tryParse(attrs['bandwidth'] ?? '');
          final media = template['media'];
          final initialization = template['initialization'];
          variants.add(DroxStreamVariant(
            url: repBase,
            width: width,
            height: height,
            bandwidth: bandwidth,
            codecs: attrs['codecs'] ?? adaptationAttrs['codecs'],
            segmentTemplate: media,
            initializationTemplate: initialization,
            startNumber: int.tryParse(template['startNumber'] ?? ''),
            timescale: int.tryParse(template['timescale'] ?? ''),
          ));
        }
      }
    }
    return variants;
  }

  String _childBaseUrl(String xml, String fallback) {
    final match = RegExp(r'<BaseURL\b[^>]*>([\s\S]*?)</BaseURL>', caseSensitive: false).firstMatch(xml);
    if (match == null) return fallback;
    final value = _decodeXml(match.group(1)!.trim());
    return value.isEmpty ? fallback : _resolve(fallback, value);
  }

  Map<String, String> _firstTagAttributes(String xml, String tag) {
    final match = RegExp('<$tag\\b([^>]*)>', caseSensitive: false).firstMatch(xml);
    return match == null ? <String, String>{} : _attributes(match.group(1) ?? '');
  }

  String _decodeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  Map<String, String> _attributes(String input) {
    final result = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9_-]+)=("[^"]*"|[^,\s]*)', caseSensitive: false);
    for (final match in pattern.allMatches(input)) {
      result[match.group(1)!.toLowerCase()] =
          match.group(2)!.replaceAll('"', '').trim();
    }
    return result;
  }

  String _resolve(String base, String value) {
    if (value.isEmpty) return base;
    return Uri.tryParse(base)?.resolve(value).toString() ?? value;
  }
}
