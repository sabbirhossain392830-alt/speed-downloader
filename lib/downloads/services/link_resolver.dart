import 'package:dio/dio.dart';

enum DroxLinkKind { directFile, googleDrive, dropbox, oneDrive, mega, mediaFire, box, pCloud, terabox, weTransfer, videoPlatform, webPage, unknown }

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
    'GitHub release assets', 'Internet Archive public files',
  ];

  static const recognizedProviders = <String>[
    'Google Drive', 'Dropbox', 'Microsoft OneDrive', 'MEGA',
    'MediaFire', 'Box', 'pCloud', 'TeraBox', 'WeTransfer',
    '4shared', 'Yandex Disk', 'Sync.com', 'Koofr', 'Send Anywhere',
    'Wormhole', 'Smash', 'Vimeo', 'Dailymotion', 'YouTube',
    'Facebook', 'Instagram', 'TikTok', 'Twitch', 'Reddit', 'X',
    'GitHub', 'GitLab', 'SourceForge', 'Internet Archive',
  ];

  DroxLinkResolution recognize(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return DroxLinkResolution(originalUrl: input, downloadUrl: input, provider: 'Unknown', kind: DroxLinkKind.unknown, canQueue: false, message: 'Enter a valid HTTP/HTTPS link.');
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\\.'), '');
    if (_isDirectFilePath(uri.path)) {
      return DroxLinkResolution(originalUrl: input, downloadUrl: input, provider: 'Direct file', kind: DroxLinkKind.directFile, canQueue: true, message: 'Direct file link detected.', filename: _filename(uri));
    }
    if (host == 'drive.google.com' || host == 'drive.usercontent.google.com') {
      final id = uri.queryParameters['id'] ?? (uri.pathSegments.length > 1 ? uri.pathSegments.last : null);
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
    final base = recognize(input);
    if (!base.canQueue) return base;
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
      if (type == 'text/html' || type == 'application/xhtml+xml') {
        return DroxLinkResolution(originalUrl: input, downloadUrl: base.downloadUrl, provider: base.provider, kind: base.kind, canQueue: false, message: 'This link opens a web page, not a direct file. Use the provider’s authorized download option.');
      }
      return DroxLinkResolution(originalUrl: input, downloadUrl: base.downloadUrl, provider: base.provider, kind: base.kind, canQueue: true, message: base.message, filename: name, contentLength: length, contentType: type);
    } on DioException {
      // Some legitimate hosts reject HEAD. Known provider URL forms remain
      // queueable; the download engine will report the actual transfer result.
      return base;
    }
  }

  DroxLinkResolution _manual(String url, String provider, DroxLinkKind kind, String message) =>
      DroxLinkResolution(originalUrl: url, downloadUrl: url, provider: provider, kind: kind, canQueue: false, message: message);

  bool _isDirectFilePath(String path) => RegExp(r'\\.(mp4|mkv|avi|mov|webm|mp3|m4a|wav|flac|aac|pdf|zip|rar|7z|tar|gz|jpg|jpeg|png|webp|gif|apk|exe|msi|txt|csv|json|xml|docx?|pptx?)$', caseSensitive: false).hasMatch(path);

  String? _filename(Uri uri) => uri.pathSegments.isEmpty ? null : Uri.decodeComponent(uri.pathSegments.last);

  String? _filenameFromDisposition(String? value) {
    if (value == null) return null;
    final utf = RegExp(r"filename\\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(value)?.group(1);
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
