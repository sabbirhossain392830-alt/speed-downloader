class YoutubeLinkInfo {
  const YoutubeLinkInfo({required this.videoId, required this.canonicalUrl});
  final String videoId;
  final String canonicalUrl;

  static YoutubeLinkInfo? parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    String? id;
    if (host == 'youtu.be') {
      if (uri.pathSegments.isNotEmpty) id = uri.pathSegments.first;
    } else if (host == 'youtube.com' || host == 'm.youtube.com' || host == 'music.youtube.com') {
      if (uri.path == '/watch') {
        id = uri.queryParameters['v'];
      } else if (uri.pathSegments.length >= 2 && const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
        id = uri.pathSegments[1];
      }
    }
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return null;
    return YoutubeLinkInfo(videoId: id, canonicalUrl: 'https://www.youtube.com/watch?v=$id');
  }

  String get oEmbedUrl => 'https://www.youtube.com/oembed?url=${Uri.encodeComponent(canonicalUrl)}&format=json';
}

class YoutubePreview {
  const YoutubePreview({required this.title, required this.authorName, required this.thumbnailUrl, required this.videoUrl});
  final String title;
  final String authorName;
  final String thumbnailUrl;
  final String videoUrl;

  factory YoutubePreview.fromJson(Map<String, dynamic> json, YoutubeLinkInfo link) {
    return YoutubePreview(
      title: (json['title'] as String?)?.trim().isNotEmpty == true ? json['title'] as String : 'YouTube video',
      authorName: (json['author_name'] as String?) ?? 'YouTube',
      thumbnailUrl: (json['thumbnail_url'] as String?) ?? 'https://i.ytimg.com/vi/${link.videoId}/hqdefault.jpg',
      videoUrl: link.canonicalUrl,
    );
  }
}
