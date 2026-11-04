import 'package:background_downloader/background_downloader.dart';

enum DroxDownloadState { queued, running, paused, complete, failed, cancelled }

class DroxDownloadItem {
  DroxDownloadItem({required this.task, this.state = DroxDownloadState.queued, this.progress = 0, this.expectedBytes = -1, this.error});
  final DownloadTask task;
  DroxDownloadState state;
  double progress;
  int expectedBytes;
  String? error;
  double speedBytesPerSecond = 0;
  DateTime? speedSampleAt;
  int speedSampleBytes = 0;
  int downloadedBytes = 0;

  String get id => task.taskId;
  String get filename => task.filename;
  String get url => task.url;

  factory DroxDownloadItem.fromTask(DownloadTask task) => DroxDownloadItem(task: task);
}
