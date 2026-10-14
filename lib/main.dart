import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const tmdbKey = String.fromEnvironment('TMDB_KEY');
const sections = ['Hollywood', 'Bollywood', 'Anime', 'Series', 'K-Drama'];
const accents = [Color(0xFF8B5CF6), Color(0xFFFF4D6D), Color(0xFF00B894), Color(0xFFFF9F1A), Color(0xFF0EA5E9)];

// ---------- Model ----------
class Item {
  final String id, title, overview, section, year;
  final String? poster;
  final double rating;
  Item(this.id, this.title, this.overview, this.section, this.year, this.poster, this.rating);
  Map<String, dynamic> toJson() => {'id': id, 't': title, 'o': overview, 's': section, 'y': year, 'p': poster, 'r': rating};
  factory Item.fromJson(Map<String, dynamic> j) =>
      Item(j['id'], j['t'], j['o'], j['s'], j['y'], j['p'], (j['r'] as num).toDouble());
}

// ---------- API ----------
Future<List<Item>> tmdb(String path, Map<String, String> q, String section) async {
  final uri = Uri.https('api.themoviedb.org', '/3/$path', {'api_key': tmdbKey, ...q});
  final r = await http.get(uri);
  if (r.statusCode != 200) throw Exception('TMDB ${r.statusCode}');
  final res = (jsonDecode(r.body)['results'] as List).where((j) => j['media_type'] != 'person');
  return res.map<Item>((j) {
    final d = (j['release_date'] ?? j['first_air_date'] ?? '') as String;
    final p = j['poster_path'];
    return Item('t${j['id']}', (j['title'] ?? j['name'] ?? '') as String, (j['overview'] ?? '') as String, section,
        d.length >= 4 ? d.substring(0, 4) : '', p == null ? null : 'https://image.tmdb.org/t/p/w342$p',
        ((j['vote_average'] ?? 0) as num).toDouble());
  }).toList();
}

Future<List<Item>> anilist({String? search}) async {
  const q = r'query($s:String){Page(perPage:20){media(type:ANIME,sort:TRENDING_DESC,search:$s){id title{romaji english} coverImage{large} averageScore seasonYear description(asHtml:false)}}}';
  final r = await http.post(Uri.https('graphql.anilist.co', '/'),
      headers: {'Content-Type': 'application/json'}, body: jsonEncode({'query': q, 'variables': {'s': search}}));
  if (r.statusCode != 200) throw Exception('AniList ${r.statusCode}');
  final list = jsonDecode(r.body)['data']['Page']['media'] as List;
  return list.map<Item>((m) {
    final t = m['title'];
    final desc = ((m['description'] ?? '') as String).replaceAll(RegExp(r'<[^>]*>'), '');
    return Item('a${m['id']}', (t['english'] ?? t['romaji'] ?? '') as String, desc, 'Anime',
        '${m['seasonYear'] ?? ''}', m['coverImage']['large'], ((m['averageScore'] ?? 0) as num) / 10);
  }).toList();
}

Future<List<Item>> load(String s) => switch (s) {
      'Hollywood' => tmdb('trending/movie/week', {}, s),
      'Bollywood' => tmdb('discover/movie', {'with_original_language': 'hi', 'sort_by': 'popularity.desc'}, s),
      'Anime' => anilist(),
      'Series' => tmdb('trending/tv/week', {}, s),
      _ => tmdb('discover/tv', {'with_original_language': 'ko', 'sort_by': 'popularity.desc'}, s),
    };

