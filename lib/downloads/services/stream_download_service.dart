import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/return_code.dart';

class DroxStreamDownloadResult {
  const DroxStreamDownloadResult({
    required this.outputPath,
    required this.bytes,
    required this.durationSeconds,
  });

  final String outputPath;
  final int bytes;
  final double durationSeconds;
}

/// Uses FFmpeg to fetch HLS/DASH segments and remux the selected stream into
/// a playable MP4 container. It deliberately does not attempt to bypass DRM,
/// authentication, or CDN security challenges.
class DroxStreamDownloadService {
  Future<DroxStreamDownloadResult> download({
    required String manifestUrl,
    required String outputPath,
    double? durationSeconds,
    Map<String, String> headers = const {},
    void Function(double progress, int bytes, double elapsedSeconds)? onProgress,
    void Function(int sessionId)? onSessionId,
  }) async {
    final uri = Uri.tryParse(manifestUrl);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        !_isManifest(uri)) {
      throw const FormatException('A valid HLS (.m3u8) or DASH (.mpd) URL is required.');
    }

    final output = File(outputPath);
    await output.parent.create(recursive: true);
    if (await output.exists()) await output.delete();

    final headerArgument = headers.entries
        .map((entry) => '${entry.key}: ${entry.value}\r\n')
        .join();
    final headersOption = headerArgument.isEmpty
        ? ''
        : '-headers ${_quote(headerArgument)} ';
    final command = '-y -hide_banner -loglevel warning '
        '-protocol_whitelist file,http,https,tcp,tls,crypto '
        '$headersOption'
        '-allowed_extensions ALL -i ${_quote(manifestUrl)} '
        '-map 0:v? -map 0:a? -sn -dn -c copy '
        '-movflags +faststart ${_quote(outputPath)}';

    final completer = Completer<DroxStreamDownloadResult>();
    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        if (completer.isCompleted) return;
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          if (!await output.exists() || await output.length() <= 0) {
            completer.completeError(StateError('FFmpeg finished without creating a media file.'));
            return;
          }
          final size = await output.length();
          final duration = durationSeconds ?? 0;
          onProgress?.call(1, size, duration);
          completer.complete(DroxStreamDownloadResult(
            outputPath: outputPath,
            bytes: size,
            durationSeconds: duration,
          ));
        } else if (ReturnCode.isCancel(code)) {
          completer.completeError(StateError('Stream download was cancelled.'));
        } else {
          final logs = await session.getOutput() ?? '';
          final tail = logs.length > 900 ? logs.substring(logs.length - 900) : logs;
          completer.completeError(StateError(
            'Could not fetch or merge this stream. The link may have expired, '
            'require a site session, or be protected. $tail',
          ));
        }
      },
      null,
      (statistics) {
        final elapsedMs = statistics.getTime();
        final size = statistics.getSize();
        final elapsed = elapsedMs / 1000.0;
        final progress = durationSeconds != null && durationSeconds > 0
            ? (elapsed / durationSeconds).clamp(0.0, 0.99).toDouble()
            : 0.0;
        onProgress?.call(progress, size, elapsed);
      },
    );
    onSessionId?.call(await session.getSessionId());
    return completer.future;
  }

  Future<void> cancel(int sessionId) => FFmpegKit.cancel(sessionId);

  bool _isManifest(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  String _quote(String value) => '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}
