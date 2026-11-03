import 'dart:convert';

import 'package:dio/dio.dart';

enum DroxLinkKind { directFile, googleDrive, dropbox, oneDrive, nextcloud, ownCloud, mega, mediaFire, box, pCloud, terabox, weTransfer, videoPlatform, webPage, unknown }

class DroxLinkResolution {
  const DroxLinkResolution({
    required this.originalUrl,
    required this.downloadUrl,
    required this.provider,
    required this.kind,
    required this.canQueue,
    required this.message,
    this.filename,
    this.contentLength,
    this.contentType,
  });

  final String originalUrl;
  final String downloadUrl;
  final String provider;
  final DroxLinkKind kind;
  final bool canQueue;
  final String message;
  final String? filename;
  final int? contentLength;
  final String? contentType;
}

/// Recognizes common public share links. Only applies documented/public
/// download URL forms; it never signs in, decrypts protected links, scrapes
/// private pages, or bypasses DRM/access controls.
class DroxLinkResolver {
  DroxLinkResolver({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
    followRedirects: true,
    maxRedirects: 8,
    headers: const {'User-Agent': 'DROX-Downloader/1.0', 'Accept': '*/*'},
  ));

  final Dio _dio;

  static const supportedProviders = <String>[
    'Direct HTTP/HTTPS files', 'Google Drive public files',
    'Dropbox public shared files', 'OneDrive public shared files',
    'GitHub release assets', 'Internet Archive public files', 'Nextcloud public shares', 'ownCloud public shares',
  ];

  static const recognizedProviders = <String>[
    'Google Drive', 'Dropbox', 'Microsoft OneDrive', 'MEGA',
    'MediaFire', 'Box', 'pCloud', 'TeraBox', 'WeTransfer',
    '4shared', 'Yandex Disk', 'Sync.com', 'Koofr', 'Send Anywhere', 'Nextcloud', 'ownCloud', 'SharePoint', 'Google Photos',
    'Wormhole', 'Smash', 'Vimeo', 'Dailymotion', 'YouTube',
    'Facebook', 'Instagram', 'TikTok', 'Twitch', 'Reddit', 'X',
    'GitHub', 'GitLab', 'SourceForge', 'Internet Archive',
  ];

