from pathlib import Path

cache = Path.home() / ".pub-cache" / "hosted" / "pub.dev"
packages = sorted(cache.glob("background_downloader-9.6.5"))
if not packages:
    raise SystemExit("background_downloader package was not found in pub cache")
package = packages[-1]
root = package / "android" / "src" / "main" / "kotlin" / "com" / "bbflight" / "background_downloader"
if not root.is_dir():
    raise SystemExit(f"Android Kotlin source directory not found: {root}")

def patch(file_name, replacements):
    path = root / file_name
    source = path.read_text()
    for item in replacements:
        old, new = item[0], item[1]
        expected_count = item[2] if len(item) == 3 else 1
        count = source.count(old)
        if count != expected_count:
            raise SystemExit(f"{file_name}: expected {expected_count} patch anchor(s), found {count}: {old[:90]!r}")
        source = source.replace(old, new)
    path.write_text(source)
    print(f"Patched {file_name}")

patch("TaskRunner.kt", [
    ("    var notificationProgress: Double\n    var networkSpeed: Double",
     "    var notificationProgress: Double\n    var notificationExpectedFileSize: Long\n    var notificationDownloadedBytes: Long\n    var networkSpeed: Double"),
    ("        progress: Double = 2.0,\n        timeRemaining: Long = -1000\n    )",
     "        progress: Double = 2.0,\n        timeRemaining: Long = -1000,\n        expectedFileSize: Long = -1,\n        downloadedBytes: Long = -1\n    )"),
    ("            progress, timeRemaining\n        )\n        lastProgressUpdate",
     "            progress, timeRemaining, expectedFileSize, bytesTotal\n        )\n        lastProgressUpdate"),
    ("            BDPlugin.localResumeData[resumeData.task.taskId] = resumeData\n            postOnBackgroundChannel(",
     "            BDPlugin.localResumeData[resumeData.task.taskId] = resumeData\n            // Keep resume data available to native notification actions after process death.\n            storeLocally(\n                BDPlugin.keyResumeDataMap,\n                resumeData.task.taskId,\n                bdJson.encodeToString<ResumeData>(resumeData),\n                prefs\n            )\n            postOnBackgroundChannel("),
])

patch("TaskWorker.kt", [
    ("    override var notificationProgress: Double = 2.0 // indeterminate\n    override var networkSpeed: Double",
     "    override var notificationProgress: Double = 2.0 // indeterminate\n    override var notificationExpectedFileSize: Long = -1\n    override var notificationDownloadedBytes: Long = -1\n    override var networkSpeed: Double"),
    ("        progress: Double,\n        timeRemaining: Long\n    ) {\n        NotificationService.updateNotification(this, status, progress, timeRemaining)",
     "        progress: Double,\n        timeRemaining: Long,\n        expectedFileSize: Long,\n        downloadedBytes: Long\n    ) {\n        NotificationService.updateNotification(this, status, progress, timeRemaining, expectedFileSize, downloadedBytes)"),
])

patch("UIDTJobService.kt", [
    ("        override var notificationProgress: Double = 2.0\n        override var networkSpeed: Double",
     "        override var notificationProgress: Double = 2.0\n        override var notificationExpectedFileSize: Long = -1\n        override var notificationDownloadedBytes: Long = -1\n        override var networkSpeed: Double"),
    ("            progress: Double,\n            timeRemaining: Long\n        ) {\n            NotificationService.updateNotification(this, status, progress, timeRemaining)",
     "            progress: Double,\n            timeRemaining: Long,\n            expectedFileSize: Long,\n            downloadedBytes: Long\n        ) {\n            NotificationService.updateNotification(this, status, progress, timeRemaining, expectedFileSize, downloadedBytes)"),
])

