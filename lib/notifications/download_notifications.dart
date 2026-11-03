import 'package:background_downloader/background_downloader.dart';

void configureDroxNotifications(bool enabled, {bool bangla = false}) {
  // Use the downloader's per-task notification as the single source of truth.
  // Do not post a second custom native notification for the same transfer.
  FileDownloader().configureNotification(
    running: enabled
        ? TaskNotification(
            bangla ? 'DROX • ডাউনলোড হচ্ছে • {filename}' : 'DROX • Downloading • {filename}',
            '{downloaded} / {total} • {progress} • {networkSpeed}',
          )
        : null,
    paused: enabled
        ? TaskNotification(
            bangla ? 'DROX • বিরতিতে • {filename}' : 'DROX • Paused • {filename}',
            '{downloaded} / {total} • {progress}',
          )
        : null,
    complete: enabled
        ? TaskNotification(
            bangla ? 'DROX • সম্পন্ন • {filename}' : 'DROX • Complete • {filename}',
            '{total} • 100%',
          )
        : null,
    error: enabled
        ? TaskNotification(
            bangla ? 'DROX • ডাউনলোড ব্যর্থ' : 'DROX • Download Failed',
            '{filename}',
          )
        : null,
    progressBar: true,
    tapOpensFile: false,
  );
}
