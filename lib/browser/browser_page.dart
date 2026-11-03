import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../shared/widgets/drox_widgets.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.onDownload, required this.isDark, required this.isBangla, required this.onThemeTap, required this.onReturn, required this.onSettings});
  final ValueChanged<String> onDownload;
  final bool isDark, isBangla;
  final VoidCallback onThemeTap, onReturn, onSettings;
  @override
  State<BrowserPage> createState() => BrowserPageState();
}
class _DroxTab {
  _DroxTab(this.controller, this.url);
  final WebViewController controller;
  String url;
  String title = 'Google';
  bool loading = false, refreshing = false, back = false, forward = false;
  final List<String> trail = <String>[];
  int trailIndex = -1;
  int pendingTraversal = 0;
}
class BrowserPageState extends State<BrowserPage> {
  final address = TextEditingController();
  final homeSearch = TextEditingController();
  final tabs = <_DroxTab>[];
  final history = <Map<String,String>>[];
  final shortcuts = <Map<String,String>>[];
  int active = 0;
  bool showHistory = false, showTrail = false, showTabOverview = false, adBlockEnabled = true, desktopMode = false;
  bool historySelectionMode = false;
  final Set<int> selectedHistory = <int>{};
  _DroxTab? get tab => tabs.isEmpty ? null : tabs[active];
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadShortcuts();
    _loadBrowserSettings();
    _newTab();
  }

  Future<void> _loadBrowserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedAdBlock = prefs.getBool('drox_browser_adblock') ?? true;
    final savedDesktop = prefs.getBool('drox_browser_desktop_mode') ?? false;
    setState(() {
      adBlockEnabled = savedAdBlock;
      desktopMode = savedDesktop;
    });
    if (savedDesktop && tab != null) {
      await tab!.controller.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      await tab!.controller.reload();
    }
  }
  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString('drox_browser_history');
      if (raw != null) history.addAll((jsonDecode(raw) as List).cast<Map<String,dynamic>>().map((e) => <String,String>{'title': (e['title'] ?? '').toString(), 'url': (e['url'] ?? '').toString(), 'visitedAt': (e['visitedAt'] ?? '').toString()}));
      if (mounted) setState(() {});
    } catch (_) {}
  }
  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('drox_browser_history', jsonEncode(history.take(100).toList()));
  }

  Future<void> _loadShortcuts() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString('drox_browser_shortcuts');
      if (raw != null) {
        shortcuts
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => <String, String>{
            'title': (e['title'] ?? '').toString(),
            'url': (e['url'] ?? '').toString(),
          }));
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveShortcuts() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('drox_browser_shortcuts', jsonEncode(shortcuts));
  }
  bool _isKnownAdUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    const blocked = ['doubleclick.net','googlesyndication.com','googleadservices.com','adservice.google.com','googletagmanager.com','googletagservices.com','adnxs.com','taboola.com','outbrain.com','adform.net','adroll.com','criteo.com','pubmatic.com','openx.net','rubiconproject.com','scorecardresearch.com','quantserve.com','amazon-adsystem.com','advertising.com','moatads.com','serving-sys.com','casalemedia.com','smartadserver.com','sharethrough.com','bidswitch.net','yieldmo.com','zedo.com','popads.net','propellerads.com'];
    return blocked.any((domain) => host == domain || host.endsWith('.' + domain));
  }
  Widget _siteIcon(String url, {double size = 34}) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return Container(width: size, height: size, decoration: const BoxDecoration(color: Color(0xFFE8F0FE), shape: BoxShape.circle), child: Icon(Icons.language_rounded, color: const Color(0xFF4285F4), size: size * .58));
    final iconUrl = 'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(host)}&sz=64';
    return ClipRRect(borderRadius: BorderRadius.circular(size), child: Image.network(iconUrl, width: size, height: size, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(width: size, height: size, decoration: const BoxDecoration(color: Color(0xFFE8F0FE), shape: BoxShape.circle), child: Icon(Icons.language_rounded, color: const Color(0xFF4285F4), size: size * .58))));
  }

  Future<void> _deleteSelectedHistory() async {
    if (selectedHistory.isEmpty) return;
    final indices = selectedHistory.toList()..sort((a, b) => b.compareTo(a));
    setState(() { for (final index in indices) { if (index >= 0 && index < history.length) history.removeAt(index); } selectedHistory.clear(); historySelectionMode = false; });
    await _saveHistory();
  }

  static const String _droxAdBlockScript = r'''(function(){
    if(window.__droxAdProtection)return;window.__droxAdProtection=true;
    var hosts=['doubleclick.net','googlesyndication.com','googleadservices.com','googletagmanager.com','googletagservices.com','adnxs.com','taboola.com','outbrain.com','adform.net','adroll.com','criteo.com','pubmatic.com','openx.net','rubiconproject.com','scorecardresearch.com','quantserve.com','amazon-adsystem.com','advertising.com','moatads.com','serving-sys.com','casalemedia.com','smartadserver.com','sharethrough.com','bidswitch.net','yieldmo.com','zedo.com','popads.net','propellerads.com'];
    function blocked(raw){try{var h=new URL(raw,location.href).hostname.toLowerCase();return hosts.some(function(d){return h===d||h.endsWith('.'+d)})}catch(_){return false}}
    var originalFetch=window.fetch;if(originalFetch)window.fetch=function(input,init){var u=typeof input==='string'?input:(input&&input.url)||'';if(blocked(u))return Promise.resolve(new Response('',{status:204,statusText:'Blocked by DROX'}));return originalFetch.apply(this,arguments)};
    var originalOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(method,url){this.__droxBlocked=blocked(url);return originalOpen.apply(this,arguments)};
    var originalSend=XMLHttpRequest.prototype.send;XMLHttpRequest.prototype.send=function(){if(this.__droxBlocked){try{this.abort()}catch(_){}return}return originalSend.apply(this,arguments)};
    var selectors=['iframe[src*="doubleclick"]','iframe[src*="googlesyndication"]','iframe[src*="adservice"]','iframe[src*="taboola"]','iframe[src*="outbrain"]','[id^="google_ads"]','[id*="_ad_container"]','[class~="ad-banner"]','[class*="ad-slot"]','[class*="adsbygoogle"]','[data-ad-client]','[data-ad-slot]'];
    function clean(){document.querySelectorAll(selectors.join(',')).forEach(function(el){if(el&&el.parentNode)el.parentNode.removeChild(el)});document.querySelectorAll('iframe[src],script[src]').forEach(function(el){if(blocked(el.src))el.remove()})}
    clean();new MutationObserver(clean).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
  })();''';

  bool _downloadable(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(pdf|epub|zip|rar|7z|tar|gz|bz2|xz|iso|dmg|apk|aab|exe|msi|deb|rpm|mp4|m4v|mkv|mov|avi|webm|ogv|3gp|mpeg|mpg|mp3|m4a|aac|wav|ogg|oga|opus|flac|m3u8|mpd|jpg|jpeg|png|gif|webp|bmp|svg|tif|tiff|txt|csv|json|xml|html|docx?|xlsx?|pptx?|odt|ods|odp|srt|vtt|ass|ssa|ttf|otf|woff2?)$').hasMatch(path);
  }
  Future<void> _newTab([String url = '']) async {
    final t = _DroxTab(WebViewController(), url);
    tabs.add(t); active = tabs.length - 1; showHistory = false; showTrail = false; showTabOverview = false; address.text = url;
    final ctrl = t.controller;
    await ctrl.setJavaScriptMode(JavaScriptMode.unrestricted);
    await ctrl.addJavaScriptChannel('DroxDownload', onMessageReceived: (m) => _downloadPrompt(m.message));
    await ctrl.addJavaScriptChannel('DroxRefresh', onMessageReceived: (_) async {
      if (t.refreshing) return;
      t.refreshing = true;
      t.loading = true;
      if (mounted) setState(() {});
      await ctrl.reload();
    });
    await ctrl.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (r) {
        if (_downloadable(r.url)) { _downloadPrompt(r.url); return NavigationDecision.prevent; }
        if (adBlockEnabled && _isKnownAdUrl(r.url)) return NavigationDecision.prevent;
        return NavigationDecision.navigate;
      },
      onPageStarted: (u) {
        t.url = u;
        t.loading = true;
        if (t.pendingTraversal < 0) {
          t.trailIndex = (t.trailIndex - 1).clamp(0, t.trail.length - 1).toInt();
          t.pendingTraversal++;
        } else if (t.pendingTraversal > 0) {
          t.trailIndex = (t.trailIndex + 1).clamp(0, t.trail.length - 1).toInt();
          t.pendingTraversal--;
        } else {
          if (t.trailIndex >= 0 && t.trailIndex < t.trail.length - 1) {
            t.trail.removeRange(t.trailIndex + 1, t.trail.length);
          }
          if (t.trail.isEmpty || t.trail.last != u) {
            t.trail.add(u);
            t.trailIndex = t.trail.length - 1;
          }
        }
        if (mounted) setState(() {
          if (tab == t) address.text = u;
        });
      },
      onPageFinished: (u) async {
        t.url = u;
        await ctrl.runJavaScript(r'''(function(){
          if(window.__droxMediaDetector)return;window.__droxMediaDetector=true;
          var seen={};
          var exts=/\.(mp4|m4v|mkv|avi|webm|mov|ogv|3gp|mpeg|mpg|mp3|m4a|aac|wav|ogg|oga|opus|flac|m3u8|mpd|pdf|epub|zip|rar|7z|tar|gz|bz2|xz|iso|dmg|apk|aab|exe|msi|deb|rpm|jpg|jpeg|png|webp|gif|bmp|svg|tif|tiff|txt|csv|json|xml|docx?|xlsx?|pptx?|odt|ods|odp|srt|vtt|ass|ssa|ttf|otf|woff2?)(?:$|[?#])/i;
          var mediaTypes=/^(video\/|audio\/|application\/(vnd\.apple\.mpegurl|x-mpegurl|dash\+xml))/i;
          function valid(raw){try{var u=new URL(raw,location.href);return /^https?:$/.test(u.protocol)?u.href:null}catch(_){return null}}
          function send(raw){var u=valid(raw);if(!u||seen[u])return;seen[u]=1;DroxDownload.postMessage(u)}
          function mediaSources(v){var list=[v.currentSrc,v.src];v.querySelectorAll('source[src]').forEach(function(s){list.push(s.src)});list.forEach(function(u){if(u)send(u)})}
          function scan(){document.querySelectorAll('video,audio').forEach(function(v){
            if(!v.__droxBound){v.__droxBound=true;
              v.addEventListener('play',function(){mediaSources(v)});
              v.addEventListener('loadedmetadata',function(){mediaSources(v)});
              v.addEventListener('canplay',function(){mediaSources(v)});
              v.addEventListener('loadstart',function(){mediaSources(v)});
              v.addEventListener('emptied',function(){mediaSources(v)});
            }
            mediaSources(v);
          })}
          function scanResources(){try{performance.getEntriesByType('resource').forEach(function(e){if(exts.test(e.name))send(e.name)})}catch(_){}}
          function scanFrames(){document.querySelectorAll('iframe').forEach(function(f){try{if(f.contentDocument){f.contentDocument.querySelectorAll('video,audio').forEach(function(v){mediaSources(v)})}}catch(_){}})}
          if(window.fetch){var originalFetch=window.fetch;window.fetch=function(){var p=originalFetch.apply(this,arguments);try{var u=typeof arguments[0]==='string'?arguments[0]:arguments[0].url; p.then(function(r){var ct=r.headers.get('content-type')||'';var target=r.url||u;if(mediaTypes.test(ct)||exts.test(target||''))send(target)})}catch(_){}return p}}
          if(window.XMLHttpRequest){var originalOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){this.__droxUrl=u;return originalOpen.apply(this,arguments)};var originalSend=XMLHttpRequest.prototype.send;XMLHttpRequest.prototype.send=function(){this.addEventListener('load',function(){var ct=this.getResponseHeader('content-type')||'';if(mediaTypes.test(ct)||exts.test(this.__droxUrl||''))send(this.responseURL||this.__droxUrl)});return originalSend.apply(this,arguments)}}
          var droxTouchStartY=0;var droxAtTop=false;var droxRefreshing=false;
          function droxPageAtTop(){var root=document.scrollingElement||document.documentElement;return (window.scrollY||root.scrollTop||(document.body&&document.body.scrollTop)||0)<=0}
          window.addEventListener('touchstart',function(e){if(e.touches&&e.touches.length===1){droxTouchStartY=e.touches[0].clientY;droxAtTop=droxPageAtTop();droxRefreshing=false;}}, {passive:true,capture:true});
          window.addEventListener('touchend',function(e){if(!droxAtTop||droxRefreshing||!e.changedTouches||!e.changedTouches.length)return;var delta=e.changedTouches[0].clientY-droxTouchStartY;if(delta>85&&droxPageAtTop()){droxRefreshing=true;try{DroxRefresh.postMessage('refresh')}catch(_){}}droxAtTop=false;}, {passive:true,capture:true});
          window.addEventListener('touchcancel',function(){droxAtTop=false;droxRefreshing=false;}, {passive:true,capture:true});
          scan();new MutationObserver(function(){scan();scanResources();scanFrames()}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
          setInterval(function(){scan();scanResources();scanFrames()},2500);
          document.addEventListener('play',function(e){if(e.target&&(e.target.tagName==='VIDEO'||e.target.tagName==='AUDIO'))mediaSources(e.target)},true);
          document.addEventListener('click',function(e){var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;if(!a)return;try{var u=new URL(a.href,location.href);if(a.hasAttribute('download')||exts.test(u.pathname)){e.preventDefault();e.stopImmediatePropagation();send(u.href)}}catch(_){}},true);
        })();''');
        if (adBlockEnabled) await ctrl.runJavaScript(_droxAdBlockScript);
        final title = await ctrl.getTitle();
        t.title = title == null || title.isEmpty ? (Uri.tryParse(u)?.host ?? 'Website') : title;
        if (t.trailIndex < 0 || t.trailIndex >= t.trail.length || t.trail[t.trailIndex] != u) {
          final visitedTrailIndex = t.trail.lastIndexWhere((entry) => entry == u);
          if (visitedTrailIndex >= 0) t.trailIndex = visitedTrailIndex;
        }
        t.pendingTraversal = 0;
        t.loading = false;
        t.refreshing = false;
        t.back = await ctrl.canGoBack();
        t.forward = await ctrl.canGoForward();
        if (!mounted) return;
        setState(() { if (tab == t) address.text = u; });
        if (u.startsWith('http')) {
          history.insert(0, {'title': t.title, 'url': u, 'visitedAt': DateTime.now().toIso8601String()});
          if (history.length > 500) history.removeLast();
          if (history.length > 100) history.removeLast();
          _saveHistory();
        }
      },
      onWebResourceError: (_) { t.loading = false; t.refreshing = false; if (mounted) setState(() {}); },
    ));
    if (mounted) setState(() {});
    if (url.isNotEmpty) await ctrl.loadRequest(Uri.parse(url));
  }
  final Set<String> _promptedDownloadUrls = <String>{};
  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return widget.isBangla ? 'অজানা' : 'Unknown';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _downloadPrompt(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return;
    if (_promptedDownloadUrls.contains(url)) return;
    _promptedDownloadUrls.add(url);
    if (!mounted) { _promptedDownloadUrls.remove(url); return; }
    final wantsDownload = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.video_file_rounded, size: 42),
        title: const Text('ভিডিওটি ডাউনলোড করবেন?'),
        content: Text('এই ওয়েবসাইটে একটি ভিডিও পাওয়া গেছে।\n\n${uri.host}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('এখন নয়')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.download_rounded), label: const Text('হ্যাঁ, ডাউনলোড')),
        ],
      ),
    );
    if (wantsDownload != true || !mounted) {
      _promptedDownloadUrls.remove(url);
      return;
    }
    var finalUrl = url;
    var name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'media_file';
    try { name = Uri.decodeComponent(name); } catch (_) {}
    if (name.isEmpty || !name.contains('.')) name = 'media_file';
    var size = 'অজানা';
    var type = 'অজানা';
    var statusNote = '';
    try {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        validateStatus: (s) => s != null && s < 500,
      ));
      final response = await dio.head(url);
      final responseType = (response.headers.value('content-type') ?? '').toLowerCase();
      if ((response.statusCode ?? 200) >= 400) {
        statusNote = 'সার্ভার লিংকটি অনুমোদন করেনি (HTTP ${response.statusCode})';
      } else if (responseType.contains('text/html')) {
        statusNote = 'এটি সরাসরি মিডিয়া ফাইল নয়—সার্ভার HTML/Cloudflare পেজ পাঠাচ্ছে';
      } else {
        if (response.realUri.toString().startsWith('http')) finalUrl = response.realUri.toString();
        final length = int.tryParse(response.headers.value('content-length') ?? '');
        size = _formatFileSize(length);
        type = responseType.split(';').first.isEmpty ? 'অজানা' : responseType.split(';').first;
      }
      final disposition = response.headers.value('content-disposition') ?? '';
      final match = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(disposition);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        try { name = Uri.decodeComponent(match.group(1)!.trim().replaceAll('"', '').replaceAll("'", '')); } catch (_) { name = match.group(1)!.trim().replaceAll('"', '').replaceAll("'", ''); }
      }
      if (response.statusCode != null && response.statusCode! >= 400) statusNote = 'সার্ভার তথ্য যাচাই করতে দেয়নি';
    } catch (_) {
      statusNote = 'সার্ভার থেকে ফাইলের তথ্য পাওয়া যায়নি';
    }
    name = name.replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_');
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        final dot = name.lastIndexOf('.');
        final baseName = dot > 0 ? name.substring(0, dot) : name;
        final extension = dot > 0 ? name.substring(dot + 1) : (type.contains('/') ? type.split('/').last : 'file');
        return AlertDialog(
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? colors.surface : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 14, 12),
          title: Row(children: [
            const Expanded(child: Text('Download file!', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
            Icon(Icons.dns_outlined, color: colors.onSurfaceVariant, size: 30),
          ]),
          content: SingleChildScrollView(
            child: SizedBox(width: 520, child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('Link (Resume: N/A)', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14))),
                  IconButton(tooltip: 'Copy link', visualDensity: VisualDensity.compact,
                    onPressed: () => Clipboard.setData(ClipboardData(text: finalUrl)),
                    icon: const Icon(Icons.content_copy_rounded)),
                  IconButton(tooltip: 'Open link in browser', visualDensity: VisualDensity.compact,
                    onPressed: () async { await tab?.controller.loadRequest(Uri.parse(finalUrl)); Navigator.pop(ctx, false); },
                    icon: const Icon(Icons.play_circle_outline_rounded)),
                  Icon(Icons.remove_red_eye_outlined, color: colors.onSurfaceVariant),
                ]),
                const SizedBox(height: 2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 8),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFBDBDBD), style: BorderStyle.solid))),
                  child: Text(finalUrl, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
                ),
                const SizedBox(height: 14),
                Text('Save as:', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14)),
                const SizedBox(height: 5),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Text(baseName, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.35))),
                  const SizedBox(width: 12),
                  Text(extension, style: const TextStyle(color: Color(0xFFFF7043), fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
                const Divider(height: 18),
                Text(size, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14)),
                if (type != 'অজানা') ...[
                  const SizedBox(height: 5),
                  Text(type, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                ],
                if (statusNote.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(width: double.infinity, padding: const EdgeInsets.all(10),
                    color: colors.errorContainer,
                    child: Text(statusNote, style: TextStyle(color: colors.onErrorContainer, fontSize: 12))),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.folder_open_outlined, color: colors.onSurfaceVariant, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text('/storage/emulated/0/Download/DROX',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
                  Icon(Icons.folder_outlined, color: colors.onSurfaceVariant),
                ]),
                const Divider(height: 16),
                Text('DROX Download Manager', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 3),
                Text('ফাইলটি ডাউনলোড কিউতে যোগ হবে।', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL', style: TextStyle(color: Color(0xFF8054C7)))),
            TextButton(
              onPressed: statusNote.isEmpty ? () => Navigator.pop(ctx, true) : null,
              child: const Text('START', style: TextStyle(color: Color(0xFF8054C7), fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
    _promptedDownloadUrls.remove(url);
    if (approved == true && mounted) widget.onDownload(finalUrl);
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 58, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );
  String _normaliseUrl(String value) {
    var v = value.trim();
    if (v.isEmpty) return '';
    if (!v.contains('://')) {
      v = (v.contains(' ') || !v.contains('.'))
          ? 'https://www.google.com/search?q=' + Uri.encodeQueryComponent(v)
          : 'https://' + v;
    }
    final uri = Uri.tryParse(v);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? uri.toString() : '';
  }

  void _loadUrl(String value) {
    final url = _normaliseUrl(value);
    if (url.isEmpty || tab == null) return;
    setState(() {
      showHistory = false;
      showTrail = false;
      address.text = url;
      tab!.url = url;
    });
    tab!.controller.loadRequest(Uri.parse(url));
  }

  void go() => _loadUrl(address.text);

  void _searchHome(String value) {
    homeSearch.text = value;
    _loadUrl(value);
  }

  Future<void> _addShortcut() async {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add shortcut'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.bookmark_add_outlined))),
          const SizedBox(height: 10),
          TextField(controller: urlController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Website URL', prefixIcon: Icon(Icons.link_rounded))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final url = _normaliseUrl(urlController.text);
            if (url.isNotEmpty) Navigator.pop(ctx, {'title': titleController.text.trim().isEmpty ? (Uri.parse(url).host) : titleController.text.trim(), 'url': url});
          }, child: const Text('Save')),
        ],
      ),
    );
    titleController.dispose();
    urlController.dispose();
    if (result != null) {
      setState(() => shortcuts.add(result));
      await _saveShortcuts();
    }
  }

  Future<void> _removeShortcut(Map<String, String> item) async {
    setState(() => shortcuts.remove(item));
    await _saveShortcuts();
  }

  Future<void> _goBack() async {
    final current = tab;
    if (current == null) return;
    if (await current.controller.canGoBack()) {
      current.pendingTraversal--;
      await current.controller.goBack();
      if (mounted) setState(() {});
      return;
    }
    if (current.url.isNotEmpty && mounted) {
      setState(() {
        current.url = '';
        current.title = 'Google';
        current.loading = false;
        current.refreshing = false;
        current.back = false;
        current.forward = false;
        address.clear();
        homeSearch.clear();
        showHistory = false;
        showTrail = false;
        showTabOverview = false;
        historySelectionMode = false;
        selectedHistory.clear();
      });
    }
  }

  Future<void> _goForward() async {
    final current = tab;
    if (current == null || !await current.controller.canGoForward()) return;
    current.pendingTraversal++;
    await current.controller.goForward();
    if (mounted) setState(() {});
  }

  void _removeTrailItem(int index) {
    final current = tab;
    if (current == null || index < 0 || index >= current.trail.length) return;
    setState(() {
      current.trail.removeAt(index);
      if (current.trail.isEmpty) {
        current.trailIndex = -1;
      } else if (index < current.trailIndex) {
        current.trailIndex--;
      } else if (index == current.trailIndex) {
        current.trailIndex = current.trailIndex.clamp(0, current.trail.length - 1).toInt();
      }
    });
  }

  Future<void> _jumpToTrail(int index) async {
    final current = tab;
    if (current == null || index < 0 || index >= current.trail.length) return;
    final distance = index - current.trailIndex;
    if (distance < 0) {
      for (var i = 0; i < -distance; i++) {
        if (!await current.controller.canGoBack()) break;
        current.pendingTraversal--;
        await current.controller.goBack();
      }
    } else if (distance > 0) {
      for (var i = 0; i < distance; i++) {
        if (!await current.controller.canGoForward()) break;
        current.pendingTraversal++;
        await current.controller.goForward();
      }
    }
    if (mounted) setState(() => showTrail = false);
  }

  Widget _buildStartPage() {
    final cs = Theme.of(context).colorScheme;
    const googleColors = [Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFEA4335)];
    const letters = ['G', 'o', 'o', 'g', 'l', 'e'];
    final tile = widget.isDark ? const Color(0xFF303134) : Colors.white;
    return RefreshIndicator(
      color: const Color(0xFF4285F4),
      onRefresh: () async {
        final current = tab;
        if (current != null && current.url.isNotEmpty) {
          await current.controller.reload();
        } else if (mounted) {
          setState(() {});
        }
      },
      child: ColoredBox(
      color: widget.isDark ? const Color(0xFF202124) : const Color(0xFFFFFFFF),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const SizedBox(height: 54),
          Row(mainAxisSize: MainAxisSize.min, children: List.generate(letters.length, (i) => Text(
            letters[i], style: TextStyle(fontSize: 43, fontWeight: FontWeight.w600, color: googleColors[i], letterSpacing: -2),
          ))),
          const SizedBox(height: 30),
          Material(
            color: tile,
            elevation: widget.isDark ? 0 : 1,
            borderRadius: BorderRadius.circular(30),
            child: TextField(
              controller: homeSearch,
              textInputAction: TextInputAction.search,
              onSubmitted: _searchHome,
              decoration: InputDecoration(
                hintText: 'Search or type a URL',
                hintStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF5F6368)),
                suffixIcon: IconButton(tooltip: 'Search', onPressed: () => _searchHome(homeSearch.text), icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF4285F4))),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ),
          const SizedBox(height: 34),
          Row(children: [
            Text('Shortcuts', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addShortcut,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add shortcut'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF4285F4)),
            ),
          ]),
          const SizedBox(height: 12),
          if (shortcuts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(children: [
                Icon(Icons.add_circle_outline_rounded, size: 32, color: cs.onSurfaceVariant),
                const SizedBox(height: 8),
                Text('Add your favourite websites', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ]),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shortcuts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, mainAxisSpacing: 14, crossAxisSpacing: 8, childAspectRatio: .82,
              ),
              itemBuilder: (_, i) {
                final item = shortcuts[i];
                final host = Uri.tryParse(item['url'] ?? '')?.host ?? '';
                return GestureDetector(
                  onLongPress: () => _removeShortcut(item),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _loadUrl(item['url'] ?? ''),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _siteIcon(item['url'] ?? '', size: 42),
                      const SizedBox(height: 7),
                      Text(item['title'] ?? host, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.onSurface)),
                    ]),
                  ),
                );
              },
            ),
          const SizedBox(height: 34),
          Text('Discover the web', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ]),
        ),
      ),
      ),
    ));
  }

  String _formatHistoryTime(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    final h = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  $h:$minute $ampm';
  }

  Widget _buildHistoryPage() {
    final cs = Theme.of(context).colorScheme;
    final allSelected = history.isNotEmpty && selectedHistory.length == history.length;
    return Container(
      color: widget.isDark ? const Color(0xFF202124) : const Color(0xFFF1F3F4),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 12, 10, 10), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(historySelectionMode ? '${selectedHistory.length} selected' : '${history.length} visited pages', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          if (history.isNotEmpty && historySelectionMode) ...[
            IconButton(tooltip: allSelected ? 'Deselect all' : 'Select all', onPressed: () => setState(() { if (allSelected) selectedHistory.clear(); else selectedHistory.addAll(List<int>.generate(history.length, (i) => i)); }), icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded)),
            IconButton(tooltip: 'Delete selected', onPressed: selectedHistory.isEmpty ? null : _deleteSelectedHistory, icon: const Icon(Icons.delete_outline_rounded)),
          ] else if (history.isNotEmpty) ...[
            IconButton(tooltip: 'Select pages', onPressed: () => setState(() { historySelectionMode = true; selectedHistory.clear(); }), icon: const Icon(Icons.checklist_rounded)),
            IconButton(tooltip: 'Delete all history', onPressed: () async {
              final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                title: const Text('Delete all history?'), content: const Text('This will remove all saved browsing history.'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
              if (ok == true) { history.clear(); selectedHistory.clear(); historySelectionMode = false; await _saveHistory(); if (mounted) setState(() {}); }
            }, icon: const Icon(Icons.delete_sweep_outlined)),
          ],
          IconButton(tooltip: 'Close history', onPressed: () => setState(() { showHistory = false; historySelectionMode = false; selectedHistory.clear(); }), icon: const Icon(Icons.close_rounded)),
        ])),
        if (historySelectionMode && history.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [
          Text('Tap pages to select', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)), const Spacer(),
          TextButton(onPressed: () => setState(() { historySelectionMode = false; selectedHistory.clear(); }), child: const Text('Cancel selection')),
        ])),
        Expanded(child: history.isEmpty ? Center(child: Text('No browsing history', style: TextStyle(color: cs.onSurfaceVariant))) :
          ListView.builder(padding: const EdgeInsets.fromLTRB(12, 4, 12, 18), itemCount: history.length, itemBuilder: (_, i) {
            final item = history[i]; final selected = selectedHistory.contains(i);
            return Card(elevation: 0, color: selected ? cs.primaryContainer.withValues(alpha: .55) : (widget.isDark ? const Color(0xFF303134) : Colors.white),
              margin: const EdgeInsets.only(bottom: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: Row(mainAxisSize: MainAxisSize.min, children: [
                  _siteIcon(item['url'] ?? '', size: 34),
                  if (historySelectionMode) ...[
                    const SizedBox(width: 6),
                    Checkbox(value: selected, visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() {
                        if (v == true) selectedHistory.add(i);
                        else selectedHistory.remove(i);
                      })),
                  ],
                ]),
                title: Text(item['title']?.isNotEmpty == true ? item['title']! : (Uri.tryParse(item['url'] ?? '')?.host ?? 'Website'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${item['url'] ?? ''}${(item['visitedAt'] ?? '').isNotEmpty ? '\\n${_formatHistoryTime(item['visitedAt']!)}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () { if (historySelectionMode) setState(() { if (selected) selectedHistory.remove(i); else selectedHistory.add(i); }); else _loadUrl(item['url'] ?? ''); },
                trailing: historySelectionMode ? null : IconButton(tooltip: 'Delete', icon: const Icon(Icons.close_rounded), onPressed: () async { setState(() => history.removeAt(i)); await _saveHistory(); }),
              ));
          })),
      ]),
    );
  }

  Widget _buildTrailPanel() {
    final cs = Theme.of(context).colorScheme;
    final current = tab;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: showTrail ? 0 : -MediaQuery.of(context).size.width * .82,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * .82,
      child: Material(
        elevation: 14,
        color: cs.surface,
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(children: [
                const Icon(Icons.route_rounded),
                const SizedBox(width: 10),
                const Expanded(child: Text('Smart Navigation Trail', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => setState(() => showTrail = false), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: current == null || current.trail.isEmpty
                ? Center(child: Text('Your visited pages will appear here', style: TextStyle(color: cs.onSurfaceVariant)))
                : ListView.builder(
                    itemCount: current.trail.length,
                    itemBuilder: (_, i) {
                      final url = current.trail[i];
                      final host = Uri.tryParse(url)?.host ?? url;
                      final selected = i == current.trailIndex;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? (widget.isDark ? const Color(0xFF203653) : const Color(0xFFE8F1FF))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: selected
                              ? Border.all(color: const Color(0xFF8AB4F8), width: 1.2)
                              : null,
                        ),
                        child: ListTile(
                          leading: _siteIcon(url, size: 34),
                          title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                              color: selected ? (widget.isDark ? const Color(0xFFD6E6FF) : const Color(0xFF174EA6)) : cs.onSurface)),
                          subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: selected ? (widget.isDark ? const Color(0xFFB6D0F5) : const Color(0xFF3C69A8)) : cs.onSurfaceVariant)),
                          trailing: IconButton(tooltip: 'Remove from trail', visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close_rounded, size: 19, color: selected ? const Color(0xFF4285F4) : cs.onSurfaceVariant),
                            onPressed: () => _removeTrailItem(i)),
                          onTap: () => _jumpToTrail(i),
                        ),
                      );
                    },
                  ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('This list follows the active tab back and forward navigation.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
  Future<bool> handleSystemBack() async {
    if (showTrail) { setState(() => showTrail = false); return true; }
    if (showHistory) {
      setState(() { showHistory = false; historySelectionMode = false; selectedHistory.clear(); });
      return true;
    }
    if (showTabOverview) { setState(() => showTabOverview = false); return true; }
    final current = tab;
    if (current == null) return false;
    if (await current.controller.canGoBack()) {
      await _goBack();
      return true;
    }
    if (current.url.isNotEmpty) {
      await _goBack();
      return true;
    }
    return false;
  }
  void _select(int i) { setState(() { active = i; address.text = tab?.url ?? ''; showHistory = false; showTrail = false; showTabOverview = false; }); }
  void _close(int i) {
    if (tabs.length == 1) { setState(() { tabs.first.url = ''; tabs.first.title = 'Google'; tabs.first.back = false; tabs.first.forward = false; address.clear(); }); return; }
    setState(() { tabs.removeAt(i); if (active >= tabs.length) active = tabs.length - 1; else if (i < active) active--; address.text = tab?.url ?? ''; });
  }
  void _showTabs() {
    setState(() {
      showTabOverview = true;
      showHistory = false;
      showTrail = false;
    });
  }

  Widget _buildTabOverview() {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Row(children: [
              const Expanded(child: Text('Tabs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              Text('${tabs.length} open', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Close tab overview', onPressed: () => setState(() => showTabOverview = false), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .88,
            ),
            itemCount: tabs.length,
            itemBuilder: (_, i) {
              final item = tabs[i];
              final selected = i == active;
              return Material(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _select(i),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 5, 4, 2),
                        child: Row(children: [
                          Icon(Icons.language_rounded, size: 17, color: cs.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Close tab',
                            onPressed: () => _close(i),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ]),
                      ),
                      Expanded(child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(item.url.isEmpty ? Icons.home_rounded : Icons.public_rounded, color: cs.primary, size: 24),
                          const SizedBox(height: 8),
                          Text(item.url.isEmpty ? 'Google Start Page' : item.url, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                        ]),
                      )),
                    ]),
                  ),
                ),
              );
            },
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: () => _newTab(), icon: const Icon(Icons.add_rounded), label: const Text('New Tab')),
            ),
          ),
        ]),
      ),
    );
  }
  Future<void> _action(String v) async {
    switch (v) {
      case 'new': _newTab(); break;
      case 'adblock':
        setState(() => adBlockEnabled = !adBlockEnabled);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('drox_browser_adblock', adBlockEnabled);
        if (tab?.url.isNotEmpty == true) await tab!.controller.reload();
        break;
      case 'refresh': tab?.controller.reload(); break;
      case 'history': setState(() { showHistory = true; showTrail = false; }); break;
      case 'settings': widget.onSettings(); break;
      case 'dark': widget.onThemeTap(); break;
      case 'desktop':
        setState(() => desktopMode = !desktopMode);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('drox_browser_desktop_mode', desktopMode);
        await tab?.controller.setUserAgent(desktopMode ? 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' : null);
        tab?.controller.reload(); break;
      case 'about':
        if (mounted) showAboutDialog(context: context, applicationName: 'DROX', applicationVersion: '1.0', children: const [Text('Browser and download manager.')]);
        break;
    }
  }
  @override
  void dispose() { address.dispose(); homeSearch.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = tab;
    final isHome = current == null || current.url.isEmpty;
    final chromeBg = widget.isDark ? const Color(0xFF202124) : const Color(0xFFF1F3F4);
    final chromeSurface = widget.isDark ? const Color(0xFF303134) : Colors.white;
    return Container(
      color: chromeBg,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Column(children: [
          Material(
            color: chromeBg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                IconButton(tooltip: 'Smart Navigation Trail', onPressed: () => setState(() { showTrail = !showTrail; showHistory = false; showTabOverview = false; }), icon: Icon(Icons.route_rounded, color: showTrail ? const Color(0xFF4285F4) : cs.onSurfaceVariant)),
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(color: chromeSurface, borderRadius: BorderRadius.circular(28)),
                    child: Row(children: [
                      const SizedBox(width: 13),
                      Icon(isHome ? Icons.search_rounded : Icons.tune_rounded, size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 9),
                      Expanded(child: TextField(
                        controller: address,
                        onTap: () => address.selection = TextSelection(baseOffset: 0, extentOffset: address.text.length),
                        onSubmitted: (_) => go(),
                        textInputAction: TextInputAction.go,
                        keyboardType: TextInputType.url,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Search or type URL',
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      )),
                      IconButton(
                        tooltip: current?.loading == true ? 'Stop' : 'Reload',
                        onPressed: () {
                          if (current?.loading == true) {
                            current?.controller.runJavaScript('window.stop();');
                          } else if (current?.url.isNotEmpty == true) {
                            current!.controller.reload();
                          } else {
                            go();
                          }
                        },
                        icon: Icon(current?.loading == true ? Icons.close_rounded : Icons.refresh_rounded, size: 20, color: cs.onSurfaceVariant),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: _action,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'new', child: const ListTile(dense: true, leading: Icon(Icons.add_rounded), title: Text('New tab'))),
                    PopupMenuItem(value: 'history', child: const ListTile(dense: true, leading: Icon(Icons.history_rounded), title: Text('History'))),
                    PopupMenuItem(value: 'adblock', child: ListTile(dense: true, leading: const Icon(Icons.shield_rounded), title: const Text('Ad Block'), trailing: Icon(adBlockEnabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color: adBlockEnabled ? const Color(0xFF4285F4) : cs.onSurfaceVariant, size: 30))),
                    PopupMenuItem(value: 'desktop', child: ListTile(dense: true, leading: const Icon(Icons.desktop_windows_outlined), title: const Text('Desktop site'), trailing: Icon(desktopMode ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color: desktopMode ? const Color(0xFF4285F4) : cs.onSurfaceVariant, size: 30))),
                    PopupMenuItem(value: 'dark', child: ListTile(dense: true, leading: const Icon(Icons.dark_mode_outlined), title: const Text('Dark mode'), trailing: Icon(widget.isDark ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color: widget.isDark ? const Color(0xFF4285F4) : cs.onSurfaceVariant, size: 30))),
                    PopupMenuItem(value: 'settings', child: const ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
                    PopupMenuItem(value: 'about', child: const ListTile(dense: true, leading: Icon(Icons.info_outline_rounded), title: Text('About'))),
                  ],
                ),
              ]),
            ),
          ),
          if (current?.loading == true)
            Container(
              height: 25,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: chromeBg,
              child: Row(children: [
                const Expanded(child: LinearProgressIndicator(minHeight: 3, color: Color(0xFF4285F4), backgroundColor: Colors.transparent)),
                if (current?.refreshing == true) ...[
                  const SizedBox(width: 10),
                  const Text('Refreshing…', style: TextStyle(fontSize: 11, color: Color(0xFF4285F4), fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: Stack(children: [
                  Offstage(
                    offstage: isHome || showHistory || showTabOverview,
                    child: IndexedStack(
                      index: active,
                      children: tabs.map((item) => WebViewWidget(controller: item.controller)).toList(),
                    ),
                  ),
                  if (isHome && !showHistory && !showTabOverview) Positioned.fill(child: _buildStartPage()),
                  if (showHistory) Positioned.fill(child: _buildHistoryPage()),
                  if (showTabOverview) Positioned.fill(child: _buildTabOverview()),
                ]),
              ),
              if (showTrail)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => showTrail = false),
                    child: Container(color: Colors.black.withValues(alpha: .30)),
                  ),
                ),
              _buildTrailPanel(),
            ]),
          ),
          Material(
            color: chromeBg,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 5),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  IconButton(tooltip: 'Back', onPressed: current?.url.isNotEmpty == true ? _goBack : null, icon: const Icon(Icons.arrow_back_rounded)),
                  IconButton(tooltip: 'Forward', onPressed: current?.forward == true ? _goForward : null, icon: const Icon(Icons.arrow_forward_rounded)),
                  IconButton(tooltip: 'Home', onPressed: () {
                    setState(() {
                      if (current != null) { current.url = ''; current.title = 'Google'; current.loading = false; current.back = false; current.forward = false; }
                      address.clear(); homeSearch.clear(); showHistory = false; showTrail = false; showTabOverview = false;
                    });
                  }, icon: const Icon(Icons.home_outlined)),
                  IconButton(tooltip: 'Downloads', onPressed: widget.onReturn, icon: const Icon(Icons.download_outlined)),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _showTabs,
                    child: Container(
                      width: 31, height: 29,
                      decoration: BoxDecoration(border: Border.all(color: cs.onSurfaceVariant, width: 1.5), borderRadius: BorderRadius.circular(7)),
                      alignment: Alignment.center,
                      child: Text('${tabs.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