  DroxLinkResolution recognize(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return DroxLinkResolution(originalUrl: input, downloadUrl: input, provider: 'Unknown', kind: DroxLinkKind.unknown, canQueue: false, message: 'Enter a valid HTTP/HTTPS link.');
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (_isDirectFilePath(uri.path)) {
      return DroxLinkResolution(originalUrl: input, downloadUrl: input, provider: 'Direct file', kind: DroxLinkKind.directFile, canQueue: true, message: 'Direct file link detected.', filename: _filename(uri));
    }
    if (host == 'drive.google.com' || host == 'drive.usercontent.google.com') {
      final segments = uri.pathSegments;
      final dIndex = segments.indexOf('d');
      final pathId = dIndex >= 0 && dIndex + 1 < segments.length ? segments[dIndex + 1] : null;
      final id = uri.queryParameters['id'] ?? pathId;
      final url = id == null ? input : 'https://drive.google.com/uc?export=download&id=${Uri.encodeQueryComponent(id)}';
      return DroxLinkResolution(originalUrl: input, downloadUrl: url, provider: 'Google Drive', kind: DroxLinkKind.googleDrive, canQueue: id != null, message: id == null ? 'Could not identify a public Drive file ID.' : 'Public Drive download URL prepared. Access permissions may still be required.');
    }
    if (host == 'dropbox.com' || host == 'dropboxusercontent.com') {
      final q = Map<String, String>.from(uri.queryParameters);
      q['dl'] = '1';
      q.remove('raw');
      final url = uri.replace(queryParameters: q).toString();
      return DroxLinkResolution(originalUrl: input, downloadUrl: url, provider: 'Dropbox', kind: DroxLinkKind.dropbox, canQueue: true, message: 'Dropbox direct-download option prepared.');
    }
    if (host == '1drv.ms' || host == 'onedrive.live.com' || host == '1drv.com') {
      final q = Map<String, String>.from(uri.queryParameters)..['download'] = '1';
      return DroxLinkResolution(originalUrl: input, downloadUrl: uri.replace(queryParameters: q).toString(), provider: 'Microsoft OneDrive', kind: DroxLinkKind.oneDrive, canQueue: true, message: 'OneDrive download option prepared; public sharing permission is required.');
    }
    if ((host == 'nextcloud.com' || host.endsWith('.nextcloud.com') || uri.pathSegments.contains('s')) &&
        uri.pathSegments.length >= 2 && uri.pathSegments.contains('s')) {
      final shareIndex = uri.pathSegments.indexOf('s');
      if (shareIndex + 1 < uri.pathSegments.length) {
        final downloadPath = [...uri.pathSegments.take(shareIndex + 2), 'download'];
        final downloadUri = uri.replace(pathSegments: downloadPath, query: null, fragment: null);
        return DroxLinkResolution(originalUrl: input, downloadUrl: downloadUri.toString(), provider: 'Nextcloud', kind: DroxLinkKind.nextcloud, canQueue: true, message: 'Nextcloud public share download prepared; the share must allow downloads.');
      }
    }
    if (host == 'owncloud.com' || host.endsWith('.owncloud.com')) {
      return _manual(input, 'ownCloud', DroxLinkKind.ownCloud, 'Open the public ownCloud share and use its authorized download control.');
    }
    if (host.contains('sharepoint.com') || host.contains('1drv.com')) {
      final q = Map<String, String>.from(uri.queryParameters)..['download'] = '1';
      return DroxLinkResolution(originalUrl: input, downloadUrl: uri.replace(queryParameters: q).toString(), provider: 'SharePoint', kind: DroxLinkKind.oneDrive, canQueue: true, message: 'SharePoint download option prepared; organizational sharing permissions may apply.');
    }
    if (host == 'mega.nz' || host == 'mega.co.nz') return _manual(input, 'MEGA', DroxLinkKind.mega, 'MEGA links need the official client/API and may be encrypted; open the link in MEGA.');
    if (host == 'mediafire.com') return _manual(input, 'MediaFire', DroxLinkKind.mediaFire, 'Open the MediaFire page and use its own download control.');
    if (host == 'box.com' || host.endsWith('.box.com')) return _manual(input, 'Box', DroxLinkKind.box, 'Box sharing permissions or sign-in may be required.');
    if (host == 'pcloud.com' || host.endsWith('.pcloud.com')) return _manual(input, 'pCloud', DroxLinkKind.pCloud, 'Open the public pCloud share page; protected or private shares need authorization.');
    if (host.contains('terabox')) return _manual(input, 'TeraBox', DroxLinkKind.terabox, 'TeraBox may require its official app or account authorization.');
    if (host == 'wetransfer.com' || host.endsWith('.wetransfer.com')) return _manual(input, 'WeTransfer', DroxLinkKind.weTransfer, 'Open the transfer page; expiry and access permissions apply.');
    if (_isVideoHost(host)) return _manual(input, _videoProvider(host), DroxLinkKind.videoPlatform, 'This platform link is recognized, but DROX only downloads media when the platform provides an authorized download link.');
    if (host == 'github.com' && uri.pathSegments.length >= 4 && uri.pathSegments[2] == 'releases') {
      return _manual(input, 'GitHub Releases', DroxLinkKind.webPage, 'Open the release page and select an asset; direct asset URLs can be downloaded in DROX.');
    }
    return DroxLinkResolution(originalUrl: input, downloadUrl: input, provider: host, kind: DroxLinkKind.webPage, canQueue: false, message: 'Web page recognized. DROX will only queue it if it resolves to an actual downloadable file.');
  }

