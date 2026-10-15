import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const tmdbKey = String.fromEnvironment('TMDB_KEY');
const omdbKey = String.fromEnvironment('OMDB_KEY');
const accents = [Color(0xFF8B5CF6), Color(0xFFFF4D6D), Color(0xFF00B894), Color(0xFFFF9F1A), Color(0xFF0EA5E9)];
const homeSecs = ['Hollywood', 'Bollywood', 'Action', 'Adventure', 'Drama', 'Anime', 'K-Drama', 'Series', 'OTT Shows'];
const aGenres = ['All', 'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller'];
const aFormats = {'All': null, 'TV': 'TV', 'Movie': 'MOVIE', 'OVA': 'OVA', 'ONA': 'ONA', 'Special': 'SPECIAL'};

// ---------- Model ----------
class Item {
  final String id, title, overview, year, kind, extra;
  final String? poster;
  final double rating;
  Item(this.id, this.title, this.overview, this.year, this.kind, this.extra, this.poster, this.rating);
  String get label => kind == 'anime' ? 'Anime' : kind == 'tv' ? 'TV Show' : 'Movie';
  Map<String, dynamic> toJson() => {'id': id, 't': title, 'o': overview, 'y': year, 'k': kind, 'x': extra, 'p': poster, 'r': rating};
  factory Item.fromJson(Map<String, dynamic> j) =>
      Item(j['id'], j['t'], j['o'], j['y'], j['k'] ?? 'movie', j['x'] ?? '', j['p'], (j['r'] as num).toDouble());
}

// ---------- API ----------
Future<List<Item>> tmdb(String path, Map<String, String> q, String kind) async {
  final r = await http.get(Uri.https('api.themoviedb.org', '/3/$path', {'api_key': tmdbKey, ...q}));
  if (r.statusCode != 200) throw Exception('TMDB ${r.statusCode}');
  return (jsonDecode(r.body)['results'] as List).where((j) => j['media_type'] != 'person').map<Item>((j) {
    final d = (j['release_date'] ?? j['first_air_date'] ?? '') as String;
    final k = (j['media_type'] ?? kind) as String;
    final p = j['poster_path'];
    return Item('t$k${j['id']}', (j['title'] ?? j['name'] ?? '') as String, (j['overview'] ?? '') as String,
        d.length >= 4 ? d.substring(0, 4) : '', k, '', p == null ? null : 'https://image.tmdb.org/t/p/w500$p',
        ((j['vote_average'] ?? 0) as num).toDouble());
  }).toList();
}

Future<List<Item>> anilist({String? search, String? genre, String? format, int page = 1, String sort = 'TRENDING_DESC'}) async {
  const q = r'query($s:String,$g:String,$f:MediaFormat,$p:Int,$o:[MediaSort]){Page(page:$p,perPage:24){media(type:ANIME,search:$s,genre:$g,format:$f,sort:$o){id title{romaji english} coverImage{large} averageScore seasonYear format episodes genres description(asHtml:false)}}}';
  final r = await http.post(Uri.https('graphql.anilist.co', '/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': q, 'variables': {'s': search, 'g': genre, 'f': format, 'p': page, 'o': [sort]}}));
  if (r.statusCode != 200) throw Exception('AniList ${r.statusCode}');
  return (jsonDecode(r.body)['data']['Page']['media'] as List).map<Item>((m) {
    final t = m['title'];
    final desc = ((m['description'] ?? '') as String).replaceAll(RegExp(r'<[^>]*>'), '');
    final extra = [...((m['genres'] ?? []) as List).take(3), if (m['format'] != null) '${m['format']}'].join(' · ');
    return Item('a${m['id']}', (t['english'] ?? t['romaji'] ?? '') as String, desc, '${m['seasonYear'] ?? ''}', 'anime',
        extra, m['coverImage']['large'], ((m['averageScore'] ?? 0) as num) / 10);
  }).toList();
}

// IMDb rating via OMDb (needs OMDB_KEY). Returns null if unavailable.
Future<String?> imdb(Item i) async {
  if (omdbKey.isEmpty) return null;
  try {
    Uri u;
    if (i.kind == 'anime') {
      u = Uri.https('www.omdbapi.com', '/', {'apikey': omdbKey, 't': i.title, if (i.year.isNotEmpty) 'y': i.year});
    } else {
      final id = i.id.substring(1 + i.kind.length);
      final e = await http.get(Uri.https('api.themoviedb.org', '/3/${i.kind}/$id/external_ids', {'api_key': tmdbKey}));
      final ii = jsonDecode(e.body)['imdb_id'];
      if (ii == null || ii == '') return null;
      u = Uri.https('www.omdbapi.com', '/', {'apikey': omdbKey, 'i': ii as String});
    }
    final v = jsonDecode((await http.get(u)).body)['imdbRating'];
    return (v == null || v == 'N/A') ? null : v as String;
  } catch (_) {
    return null;
  }
}