// ---------- State ----------
class AppState extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  int accent = 0;
  bool rank = true;
  List<Item> wl = [];
  final data = <String, List<Item>>{};
  final errors = <String, String>{};
  late SharedPreferences p;

  Future<void> init() async {
    p = await SharedPreferences.getInstance();
    mode = ThemeMode.values[p.getInt('mode') ?? 0];
    accent = p.getInt('acc') ?? 0;
    rank = p.getBool('rank') ?? true;
    wl = (p.getStringList('wl') ?? []).map((s) => Item.fromJson(jsonDecode(s))).toList();
    for (final s in sections) {
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

  void prefs({ThemeMode? m, int? a, bool? r}) {
    mode = m ?? mode;
    accent = a ?? accent;
    rank = r ?? rank;
    p.setInt('mode', mode.index);
    p.setInt('acc', accent);
    p.setBool('rank', rank);
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
  runApp(const VortexApp());
}

class VortexApp extends StatelessWidget {
  const VortexApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (_, __) => MaterialApp(
          title: 'Vortex',
          debugShowCheckedModeBanner: false,
          themeMode: app.mode,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: accents[app.accent]),
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: accents[app.accent]),
          home: const Shell(),
        ),
      );
}

// ---------- Widgets ----------
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

void openDetail(BuildContext context, Item i) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ListenableBuilder(
      listenable: app,
      builder: (ctx, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Poster(i, w: 100),
            const SizedBox(width: 16),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('${i.year} · ${i.section} · ★ ${i.rating.toStringAsFixed(1)}'),
            ])),
          ]),
          const SizedBox(height: 14),
          ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(child: Text(i.overview.isEmpty ? 'No description available.' : i.overview))),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: () => app.toggle(i),
                  icon: Icon(app.saved(i) ? Icons.bookmark : Icons.bookmark_add_outlined),
                  label: Text(app.saved(i) ? 'In watchlist (tap to remove)' : 'Add to watchlist'))),
        ]),
      ),
    ),
  );
}

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

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    const pages = [HomePage(), SearchPage(), WatchlistPage(), SettingsPage()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        NavigationDestination(icon: Icon(Icons.bookmark_outline), label: 'Watchlist'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ]),
    );
  }
}

// ---------- Pages ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String sel = 'All';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final secs = sel == 'All' ? sections : [sel];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Vortex', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in ['All', ...sections])
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(s), selected: sel == s, onSelected: (_) => setState(() => sel = s))),
                ])),
            for (final s in secs) ..._block(context, s),
          ]);
        },
      );

  List<Widget> _block(BuildContext context, String s) {
    final items = app.data[s];
    final err = app.errors[s];
    return [
      const SizedBox(height: 18),
      Text('🔥 $s — Trending Top 5', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (err != null)
        Row(children: [Expanded(child: Text(err)), TextButton(onPressed: () => app.fetch(s), child: const Text('Retry'))])
      else if (items == null)
        const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
      else ...[
        for (var i = 0; i < items.length && i < 5; i++)
          Card(
              child: ListTile(
            onTap: () => openDetail(context, items[i]),
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              if (app.rank) SizedBox(width: 26, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary))),
              Poster(items[i], w: 44),
            ]),
            title: Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${items[i].year} · ${s}'),
            trailing: Text('★ ${items[i].rating.toStringAsFixed(1)}'),
          )),
        const SizedBox(height: 10),
        Text('More in $s', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(height: 210, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(width: 10), itemBuilder: (_, i) => Card1(items[i]))),
      ],
    ];
  }
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
      final r = await Future.wait([tmdb('search/multi', {'query': q}, 'Search'), anilist(search: q)]);
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
          TextField(textInputAction: TextInputAction.search, onSubmitted: run, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search movies, series, anime', border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))))),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          Expanded(
              child: results == null
                  ? const Center(child: Text('Type a title and press search'))
                  : results!.isEmpty
                      ? const Center(child: Text('No results'))
                      : GridView.builder(gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 200, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: results!.length, itemBuilder: (_, i) => Card1(results![i], w: 120))),
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
            : GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 200, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: app.wl.length, itemBuilder: (_, i) => Card1(app.wl[i], w: 120)),
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
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show rank numbers'), value: app.rank, onChanged: (v) => app.prefs(r: v)),
          OutlinedButton(onPressed: app.clearWl, child: const Text('Clear watchlist')),
          const SizedBox(height: 24),
          const Text('Data provided by TMDB and AniList. This product uses the TMDB API but is not endorsed or certified by TMDB.', style: TextStyle(fontSize: 12)),
        ]),
      );
}

