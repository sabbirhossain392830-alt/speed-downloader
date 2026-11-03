import 'package:dio/dio.dart';
import '../youtube/youtube_link_info.dart';

/// Uses YouTube's public oEmbed metadata endpoint for title, channel and
/// thumbnail only. It does not extract media streams or bypass download rules.
class YoutubeMetadataService {
  YoutubeMetadataService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: const {'Accept': 'application/json'},
  ));

  final Dio _dio;

  Future<YoutubePreview> fetch(YoutubeLinkInfo link) async {
    final response = await _dio.getUri(Uri.parse(link.oEmbedUrl));
    if (response.statusCode != 200 || response.data is! Map) {
      throw Exception('YouTube preview is unavailable for this link.');
    }
    return YoutubePreview.fromJson(Map<String, dynamic>.from(response.data as Map), link);
  }
}
