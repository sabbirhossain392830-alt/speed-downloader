import 'package:background_downloader/background_downloader.dart';

import '../youtube/youtube_download_option.dart';

enum DroxDownloadState { queued, running, paused, complete, failed, cancelled }

class DroxDownloadItem {
  DroxDownloadItem({required this.task, this.state = DroxDownloadState.queued, this.progress = 0, this.expectedBytes = -1, this.error, this.isStream = false});
  DownloadTask task;
  DroxDownloadState state;
  double progress;
  int expectedBytes;
  String? error;
  bool isStream;

  /// Set only for YouTube downloads; lets a failed/interrupted item be retried.
  YoutubeJob? youtube;
  double speedBytesPerSecond = 0;
  DateTime? speedSampleAt;
  int speedSampleBytes = 0;
  int downloadedBytes = 0;
  String? renamedFilename;
  String? renamedPath;

  String get id => task.taskId;
  String get filename => renamedFilename ?? task.filename;
  String get url => task.url;

  factory DroxDownloadItem.fromTask(DownloadTask task) => DroxDownloadItem(task: task);
}
