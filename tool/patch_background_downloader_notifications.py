from pathlib import Path

cache = Path.home() / ".pub-cache" / "hosted" / "pub.dev"
packages = sorted(cache.glob("background_downloader-*"))
if not packages:
    raise SystemExit("background_downloader package was not found in pub cache")
package = packages[-1]
root = package / "android" / "src" / "main" / "kotlin" / "com" / "bbflight" / "background_downloader"
if not root.is_dir():
    raise SystemExit(f"Android Kotlin source directory not found: {root}")

def patch(file_name, replacements):
    path = root / file_name
    source = path.read_text()
    for old, new in replacements:
        count = source.count(old)
        if count != 1:
            raise SystemExit(f"{file_name}: expected one patch anchor, found {count}: {old[:90]!r}")
        source = source.replace(old, new, 1)
    path.write_text(source)
    print(f"Patched {file_name}")

patch("TaskRunner.kt", [
    ("    var notificationProgress: Double\n    var networkSpeed: Double",
     "    var notificationProgress: Double\n    var notificationExpectedFileSize: Long\n    var networkSpeed: Double"),
    ("        progress: Double = 2.0,\n        timeRemaining: Long = -1000\n    )",
     "        progress: Double = 2.0,\n        timeRemaining: Long = -1000,\n        expectedFileSize: Long = -1\n    )"),
    ("            progress, timeRemaining\n        )\n        lastProgressUpdate",
     "            progress, timeRemaining, expectedFileSize\n        )\n        lastProgressUpdate"),
])

patch("TaskWorker.kt", [
    ("    override var notificationProgress: Double = 2.0 // indeterminate\n    override var networkSpeed: Double",
     "    override var notificationProgress: Double = 2.0 // indeterminate\n    override var notificationExpectedFileSize: Long = -1\n    override var networkSpeed: Double"),
    ("        progress: Double,\n        timeRemaining: Long\n    ) {\n        NotificationService.updateNotification(this, status, progress, timeRemaining)",
     "        progress: Double,\n        timeRemaining: Long,\n        expectedFileSize: Long\n    ) {\n        NotificationService.updateNotification(this, status, progress, timeRemaining, expectedFileSize)"),
])

patch("UIDTJobService.kt", [
    ("        override var notificationProgress: Double = 2.0\n        override var networkSpeed: Double",
     "        override var notificationProgress: Double = 2.0\n        override var notificationExpectedFileSize: Long = -1\n        override var networkSpeed: Double"),
    ("            progress: Double,\n            timeRemaining: Long\n        ) {\n            NotificationService.updateNotification(this, status, progress, timeRemaining)",
     "            progress: Double,\n            timeRemaining: Long,\n            expectedFileSize: Long\n        ) {\n            NotificationService.updateNotification(this, status, progress, timeRemaining, expectedFileSize)"),
])

patch("Notifications.kt", [
    ("        progress: Double = 2.0,\n        timeRemaining: Long = -1000\n    ) {\n        val notificationType",
     "        progress: Double = 2.0,\n        timeRemaining: Long = -1000,\n        expectedFileSize: Long = -1\n    ) {\n        val notificationType"),
    ("        taskWorker.notificationProgress =\n            if (notificationType == NotificationType.paused) taskWorker.notificationProgress else progress\n        // title and body interpolation",
     "        if (expectedFileSize > 0) taskWorker.notificationExpectedFileSize = expectedFileSize\n        taskWorker.notificationProgress = when {\n            notificationType == NotificationType.paused -> taskWorker.notificationProgress\n            taskStatus == TaskStatus.complete -> 1.0\n            progress == 2.0 && notificationType != NotificationType.running -> taskWorker.notificationProgress\n            else -> progress\n        }\n        val effectiveExpectedFileSize = taskWorker.notificationExpectedFileSize\n        // title and body interpolation"),
    ("            networkSpeed = taskWorker.networkSpeed,\n            timeRemaining = timeRemaining\n        )",
     "            networkSpeed = taskWorker.networkSpeed,\n            timeRemaining = timeRemaining,\n            expectedFileSize = effectiveExpectedFileSize\n        )"),
    ("    private val progressRegEx = Regex(\"\"\"\\{progress\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val networkSpeedRegEx",
     "    private val progressRegEx = Regex(\"\"\"\\{progress\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val downloadedRegEx = Regex(\"\"\"\\{downloaded\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val totalRegEx = Regex(\"\"\"\\{total\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val networkSpeedRegEx"),
    ("        timeRemaining: Long? = null,\n        groupNotification: GroupNotification? = null\n    ): String {",
     "        timeRemaining: Long? = null,\n        expectedFileSize: Long = -1,\n        groupNotification: GroupNotification? = null\n    ): String {"),
    ("        val progressString =\n            if (progress in 0.0..1.0) (progress * 100).roundToInt().toString() + \"%\"\n            else \"\"\n        val output2 = progressRegEx.replace(output, progressString)\n        // download speed",
     "        val progressString =\n            if (progress in 0.0..1.0) (progress * 100).roundToInt().toString() + \"%\"\n            else \"--%\"\n        val output2 = progressRegEx.replace(output, progressString)\n        val downloadedBytes = if (expectedFileSize > 0 && progress in 0.0..1.0)\n            (progress * expectedFileSize).toLong() else -1L\n        fun formatMegabytes(bytes: Long): String = if (bytes < 0) \"-- MB\"\n            else String.format(Locale.US, \"%.1f MB\", bytes / (1024.0 * 1024.0))\n        val output2WithSizes = downloadedRegEx.replace(\n            totalRegEx.replace(output2, formatMegabytes(expectedFileSize)),\n            formatMegabytes(downloadedBytes)\n        )\n        // download speed"),
    ("        val output3 = networkSpeedRegEx.replace(output2, networkSpeedString)",
     "        val output3 = networkSpeedRegEx.replace(output2WithSizes, networkSpeedString)"),
])

print(f"Applied notification byte-count patch to {package.name}")
