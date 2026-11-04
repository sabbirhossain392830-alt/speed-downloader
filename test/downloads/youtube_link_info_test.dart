import 'package:flutter_test/flutter_test.dart';
import 'package:speed_downloader/downloads/youtube/youtube_link_info.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  test('parses a normal watch link with www', () {
    final link = YoutubeLinkInfo.parse('https://www.youtube.com/watch?v=$id');
    expect(link?.videoId, id);
    expect(link?.canonicalUrl, 'https://www.youtube.com/watch?v=$id');
  });

  test('parses watch links with extra query parameters', () {
    final link = YoutubeLinkInfo.parse('https://www.youtube.com/watch?v=$id&t=42s&list=PL123');
    expect(link?.videoId, id);
  });

  test('parses mobile and music hosts', () {
    expect(YoutubeLinkInfo.parse('https://m.youtube.com/watch?v=$id')?.videoId, id);
    expect(YoutubeLinkInfo.parse('https://music.youtube.com/watch?v=$id')?.videoId, id);
  });

  test('parses youtu.be short links', () {
    expect(YoutubeLinkInfo.parse('https://youtu.be/$id?si=abc')?.videoId, id);
  });

  test('parses shorts, embed and live links', () {
    expect(YoutubeLinkInfo.parse('https://www.youtube.com/shorts/$id')?.videoId, id);
    expect(YoutubeLinkInfo.parse('https://www.youtube.com/embed/$id')?.videoId, id);
    expect(YoutubeLinkInfo.parse('https://www.youtube.com/live/$id')?.videoId, id);
  });

  test('rejects other hosts, bad ids and non-http schemes', () {
    expect(YoutubeLinkInfo.parse('https://vimeo.com/watch?v=$id'), isNull);
    expect(YoutubeLinkInfo.parse('https://www.youtube.com/watch?v=short'), isNull);
    expect(YoutubeLinkInfo.parse('https://www.youtube.com/watch'), isNull);
    expect(YoutubeLinkInfo.parse('ftp://www.youtube.com/watch?v=$id'), isNull);
    expect(YoutubeLinkInfo.parse('not a url'), isNull);
  });
}
