import 'dart:convert';

import 'package:dio/dio.dart';

class DroxMediaVerification {
  const DroxMediaVerification({
    required this.isMedia,
    required this.url,
    required this.contentType,
    required this.filename,
    required this.contentLength,
    required this.reason,
    this.isStreamingManifest = false,
  });

  final bool isMedia;
  final String url;
  final String? contentType;
  final String? filename;
  final int? contentLength;
  final String reason;
  final bool isStreamingManifest;
}

/// Verifies a candidate URL before DROX presents a download prompt.
/// Uses HEAD first, then a bounded Range request for hosts that reject HEAD
/// or return incomplete metadata. It never downloads the full response here.
class DroxMediaVerifier {
  DroxMediaVerifier({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
              followRedirects: true,
              maxRedirects: 8,
              maxContentLength: 4096,
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
                'Accept': '*/*',
              },
            ));

  final Dio _dio;

  Future<DroxMediaVerification> verify(String input) async {
    final uri = Uri.tryParse(input);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return _reject(input, 'Invalid HTTP URL.');
    }

    Response<dynamic>? head;
    try {
      head = await _dio.head<dynamic>(input,
          options: Options(validateStatus: (s) => s != null && s < 500));
      final status = head.statusCode ?? 0;
      if (status >= 400 && status != 405 && status != 501) return _reject(input, 'HTTP $status');
      final type = _cleanType(head.headers.value(Headers.contentTypeHeader));
      final disposition = head.headers.value('content-disposition');
      final length = int.tryParse(head.headers.value(Headers.contentLengthHeader) ?? '');
      final finalUrl = head.realUri.toString();
      if (_isHtml(type)) return _reject(finalUrl, 'Server returned HTML, not media.');
      if (_isMediaType(type)) {
        return _accept(finalUrl, type, disposition, length,
            manifest: _isManifestPath(finalUrl));
      }
      // HEAD metadata is often missing or generic. Verify a tiny byte range.
    } on DioException {
      // Some CDNs and file hosts reject HEAD; try a bounded Range GET below.
    }

    try {
      final response = await _dio.get<List<int>>(input,
          options: Options(
            responseType: ResponseType.bytes,
            headers: const {'Range': 'bytes=0-2047'},
            validateStatus: (s) => s != null && s < 500,
            followRedirects: true,
          ));
      final status = response.statusCode ?? 0;
      if (status >= 400) return _reject(response.realUri.toString(), 'HTTP $status');
      final bytes = response.data ?? const <int>[];
      final type = _cleanType(response.headers.value(Headers.contentTypeHeader));
      final finalUrl = response.realUri.toString();
      final disposition = response.headers.value('content-disposition');
      final length = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ??
          _rangeTotal(response.headers.value('content-range'));
      if (_looksLikeHtml(bytes) || _isHtml(type)) {
        return _reject(finalUrl, 'Server returned HTML or a security challenge.');
      }
      final signature = _signatureType(bytes);
      final manifest = _looksLikeHls(bytes) || _looksLikeDash(bytes) || _isManifestPath(finalUrl);
      if (manifest || _isMediaType(type) || signature != null) {
        return _accept(finalUrl, signature ?? type, disposition, length,
            manifest: manifest);
      }
      // A server may legitimately serve an unknown binary format. Only trust
      // it when it explicitly advertises attachment and is not HTML.
      if ((disposition ?? '').toLowerCase().contains('attachment') &&
          type == 'application/octet-stream' && bytes.isNotEmpty) {
        return _accept(finalUrl, type, disposition, length);
      }
      return _reject(finalUrl, 'Response could not be verified as media.');
    } on DioException catch (error) {
      // A HEAD response can still be sufficient when Range is unsupported.
      if (head != null) {
        final type = _cleanType(head.headers.value(Headers.contentTypeHeader));
        if (_isMediaType(type)) {
          return _accept(head.realUri.toString(), type,
              head.headers.value('content-disposition'),
              int.tryParse(head.headers.value(Headers.contentLengthHeader) ?? ''));
        }
      }
      return _reject(input, error.message ?? 'Could not verify server response.');
    }
  }

  DroxMediaVerification _accept(String url, String? type, String? disposition,
      int? length, {bool manifest = false}) {
    return DroxMediaVerification(
      isMedia: true,
      url: url,
      contentType: type,
      filename: _filenameFromDisposition(disposition),
      contentLength: length,
      reason: manifest ? 'Streaming manifest verified.' : 'Media response verified.',
      isStreamingManifest: manifest,
    );
  }

  DroxMediaVerification _reject(String url, String reason) =>
      DroxMediaVerification(
        isMedia: false,
        url: url,
        contentType: null,
        filename: null,
        contentLength: null,
        reason: reason,
      );

  String? _cleanType(String? value) =>
      value?.split(';').first.trim().toLowerCase();

  bool _isHtml(String? type) =>
      type == 'text/html' || type == 'application/xhtml+xml';

  bool _isMediaType(String? type) =>
      type != null &&
      (type.startsWith('video/') ||
          type.startsWith('audio/') ||
          type == 'application/vnd.apple.mpegurl' ||
          type == 'application/x-mpegurl' ||
          type == 'application/dash+xml');

  bool _isManifestPath(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  bool _looksLikeHtml(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final sample = utf8.decode(bytes.take(1024).toList(), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return sample.startsWith('<!doctype html') ||
        sample.startsWith('<html') ||
        sample.startsWith('<head') ||
        sample.startsWith('<body') ||
        sample.contains('cf-chl-') ||
        sample.contains('cloudflare') && sample.contains('challenge');
  }

  bool _looksLikeHls(List<int> bytes) {
    final text = utf8.decode(bytes.take(1024).toList(), allowMalformed: true).trimLeft();
    return text.startsWith('#EXTM3U');
  }

  bool _looksLikeDash(List<int> bytes) {
    final text = utf8.decode(bytes.take(2048).toList(), allowMalformed: true).trimLeft();
    return text.startsWith('<?xml') && text.contains('<MPD') ||
        text.startsWith('<MPD');
  }

  String? _signatureType(List<int> b) {
    if (b.length >= 12 &&
        b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return 'video/mp4';
    }
    if (b.length >= 4 && b[0] == 0x1A && b[1] == 0x45 &&
        b[2] == 0xDF && b[3] == 0xA3) return 'video/webm';
    if (b.length >= 4 && ascii.decode(b.take(3).toList(), allowInvalid: true) == 'FLV') {
      return 'video/x-flv';
    }
    if (b.length >= 12 && ascii.decode(b.take(4).toList(), allowInvalid: true) == 'RIFF' &&
        ascii.decode(b.skip(8).take(4).toList(), allowInvalid: true) == 'AVI ') {
      return 'video/x-msvideo';
    }
    if (b.length >= 189 && b[0] == 0x47 && b[188] == 0x47 && (b.length < 377 || b[376] == 0x47)) return 'video/mp2t';
    return null;
  }

  int? _rangeTotal(String? value) {
    if (value == null) return null;
    final match = RegExp(r'/([0-9]+)$').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String? _filenameFromDisposition(String? value) {
    if (value == null) return null;
    final match = RegExp(r"filename\\*=UTF-8''([^;]+)", caseSensitive: false)
            .firstMatch(value) ??
        RegExp(r'filename="?([^";]+)', caseSensitive: false).firstMatch(value);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Uri.decodeComponent(raw.replaceAll('"', '').trim());
    } catch (_) {
      return raw.replaceAll('"', '').trim();
    }
  }
}