  Future<DroxLinkResolution> resolve(String input) async {
    final parsed = Uri.tryParse(input.trim());
    if (parsed != null && parsed.host.isNotEmpty) {
      final host = parsed.host.toLowerCase().replaceFirst(RegExp(r'^www\\.'), '');
      if (host == 'github.com' &&
          parsed.pathSegments.length >= 5 &&
          parsed.pathSegments[2] == 'releases' &&
          parsed.pathSegments[3] == 'tag') {
        return _resolveGitHubRelease(input, parsed);
      }
      if (host == 'archive.org' &&
          parsed.pathSegments.length >= 2 &&
          parsed.pathSegments[0] == 'details') {
        return _resolveArchiveItem(input, parsed);
      }
    }
    final base = recognize(input);
    if (!base.canQueue && base.kind != DroxLinkKind.webPage) return base;
    if (base.kind == DroxLinkKind.directFile) return base;
    try {
      final response = await _dio.head<dynamic>(base.downloadUrl,
        options: Options(validateStatus: (s) => s != null && s < 500));
      final type = response.headers.value(Headers.contentTypeHeader)?.split(';').first.trim().toLowerCase();
      final length = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
      final disposition = response.headers.value('content-disposition');
      final name = _filenameFromDisposition(disposition) ?? base.filename;
      if (response.statusCode != null && response.statusCode! >= 400) {
        return DroxLinkResolution(originalUrl: input, downloadUrl: base.downloadUrl, provider: base.provider, kind: base.kind, canQueue: false, message: 'The server denied this link (HTTP ${response.statusCode}). Check sharing permissions.');
      }
      if (type == 'text/html' || type == 'application/xhtml+xml' || (type == null && disposition == null)) {
        return DroxLinkResolution(originalUrl: input, downloadUrl: base.downloadUrl, provider: base.provider, kind: base.kind, canQueue: false, message: 'This link opens a web page or could not be verified as a file. Use the website’s authorized download option.');
      }
      return DroxLinkResolution(originalUrl: input, downloadUrl: base.downloadUrl, provider: base.provider, kind: base.kind, canQueue: true, message: base.canQueue ? base.message : 'Direct file response detected from this website.', filename: name, contentLength: length, contentType: type);
    } on DioException {
      // Some legitimate hosts reject HEAD. Known provider URL forms remain
      // queueable; the download engine will report the actual transfer result.
      return base;
    }
  }

  Future<DroxLinkResolution> _resolveGitHubRelease(String input, Uri uri) async {
    final p = uri.pathSegments;
    if (p.length < 5 || p[3] != 'tag') {
      return _manual(input, 'GitHub Releases', DroxLinkKind.webPage, 'Open the release page and select a specific asset. Direct asset links can be downloaded in DROX.');
    }
    try {
      final owner = p[0], repo = p[1], tag = p.sublist(4).join('/');
      final api = Uri.https('api.github.com', '/repos/$owner/$repo/releases/tags/$tag');
      final response = await _dio.get<dynamic>(api.toString(), options: Options(headers: {'Accept': 'application/vnd.github+json'}));
      final data = response.data is String ? jsonDecode(response.data as String) : response.data;
      final assets = (data is Map ? data['assets'] : null) as List? ?? const [];
      final downloadable = assets.whereType<Map>().where((a) => a['browser_download_url'] is String).toList();
      if (downloadable.length != 1) {
        return _manual(input, 'GitHub Releases', DroxLinkKind.webPage,
          downloadable.isEmpty ? 'No public release assets were found. Open the release page to inspect available files.' : 'This release has ${downloadable.length} assets. Open GitHub and choose the exact asset you want.');
      }
      final asset = downloadable.single;
      final url = asset['browser_download_url'] as String;
      return DroxLinkResolution(originalUrl: input, downloadUrl: url, provider: 'GitHub Releases', kind: DroxLinkKind.directFile, canQueue: true, message: 'One public release asset found.', filename: asset['name'] as String?, contentLength: asset['size'] is int ? asset['size'] as int : null, contentType: null);
    } on DioException {
      return _manual(input, 'GitHub Releases', DroxLinkKind.webPage, 'Could not read public release assets. Open GitHub and choose an asset manually.');
    } on FormatException {
      return _manual(input, 'GitHub Releases', DroxLinkKind.webPage, 'GitHub returned an unexpected release response. Open the release page and choose an asset.');
    }
  }