patch("Notifications.kt", [
    ("        progress: Double = 2.0,\n        timeRemaining: Long = -1000\n    ) {\n        val notificationType",
     "        progress: Double = 2.0,\n        timeRemaining: Long = -1000,\n        expectedFileSize: Long = -1,\n        downloadedBytes: Long = -1\n    ) {\n        val notificationType"),
    ("        taskWorker.notificationProgress =\n            if (notificationType == NotificationType.paused) taskWorker.notificationProgress else progress\n        // title and body interpolation",
     "        if (expectedFileSize > 0) taskWorker.notificationExpectedFileSize = expectedFileSize\n        if (downloadedBytes >= 0) taskWorker.notificationDownloadedBytes = downloadedBytes\n        if (taskStatus == TaskStatus.complete && taskWorker.notificationExpectedFileSize > 0) {\n            taskWorker.notificationDownloadedBytes = taskWorker.notificationExpectedFileSize\n        }\n        taskWorker.notificationProgress = when {\n            notificationType == NotificationType.paused -> taskWorker.notificationProgress\n            taskStatus == TaskStatus.complete -> 1.0\n            progress == 2.0 && notificationType != NotificationType.running -> taskWorker.notificationProgress\n            else -> progress\n        }\n        val effectiveExpectedFileSize = taskWorker.notificationExpectedFileSize\n        val effectiveDownloadedBytes = taskWorker.notificationDownloadedBytes\n        // title and body interpolation"),
    ("            networkSpeed = taskWorker.networkSpeed,\n            timeRemaining = timeRemaining\n        )",
     "            networkSpeed = taskWorker.networkSpeed,\n            timeRemaining = timeRemaining,\n            expectedFileSize = effectiveExpectedFileSize,\n            downloadedBytes = effectiveDownloadedBytes\n        )", 2),
    ("    private val progressRegEx = Regex(\"\"\"\\{progress\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val networkSpeedRegEx",
     "    private val progressRegEx = Regex(\"\"\"\\{progress\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val downloadedRegEx = Regex(\"\"\"\\{downloaded\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val totalRegEx = Regex(\"\"\"\\{total\\}\"\"\", RegexOption.IGNORE_CASE)\n    private val networkSpeedRegEx"),
    ("        timeRemaining: Long? = null,\n        groupNotification: GroupNotification? = null\n    ): String {",
     "        timeRemaining: Long? = null,\n        expectedFileSize: Long = -1,\n        downloadedBytes: Long = -1,\n        groupNotification: GroupNotification? = null\n    ): String {"),
    ("        val progressString =\n            if (progress in 0.0..1.0) (progress * 100).roundToInt().toString() + \"%\"\n            else \"\"\n        val output2 = progressRegEx.replace(output, progressString)\n        // download speed",
     "        val progressString =\n            if (progress in 0.0..1.0) (progress * 100).roundToInt().toString() + \"%\"\n            else \"--%\"\n        val output2 = progressRegEx.replace(output, progressString)\n        fun formatBytes(bytes: Long): String = when {\n            bytes < 0 -> \"--\"\n            bytes < 1024 -> \"$bytes B\"\n            bytes < 1024L * 1024L -> String.format(Locale.US, \"%.1f KB\", bytes / 1024.0)\n            bytes < 1024L * 1024L * 1024L -> String.format(Locale.US, \"%.1f MB\", bytes / (1024.0 * 1024.0))\n            else -> String.format(Locale.US, \"%.2f GB\", bytes / (1024.0 * 1024.0 * 1024.0))\n        }\n        val output2WithSizes = downloadedRegEx.replace(\n            totalRegEx.replace(output2, formatBytes(expectedFileSize)),\n            formatBytes(downloadedBytes)\n        )\n        // download speed"),
    ("        val output3 = networkSpeedRegEx.replace(output2, networkSpeedString)",
     "        val output3 = networkSpeedRegEx.replace(output2WithSizes, networkSpeedString)"),

    ("import android.content.Intent\n",
     "import android.content.Intent\nimport androidx.preference.PreferenceManager\n"),
    ("    private suspend fun handleAction(\n",
     """    private fun loadResumeData(context: Context, taskId: String): ResumeData? {
        BDPlugin.localResumeData[taskId]?.let { return it }
        return try {
            val prefs = PreferenceManager.getDefaultSharedPreferences(context)
            val mapJson = prefs.getString(BDPlugin.keyResumeDataMap, "{}") ?: "{}"
            val resumeMap = bdJson.decodeFromString<MutableMap<String, String>>(mapJson)
            val encoded = resumeMap[taskId] ?: return null
            bdJson.decodeFromString<ResumeData>(encoded).also {
                BDPlugin.localResumeData[taskId] = it
            }
        } catch (e: Exception) {
            Log.e(TAG, "Could not restore resume data for taskId $taskId", e)
            null
        }
    }

    private suspend fun handleAction(
"""),
    ("                val resumeData = BDPlugin.localResumeData[taskId]",
     "                val resumeData = loadResumeData(context, taskId)"),
    ("                    } else {\n                        BDPlugin.cancelActiveTaskWithId(\n                            context, taskId, WorkManager.getInstance(context)\n                        )\n                    }",
     "                    } else {\n                        Log.e(TAG, \"Missing notification config for resume action on taskId $taskId\")\n                    }"),
    ("                } else {\n                    BDPlugin.cancelActiveTaskWithId(\n                        context, taskId, WorkManager.getInstance(context)\n                    )\n                }",
     """                } else {
                    // The app process may have been killed before resume data was persisted.
                    // In that case restart the same task from byte zero instead of treating
                    // the Resume action as Cancel.
                    val taskJsonString = bundle.getString(keyTask)
                    val notificationConfigJsonString = bundle.getString(keyNotificationConfig)
                    if (taskJsonString != null && notificationConfigJsonString != null) {
                        try {
                            val task = bdJson.decodeFromString<Task>(taskJsonString)
                            if (!BDPlugin.doEnqueue(context, task, notificationConfigJsonString, null)) {
                                Log.e(TAG, "Could not restart taskId $taskId from notification")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error restarting taskId $taskId from notification: ${e.message}", e)
                        }
                    } else {
                        Log.e(TAG, "Missing task or notification config for resume action on taskId $taskId")
                    }
                }""")

])

print(f"Applied notification byte-count patch to {package.name}")
