import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

// Your video list lives in videos.json in this repo.
// Value is either one link, or {"360p": link, "720p": link, "1080p": link}.
const catalogUrl = 'https://raw.githubusercontent.com/mobid08rujee-coder/Playbox/main/videos.json';
Map<String, dynamic>? _cat;

Future<Map<String, String>?> videoFor(String title) async {
  try {
    _cat ??= jsonDecode((await http.get(Uri.parse(catalogUrl))).body) as Map<String, dynamic>;
    final v = _cat![title.toLowerCase()];
    if (v == null) return null;
    if (v is String) return {'Auto': v};
    if (v is List) return {for (var k = 0; k < v.length; k++) 'Server ${k + 1}': '${v[k]}'};
    return (v as Map).map((k, x) => MapEntry('$k', '$x'));
  } catch (_) {
    return null;
  }
}

String fmt(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerPage extends StatefulWidget {
  final Map<String, String> urls;
  final String title;
  final void Function(int, int)? onProgress;
  const PlayerPage(this.urls, this.title, {this.onProgress, super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? vc;
  late String q = widget.urls.containsKey('720p') ? '720p' : widget.urls.keys.first;
  bool ui = true, failed = false, land = false;
  double speed = 1;
  Timer? hide;
  SharedPreferences? sp;
  String get key => 'pos_${widget.title}';

  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open({Duration? at}) async {
    sp ??= await SharedPreferences.getInstance();
    final start = at ?? Duration(seconds: sp!.getInt(key) ?? 0);
    final n = VideoPlayerController.networkUrl(Uri.parse(widget.urls[q]!));
    try {
      await n.initialize();
      await n.seekTo(start);
      await n.setPlaybackSpeed(speed);
      await n.play();
      n.addListener(() {
        if (mounted) setState(() {});
      });
      final old = vc;
      vc = n;
      old?.dispose();
      if (mounted) setState(() {});
      poke();
    } catch (_) {
      final keys = widget.urls.keys.toList();
      final n = keys.indexOf(q) + 1;
      if (n < keys.length) {
        q = keys[n];
        open(at: start);
      } else if (mounted) {
        setState(() => failed = true);
      }
    }
  }

  void poke() {
    hide?.cancel();
    hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (vc?.value.isPlaying ?? false)) setState(() => ui = false);
    });
  }

  void seek(int s) {
    final c = vc!;
    final t = c.value.position + Duration(seconds: s);
    c.seekTo(t < Duration.zero ? Duration.zero : t);
    poke();
  }

  void rotate() {
    land = !land;
    SystemChrome.setPreferredOrientations(land ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(land ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    setState(() {});
  }

  @override
  void dispose() {
    hide?.cancel();
    if (vc != null) {
      sp?.setInt(key, vc!.value.position.inSeconds);
      widget.onProgress?.call(vc!.value.position.inSeconds, vc!.value.duration.inSeconds);
    }
    vc?.dispose();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = vc;
    final v = c?.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: failed
          ? const Center(child: Text('Could not play this video.'))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
                  onDoubleTapDown: (d) => seek(d.localPosition.dx < MediaQuery.of(context).size.width / 2 ? -10 : 10),
                  onTap: () {
                    setState(() => ui = !ui);
                    poke();
                  },
                  child: Stack(fit: StackFit.expand, children: [
                    Center(child: AspectRatio(aspectRatio: v!.aspectRatio, child: VideoPlayer(c))),
                    if (ui) ...[
                      Container(color: Colors.black38),
                      SafeArea(
                          child: Row(children: [
                        const BackButton(color: Colors.white),
                        Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16))),
                        if (widget.urls.length > 1)
                          PopupMenuButton<String>(
                              icon: const Icon(Icons.high_quality, color: Colors.white),
                              onSelected: (s) {
                                q = s;
                                open(at: c.value.position);
                              },
                              itemBuilder: (_) => [for (final k in widget.urls.keys) CheckedPopupMenuItem(value: k, checked: k == q, child: Text(k))]),
                      ])),
                      Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(iconSize: 40, color: Colors.white, icon: const Icon(Icons.replay_10), onPressed: () => seek(-10)),
                        const SizedBox(width: 16),
                        IconButton(
                            iconSize: 64,
                            color: Colors.white,
                            icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle),
                            onPressed: () {
                              v.isPlaying ? c.pause() : c.play();
                              poke();
                            }),
                        const SizedBox(width: 16),
                        IconButton(iconSize: 40, color: Colors.white, icon: const Icon(Icons.forward_10), onPressed: () => seek(10)),
                      ])),
                      Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                              child: Row(children: [
                            const SizedBox(width: 12),
                            Text(fmt(v.position), style: const TextStyle(color: Colors.white)),
                            Expanded(
                                child: Slider(
                                    value: v.position.inMilliseconds.clamp(0, v.duration.inMilliseconds).toDouble(),
                                    max: v.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                    onChanged: (x) => c.seekTo(Duration(milliseconds: x.toInt())))),
                            Text(fmt(v.duration), style: const TextStyle(color: Colors.white)),
                            PopupMenuButton<double>(
                                icon: const Icon(Icons.speed, color: Colors.white),
                                onSelected: (s) {
                                  speed = s;
                                  c.setPlaybackSpeed(s);
                                },
                                itemBuilder: (_) => [for (final s in [0.5, 1.0, 1.5, 2.0]) CheckedPopupMenuItem(value: s, checked: s == speed, child: Text('${s}x'))]),
                            IconButton(color: Colors.white, icon: Icon(land ? Icons.fullscreen_exit : Icons.fullscreen), onPressed: rotate),
                          ]))),
                    ],
                  ])),
    );
  }
}
