import 'package:background_downloader/background_downloader.dart';

class DownloadEntry {
  DownloadEntry(this.task);
  DownloadTask task;
  double progress = 0;
  int expectedFileSize = -1;
  String status = 'কিউতে আছে';
  String? error;
  String? sharedPath;
  int lastDownloadedBytes = 0;
  DateTime? lastSpeedSampleAt;
  double speedBytesPerSecond = 0;
}

enum DownloadFilter { all, active, completed, failed, scheduled }