Future<List<Item>> load(String s) => switch (s) {
      'Hollywood' => tmdb('trending/movie/week', {}, 'movie'),
      'Bollywood' => tmdb('discover/movie', {'with_original_language': 'hi', 'sort_by': 'popularity.desc'}, 'movie'),
      'Action' => tmdb('discover/movie', {'with_genres': '28', 'sort_by': 'popularity.desc'}, 'movie'),
      'Adventure' => tmdb('discover/movie', {'with_genres': '12', 'sort_by': 'popularity.desc'}, 'movie'),
      'Drama' => tmdb('discover/movie', {'with_genres': '18', 'sort_by': 'popularity.desc'}, 'movie'),
      'Anime' => anilist(),
      'K-Drama' => tmdb('discover/tv', {'with_original_language': 'ko', 'sort_by': 'popularity.desc'}, 'tv'),
      'Series' => tmdb('trending/tv/week', {}, 'tv'),
      _ => tmdb('discover/tv', {'with_watch_providers': '8|119|122', 'watch_region': 'IN', 'sort_by': 'popularity.desc'}, 'tv'),
    };

// ---------- State ----------
class AppState extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  int accent = 0;
  List<Item> wl = [];
  final data = <String, List<Item>>{};
  final errors = <String, String>{};
  late SharedPreferences p;

  Future<void> init() async {
    p = await SharedPreferences.getInstance();
    mode = ThemeMode.values[p.getInt('mode') ?? 0];
    accent = p.getInt('acc') ?? 0;
    wl = (p.getStringList('wl') ?? []).map((s) => Item.fromJson(jsonDecode(s))).toList();
    for (final s in homeSecs) {
      fetch(s);
    }
  }

  Future<void> fetch(String s) async {
    try {
      data[s] = await load(s);
      errors.remove(s);
    } catch (e) {
      errors[s] = 'Could not load. Check your API key and connection.';
    }
    notifyListeners();
  }

  void prefs({ThemeMode? m, int? a}) {
    mode = m ?? mode;
    accent = a ?? accent;
    p.setInt('mode', mode.index);
    p.setInt('acc', accent);
    notifyListeners();
  }

  bool saved(Item i) => wl.any((x) => x.id == i.id);
  void toggle(Item i) {
    saved(i) ? wl.removeWhere((x) => x.id == i.id) : wl.add(i);
    p.setStringList('wl', wl.map((x) => jsonEncode(x.toJson())).toList());
    notifyListeners();
  }

  void clearWl() {
    wl = [];
    p.setStringList('wl', []);
    notifyListeners();
  }
}

final app = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  runApp(const PlayboxApp());
}

class PlayboxApp extends StatelessWidget {
  const PlayboxApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (_, __) => MaterialApp(
          title: 'Playbox',
          debugShowCheckedModeBanner: false,
          themeMode: app.mode,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: accents[app.accent]),
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: accents[app.accent]),
          home: const Splash(),
        ),
      );
}

// ---------- Splash (logo animation) ----------
class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => const Shell(), transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)));
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0B0B12),
        body: Center(
          child: AnimatedBuilder(
            animation: c,
            builder: (_, __) {
              final t = Curves.easeOutBack.transform(c.value);
              return Opacity(
                opacity: c.value.clamp(0.0, 1.0).toDouble(),
                child: Transform.scale(
                  scale: 0.5 + 0.5 * t,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Transform.rotate(
                      angle: (1 - c.value) * 3.14,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF22D3EE)])),
                        child: const Icon(Icons.play_arrow_rounded, size: 64, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Playbox', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}

// ---------- Shared widgets ----------
class Poster extends StatelessWidget {
  final Item item;
  final double w;
  const Poster(this.item, {this.w = 110, super.key});
  @override
  Widget build(BuildContext context) {
    final fb = Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(child: Text(item.title.isEmpty ? '?' : item.title[0], style: const TextStyle(fontSize: 28))));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
          width: w,
          height: w * 1.5,
          child: item.poster == null ? fb : Image.network(item.poster!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fb)),
    );
  }
}

void openDetail(BuildContext context, Item i) => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(i)));

class Card1 extends StatelessWidget {
  final Item item;
  final double w;
  const Card1(this.item, {this.w = 110, super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openDetail(context, item),
        child: SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Poster(item, w: w),
              const SizedBox(height: 4),
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('★ ${item.rating.toStringAsFixed(1)} · ${item.year}', style: const TextStyle(fontSize: 12)),
            ])),
      );
}

Widget chipRow(List<String> l, String sel, void Function(String) on) => SizedBox(
    height: 44,
    child: ListView(scrollDirection: Axis.horizontal, children: [
      for (final s in l)
        Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: sel == s, onSelected: (_) => on(s))),
    ]));

const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 215, crossAxisSpacing: 10, mainAxisSpacing: 10);

