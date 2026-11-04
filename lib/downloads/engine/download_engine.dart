import 'package:background_downloader/background_downloader.dart';

/// Thin adapter around the platform transfer engine. UI must not call the
/// plugin directly; all task lifecycle operations pass through this class.
class DownloadEngine {
  final FileDownloader _downloader = FileDownloader();

  Stream<TaskUpdate> get updates => _downloader.updates;

  Future<void> initialize() async {
    await _downloader.start(autoCleanDatabase: true);
  }

  Future<DownloadTask> createTask({
    required String url,
    required String filename,
    String directory = 'DROX',
    int retries = 5,
    String? taskId,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('Enter a valid direct HTTP/HTTPS media URL.');
    }
    return DownloadTask(
      url: uri.toString(),
      filename: filename,
      directory: directory,
      baseDirectory: BaseDirectory.downloads,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: retries,
      taskId: taskId,
    );
  }

  Future<void> enqueue(DownloadTask task) async { await _downloader.enqueue(task); }
  Future<bool> pause(DownloadTask task) => _downloader.pause(task);
  Future<bool> resume(DownloadTask task) => _downloader.resume(task);
  Future<void> cancel(DownloadTask task) => _downloader.cancelTaskWithId(task.taskId);
  Future<String> filePath(DownloadTask task) => task.filePath();
}
