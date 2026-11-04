import 'package:flutter_test/flutter_test.dart';
import 'package:speed_downloader/downloads/services/link_resolver.dart';

void main() {
  test('DROX recognizes its app-level direct download URL contract', () {
    final result = DroxLinkResolver().recognize(
      'https://cdn.example.com/files/sample-video.mp4',
    );
    expect(result.canQueue, isTrue);
    expect(result.filename, 'sample-video.mp4');
  });
}