// ---------- Detail page ----------
class DetailPage extends StatelessWidget {
  final Item i;
  const DetailPage(this.i, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: [
          ListenableBuilder(
              listenable: app,
              builder: (_, __) => IconButton(
                  tooltip: 'Watchlist', icon: Icon(app.saved(i) ? Icons.bookmark : Icons.bookmark_add_outlined), onPressed: () => app.toggle(i))),
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: Poster(i, w: 200)),
          const SizedBox(height: 16),
          Text(i.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text([i.label, if (i.year.isNotEmpty) i.year, if (i.extra.isNotEmpty) i.extra].join(' · ')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            Chip(label: Text('${i.kind == 'anime' ? 'AniList' : 'TMDB'} ★ ${i.rating.toStringAsFixed(1)}')),
            FutureBuilder<String?>(
                future: imdb(i),
                builder: (_, s) => Chip(
                    label: Text(s.connectionState != ConnectionState.done
                        ? 'IMDb …'
                        : s.data != null
                            ? 'IMDb ★ ${s.data}'
                            : omdbKey.isEmpty ? 'IMDb: add OMDb key' : 'IMDb: not found'))),
          ]),
          const SizedBox(height: 16),
          Text('Description', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(i.overview.isEmpty ? 'No description available.' : i.overview),
        ]),
      );
}

// ---------- Pages ----------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: IndexedStack(index: tab, children: const [HomePage(), AnimePage(), SearchPage(), WatchlistPage(), SettingsPage()])),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'Anime'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), label: 'Watchlist'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ]),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Playbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          for (final s in homeSecs) ...[
            Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Text(s, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (app.errors[s] != null)
              Row(children: [Expanded(child: Text(app.errors[s]!)), TextButton(onPressed: () => app.fetch(s), child: const Text('Retry'))])
            else if (app.data[s] == null)
              const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
            else
              SizedBox(
                  height: 215,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: app.data[s]!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => Card1(app.data[s]![i]))),
          ],
        ]),
      );
}

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});
  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  String g = 'All', f = 'All';
  List<Item> items = [];
  int page = 1;
  bool busy = false, more = true;
  @override
  void initState() {
    super.initState();
    fetch(true);
  }

  Future<void> fetch(bool reset) async {
    if (reset) {
      page = 1;
      items = [];
      more = true;
    }
    setState(() => busy = true);
    try {
      final r = await anilist(genre: g == 'All' ? null : g, format: aFormats[f], page: page, sort: 'POPULARITY_DESC');
      items = [...items, ...r];
      more = r.length == 24;
    } catch (_) {
      more = false;
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Anime', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          chipRow(aFormats.keys.toList(), f, (v) {
            f = v;
            fetch(true);
          }),
          chipRow(aGenres, g, (v) {
            g = v;
            fetch(true);
          }),
          const SizedBox(height: 8),
          Expanded(
              child: GridView.builder(
                  gridDelegate: gridDelegate,
                  itemCount: items.length + 1,
                  itemBuilder: (_, i) {
                    if (i < items.length) return Card1(items[i], w: 120);
                    if (busy) return const Center(child: CircularProgressIndicator());
                    return more
                        ? Center(
                            child: TextButton(
                                onPressed: () {
                                  page++;
                                  fetch(false);
                                },
                                child: const Text('Load more')))
                        : const SizedBox();
                  })),
        ]),
      );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  List<Item>? results;
  bool busy = false;
  Future<void> run(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await Future.wait([tmdb('search/multi', {'query': q}, 'movie'), anilist(search: q)]);
      results = [...r[0], ...r[1]];
    } catch (_) {
      results = [];
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: run,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search movies, series, anime', border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))))),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          Expanded(
              child: results == null
                  ? const Center(child: Text('Type a title and press search'))
                  : results!.isEmpty
                      ? const Center(child: Text('No results'))
                      : GridView.builder(gridDelegate: gridDelegate, itemCount: results!.length, itemBuilder: (_, i) => Card1(results![i], w: 120))),
        ]),
      );
}

class WatchlistPage extends StatelessWidget {
  const WatchlistPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => app.wl.isEmpty
            ? const Center(child: Text('Nothing saved yet'))
            : GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: gridDelegate, itemCount: app.wl.length, itemBuilder: (_, i) => Card1(app.wl[i], w: 120)),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text('Theme'),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
              segments: const [ButtonSegment(value: ThemeMode.system, label: Text('System')), ButtonSegment(value: ThemeMode.light, label: Text('Light')), ButtonSegment(value: ThemeMode.dark, label: Text('Dark'))],
              selected: {app.mode},
              onSelectionChanged: (s) => app.prefs(m: s.first)),
          const SizedBox(height: 20),
          const Text('Accent color'),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < accents.length; i++)
              GestureDetector(
                  onTap: () => app.prefs(a: i),
                  child: Container(margin: const EdgeInsets.only(right: 10), width: 34, height: 34, decoration: BoxDecoration(color: accents[i], shape: BoxShape.circle, border: Border.all(width: 3, color: app.accent == i ? Theme.of(context).colorScheme.onSurface : Colors.transparent)))),
          ]),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: app.clearWl, child: const Text('Clear watchlist')),
          const SizedBox(height: 24),
          const Text('Data from TMDB, AniList and OMDb (IMDb ratings). This product uses the TMDB API but is not endorsed or certified by TMDB.', style: TextStyle(fontSize: 12)),
        ]),
      );
}
