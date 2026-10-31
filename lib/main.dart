import 'package:flutter/material.dart';

void main() {
  runApp(const SpeedDownloader());
}

class SpeedDownloader extends StatelessWidget {
  const SpeedDownloader({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speed Downloader',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF101827),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ Speed Downloader'),
        centerTitle: true,
        backgroundColor: const Color(0xFF172554),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 35),
            const Icon(Icons.download_for_offline,
                size: 90, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text(
              'Fast File Downloader',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Paste direct download URL',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a download URL'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Download engine coming next!'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('DOWNLOAD'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(17),
              ),
            ),
            const SizedBox(height: 25),
            const Text('Features'),
            const ListTile(
              leading: Icon(Icons.speed, color: Colors.green),
              title: Text('Fast Download'),
            ),
            const ListTile(
              leading: Icon(Icons.pause_circle, color: Colors.orange),
              title: Text('Pause & Resume - Coming soon'),
            ),
            const ListTile(
              leading: Icon(Icons.folder, color: Colors.blue),
              title: Text('Download Manager - Coming soon'),
            ),
          ],
        ),
      ),
    );
  }
}
