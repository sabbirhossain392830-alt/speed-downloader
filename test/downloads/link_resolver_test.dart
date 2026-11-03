import 'package:flutter_test/flutter_test.dart';
import 'package:speed_downloader/downloads/services/link_resolver.dart';

void main() {
  final resolver = DroxLinkResolver();

  test('recognizes direct file URLs', () {
    final result = resolver.recognize('https://cdn.example.com/movie.mp4');
    expect(result.canQueue, isTrue);
    expect(result.kind, DroxLinkKind.directFile);
    expect(result.filename, 'movie.mp4');
  });

  test('prepares public Google Drive download URL', () {
    final result = resolver.recognize('https://drive.google.com/file/d/FILE_ID/view?usp=sharing');
    expect(result.provider, 'Google Drive');
    expect(result.canQueue, isTrue);
    expect(result.downloadUrl, contains('id=FILE_ID'));
  });

  test('prepares Dropbox direct download option', () {
    final result = resolver.recognize('https://www.dropbox.com/s/example/file.zip?dl=0');
    expect(result.provider, 'Dropbox');
    expect(result.downloadUrl, contains('dl=1'));
  });

  test('recognizes OneDrive shared links', () {
    final result = resolver.recognize('https://1drv.ms/u/s!example');
    expect(result.provider, 'Microsoft OneDrive');
    expect(result.downloadUrl, contains('download=1'));
  });

  test('recognizes direct GitHub release asset URLs', () {
    final result = resolver.recognize('https://github.com/user/project/releases/download/v1.0/app.apk');
    expect(result.canQueue, isTrue);
    expect(result.kind, DroxLinkKind.directFile);
    expect(result.filename, 'app.apk');
  });

  test('recognizes direct Internet Archive download URLs', () {
    final result = resolver.recognize('https://archive.org/download/sample/movie.mp4');
    expect(result.canQueue, isTrue);
    expect(result.kind, DroxLinkKind.directFile);
  });

  test('does not claim protected video platform pages are downloadable', () {
    final result = resolver.recognize('https://www.youtube.com/watch?v=abcdefghijk');
    expect(result.provider, 'YouTube');
    expect(result.canQueue, isFalse);
  });

  test('rejects non-http schemes', () {
    expect(resolver.recognize('file:///storage/movie.mp4').canQueue, isFalse);
  });
}