  Future<DroxLinkResolution> _resolveArchiveItem(String input, Uri uri) async {
    final index = uri.pathSegments.indexOf('details');
    final identifier = uri.pathSegments[index + 1];
    try {
      final api = Uri.https('archive.org', '/metadata/$identifier');
      final response = await _dio.get<dynamic>(api.toString());
      final data = response.data is String ? jsonDecode(response.data as String) : response.data;
      final files = (data is Map ? data['files'] : null) as List? ?? const [];
      final downloadable = files.whereType<Map>().where((file) {
        final name = file['name'];
        final source = file['source'];
        return name is String && source != 'metadata' && _isDirectFilePath(name);
      }).toList();
      if (downloadable.length != 1) {
        return _manual(input, 'Internet Archive', DroxLinkKind.webPage,
          downloadable.isEmpty ? 'No single supported public file was found in this item.' : 'This item contains ${downloadable.length} downloadable files. Open the item and choose a specific file.');
      }
      final file = downloadable.single;
      final name = file['name'] as String;
      final url = Uri.https('archive.org', '/download/$identifier/${Uri.encodeComponent(name)}').toString();
      final size = int.tryParse('${file['size'] ?? ''}');
      return DroxLinkResolution(originalUrl: input, downloadUrl: url, provider: 'Internet Archive', kind: DroxLinkKind.directFile, canQueue: true, message: 'One public downloadable file found.', filename: name, contentLength: size);
    } on DioException {
      return _manual(input, 'Internet Archive', DroxLinkKind.webPage, 'Could not read item metadata. Open the Archive item and select a file.');
    } on FormatException {
      return _manual(input, 'Internet Archive', DroxLinkKind.webPage, 'The item metadata could not be read.');
    }
  }

  DroxLinkResolution _manual(String url, String provider, DroxLinkKind kind, String message) =>
      DroxLinkResolution(originalUrl: url, downloadUrl: url, provider: provider, kind: kind, canQueue: false, message: message);

  bool _isDirectFilePath(String path) => RegExp(r'\.(mp4|m4v|mkv|avi|mov|webm|ogv|3gp|mpeg|mpg|mp3|m4a|wav|flac|aac|ogg|opus|pdf|epub|zip|rar|7z|tar|gz|bz2|xz|iso|dmg|apk|aab|exe|msi|deb|rpm|jpg|jpeg|png|webp|gif|bmp|svg|tif|tiff|txt|csv|json|xml|html|docx?|xlsx?|pptx?|odt|ods|odp|srt|vtt|ass|ssa|ttf|otf|woff2?)$', caseSensitive: false).hasMatch(path);

  String? _filename(Uri uri) => uri.pathSegments.isEmpty ? null : Uri.decodeComponent(uri.pathSegments.last);

  String? _filenameFromDisposition(String? value) {
    if (value == null) return null;
    final utf = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(value)?.group(1);
    final plain = RegExp(r'filename="?([^";]+)', caseSensitive: false).firstMatch(value)?.group(1);
    final raw = utf ?? plain;
    if (raw == null) return null;
    try { return Uri.decodeComponent(raw); } catch (_) { return raw; }
  }

  bool _isVideoHost(String host) => <String>[
    'youtube.com', 'youtu.be', 'vimeo.com', 'dailymotion.com',
    'facebook.com', 'fb.watch', 'instagram.com', 'tiktok.com',
    'twitch.tv', 'reddit.com', 'redd.it', 'x.com', 'twitter.com',
  ].any((domain) => host == domain || host.endsWith('.$domain'));

  String _videoProvider(String host) {
    if (host.contains('youtube') || host == 'youtu.be') return 'YouTube';
    if (host.contains('vimeo')) return 'Vimeo';
    if (host.contains('dailymotion')) return 'Dailymotion';
    if (host.contains('facebook') || host == 'fb.watch') return 'Facebook';
    if (host.contains('instagram')) return 'Instagram';
    if (host.contains('tiktok')) return 'TikTok';
    if (host.contains('twitch')) return 'Twitch';
    if (host.contains('reddit') || host == 'redd.it') return 'Reddit';
    return 'X';
  }
}
