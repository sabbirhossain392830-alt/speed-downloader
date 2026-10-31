import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const SpeedDownloaderApp());
}

class SpeedDownloaderApp extends StatelessWidget {
  const SpeedDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speed Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DownloadHome(),
    );
  }
}

class DownloadHome extends StatefulWidget {
  const DownloadHome({super.key});

  @override
  State<DownloadHome> createState() => _DownloadHomeState();
}

class _DownloadHomeState extends State<DownloadHome> {
  final TextEditingController urlController = TextEditingController();
  double progress = 0;
  bool downloading = false;
  String status = 'Download a file using a direct link';
  String? savedPath;

  Future<void> startDownload() async {
    final url = urlController.text.trim();

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => status = 'Please enter a valid HTTP/HTTPS link');
      return;
    }

    setState(() {
      downloading = true;
      progress = 0;
      savedPath = null;
      status = 'Connecting...';
    });

    try {
      final uri = Uri.parse(url);
      String fileName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'downloaded_file';

      if (fileName.isEmpty) fileName = 'downloaded_file';

      final directory = await getApplicationDocumentsDirectory();
      final saveFile = '${directory.path}/$fileName';

      await Dio().download(
        url,
        saveFile,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              progress = received / total;
              status =
                  'Downloading ${(progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        downloading = false;
        progress = 1;
        savedPath = saveFile;
        status = 'Download completed!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        downloading = false;
        status = 'Download failed: $e';
      });
    }
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speed Downloader'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.download_rounded, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Fast & Simple Downloader',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Paste direct download URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: downloading ? null : startDownload,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
            const SizedBox(height: 25),
            LinearProgressIndicator(value: downloading ? progress : null),
            const SizedBox(height: 12),
            Text(status, textAlign: TextAlign.center),
            if (savedPath != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Saved inside the app storage:',
                textAlign: TextAlign.center,
              ),
              SelectableText(savedPath!),
            ],
          ],
        ),
      ),
    );
  }
}
