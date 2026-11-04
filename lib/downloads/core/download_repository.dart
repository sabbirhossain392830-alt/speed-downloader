import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_item.dart';

/// Persists only DROX-owned download metadata. Native transfer state remains
/// managed by background_downloader.
class DownloadRepository {
  static const _storageKey = 'drox_downloads_v2';

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(Iterable<DroxDownloadItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final data = items.map((item) => {
      'id': item.id,
      'url': item.url,
      'filename': item.task.filename,
      'displayFilename': item.renamedFilename,
      'renamedPath': item.renamedPath,
      'state': item.state.name,
      'progress': item.progress,
      'expectedBytes': item.expectedBytes,
      'downloadedBytes': item.downloadedBytes,
      'error': item.error,
      'isStream': item.isStream,
      'youtube': item.youtube?.toJson(),
    }).toList();
    await prefs.setString(_storageKey, jsonEncode(data));
  }
}
