import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player.dart';

const tmdbKey = String.fromEnvironment('TMDB_KEY');
const omdbKey = String.fromEnvironment('OMDB_KEY');
const accents = [Color(0xFF8B5CF6), Color(0xFFFF4D6D), Color(0xFF00B894), Color(0xFFFF9F1A), Color(0xFF0EA5E9)];
const homeSecs = ['Recently Added Movies', 'Recently Added Series', 'Top 10 Rated Movies', 'Top 10 Rated Series', 'Top Series This Week', 'Top Movies This Week', 'Hollywood', 'Bollywood', 'K-Drama', 'OTT Shows', 'Action', 'Adventure', 'Drama', 'Horror', 'Comedy', 'Romance', 'Sci-Fi', 'Thriller', 'Crime', 'Animation', 'Fantasy', 'Mystery', 'Family', 'Documentary'];
const animeSecs = ['Trending Anime', 'Top Rated Anime', 'Popular Anime', 'Anime Movies'];
const provs = {'Prime Video': '119', 'Netflix': '8', 'Sony LIV': '237', 'Crunchyroll': '283', 'JioHotstar': '122'};
const genres = {'Action': '28', 'Adventure': '12', 'Drama': '18', 'Horror': '27', 'Comedy': '35', 'Romance': '10749', 'Sci-Fi': '878', 'Thriller': '53', 'Crime': '80', 'Animation': '16', 'Fantasy': '14', 'Mystery': '9648', 'Family': '10751', 'Documentary': '99', 'War': '10752', 'History': '36', 'Music': '10402', 'Western': '37', 'Anime': ''};
const langs = {'Hindi': 'hi', 'English': 'en', 'Bengali': 'bn', 'Assamese': 'as', 'Tamil': 'ta', 'Telugu': 'te'};
const aGenres = ['All', 'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller'];
const aFormats = {'All': null, 'TV': 'TV', 'Movie': 'MOVIE', 'OVA': 'OVA', 'ONA': 'ONA', 'Special': 'SPECIAL'};

// ---------- Model ----------
class Item {
  final String id, title, overview, year, kind, extra;
  final String? poster;
  final double rating;
  final bool isNew;
  Item(this.id, this.title, this.overview, this.year, this.kind, this.extra, this.poster, this.rating, {this.isNew = false});
  String get label => kind == 'anime' ? 'Anime' : kind == 'tv' ? 'TV Show' : 'Movie';
  String? get lang {
    if (kind == 'anime' || extra.isEmpty) return null;
    const m = {'hi': 'HIN', 'en': 'ENG', 'ta': 'TAM', 'te': 'TEL', 'bn': 'BEN', 'mr': 'MAR', 'pa': 'PUN', 'ko': 'KOR', 'ja': 'JPN', 'ml': 'MAL', 'kn': 'KAN', 'as': 'ASM'};
    return m[extra] ?? 'MULTI';
  }

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'o': overview, 'y': year, 'k': kind, 'x': extra, 'p': poster, 'r': rating, 'n': isNew};
  factory Item.fromJson(Map<String, dynamic> j) =>
      Item(j['id'], j['t'], j['o'], j['y'], j['k'] ?? 'movie', j['x'] ?? '', j['p'], (j['r'] as num).toDouble(), isNew: j['n'] == true);
}

// ---------- API ----------
Item _toItem(Map j, String kind) {
  final d = (j['release_date'] ?? j['first_air_date'] ?? '') as String;
  final k = (j['media_type'] ?? kind) as String;
  final p = j['poster_path'];
  final dt = DateTime.tryParse(d);
  return Item('t$k${j['id']}', (j['title'] ?? j['name'] ?? '') as String, (j['overview'] ?? '') as String,
      d.length >= 4 ? d.substring(0, 4) : '', k, (j['original_language'] ?? '') as String, p == null ? null : 'https://image.tmdb.org/t/p/w500$p',
      ((j['vote_average'] ?? 0) as num).toDouble(),
      isNew: dt != null && dt.isAfter(DateTime.now().subtract(const Duration(days: 90))));
}

Future<List<Item>> tmdb(String path, Map<String, String> q, String kind) async {
  final r = await http.get(Uri.https('api.themoviedb.org', '/3/$path', {'api_key': tmdbKey, ...q}));
  if (r.statusCode != 200) throw Exception('TMDB ${r.statusCode}');
  final out = <Item>[];
  for (final j in jsonDecode(r.body)['results'] as List) {
    if (j['media_type'] == 'person') {
      for (final k in (j['known_for'] ?? []) as List) {
        if (k['media_type'] == 'movie' || k['media_type'] == 'tv') out.add(_toItem(k, kind));
      }
    } else {
      out.add(_toItem(j, kind));
    }
  }
  final seen = <String>{};
  return out.where((x) => seen.add(x.id)).toList();
}

const sortMap = {'Popular': 'popularity.desc', 'Top Rated': 'vote_average.desc', 'Newest': 'primary_release_date.desc'};
Future<List<Item>> discover(String g, String l, [int page = 1, String sort = 'popularity.desc', String year = 'All']) => g == 'Anime'
    ? anilist(sort: 'POPULARITY_DESC', page: page)
    : tmdb('discover/movie', {'sort_by': sort, 'page': '$page', if (sort.startsWith('vote')) 'vote_count.gte': '300', if (sort.startsWith('primary')) 'primary_release_date.lte': DateTime.now().toIso8601String().substring(0, 10), if (year != 'All') 'primary_release_year': year, if (g != 'All') 'with_genres': genres[g]!, if (l != 'All') 'with_original_language': langs[l]!}, 'movie');

Future<Map<String, dynamic>?> detailsOf(Item i) async {
  if (i.kind == 'anime') return null;
  try {
    final r = await http.get(Uri.https('api.themoviedb.org', '/3/${i.kind}/${i.id.substring(1 + i.kind.length)}', {'api_key': tmdbKey, 'append_to_response': 'credits,recommendations'}));
    return jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<List<Item>> anilist({String? search, String? genre, String? format, int page = 1, String sort = 'TRENDING_DESC'}) async {
  const q = r'query($s:String,$g:String,$f:MediaFormat,$p:Int,$o:[MediaSort]){Page(page:$p,perPage:24){media(type:ANIME,search:$s,genre:$g,format:$f,sort:$o){id title{romaji english} coverImage{large} averageScore seasonYear format episodes genres description(asHtml:false)}}}';
  final r = await http.post(Uri.https('graphql.anilist.co', '/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': q, 'variables': {'s': search, 'g': genre, 'f': format, 'p': page, 'o': [sort]}}));
  if (r.statusCode != 200) throw Exception('AniList ${r.statusCode}');
  return (jsonDecode(r.body)['data']['Page']['media'] as List).map<Item>(_anime).toList();
}

Item _anime(dynamic m) {
  final t = m['title'];
  final desc = ((m['description'] ?? '') as String).replaceAll(RegExp(r'<[^>]*>'), '');
  final extra = [...((m['genres'] ?? []) as List).take(3), if (m['format'] != null) '${m['format']}'].join(' · ');
  return Item('a${m['id']}', (t['english'] ?? t['romaji'] ?? '') as String, desc, '${m['seasonYear'] ?? ''}', 'anime',
      extra, m['coverImage']['large'], ((m['averageScore'] ?? 0) as num) / 10);
}

Future<List<Item>> animeByStudio(String name, int page) async {
  const q = r'query($s:String,$p:Int){Studio(search:$s){media(sort:POPULARITY_DESC,page:$p,perPage:24){nodes{id title{romaji english} coverImage{large} averageScore seasonYear format genres description(asHtml:false)}}}}';
  final r = await http.post(Uri.https('graphql.anilist.co', '/'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'query': q, 'variables': {'s': name, 'p': page}}));
  if (r.statusCode != 200) throw Exception('AniList ${r.statusCode}');
  return (jsonDecode(r.body)['data']['Studio']['media']['nodes'] as List).map<Item>(_anime).toList();
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

Future<List<Item>> providerLoad(String s, int page) async {
  final q = {'with_watch_providers': provs[s]!, 'watch_region': 'IN', 'sort_by': 'popularity.desc', 'page': '$page'};
  final r = await Future.wait([tmdb('discover/movie', q, 'movie'), tmdb('discover/tv', q, 'tv')]);
  return [for (var i = 0; i < 20; i++) ...[if (i < r[0].length) r[0][i], if (i < r[1].length) r[1][i]]];
}

Future<List<Item>> load(String s, [int page = 1]) {
  final pg = {'page': '$page'};
  if (provs.containsKey(s)) return providerLoad(s, page);
  if (genres.containsKey(s) && s != 'Anime') {
    return tmdb('discover/movie', {'sort_by': 'popularity.desc', 'with_genres': genres[s]!, ...pg}, 'movie');
  }
  return switch (s) {
    'Recently Added Movies' => tmdb('movie/now_playing', {'region': 'IN', ...pg}, 'movie'),
    'Recently Added Series' => tmdb('tv/on_the_air', pg, 'tv'),
    'Top 10 Rated Movies' => tmdb('movie/top_rated', pg, 'movie'),
    'Top 10 Rated Series' => tmdb('tv/top_rated', pg, 'tv'),
    'Top Series This Week' => tmdb('trending/tv/week', pg, 'tv'),
    'Top Movies This Week' => tmdb('trending/movie/week', pg, 'movie'),
    'Hollywood' => tmdb('discover/movie', {'with_original_language': 'en', 'sort_by': 'popularity.desc', ...pg}, 'movie'),
    'Bollywood' => tmdb('discover/movie', {'with_original_language': 'hi', 'sort_by': 'popularity.desc', ...pg}, 'movie'),
    'K-Drama' => tmdb('discover/tv', {'with_original_language': 'ko', 'sort_by': 'popularity.desc', ...pg}, 'tv'),
    'Trending Anime' || 'Anime' => anilist(page: page),
    'Top Rated Anime' => anilist(sort: 'SCORE_DESC', page: page),
    'Popular Anime' => anilist(sort: 'POPULARITY_DESC', page: page),
    'Anime Movies' => anilist(format: 'MOVIE', sort: 'POPULARITY_DESC', page: page),
    _ => tmdb('discover/tv', {'with_watch_providers': '8|119|122', 'watch_region': 'IN', 'sort_by': 'popularity.desc', ...pg}, 'tv'),
  };
}

// ---------- State ----------
class AppState extends ChangeNotifier {
  ThemeMode mode = ThemeMode.dark;
  int accent = 0;
  List<Item> wl = [];
  final data = <String, List<Item>>{};
  final errors = <String, String>{};
  Map<String, List<Item>> lists = {'Favorites': [], 'Plan to Watch': [], 'Completed': []};
  List<Map<String, dynamic>> hist = [];
  SharedPreferences? p;

  Future<void> init() async {
    try {
      p = await SharedPreferences.getInstance();
      mode = ThemeMode.values[(p!.getInt('mode') ?? 2).clamp(0, 2)];
      accent = (p!.getInt('acc') ?? 0).clamp(0, accents.length - 1);
      wl = (p!.getStringList('wl') ?? []).map((s) => Item.fromJson(jsonDecode(s))).toList();
      final ls = p!.getString('lists');
      if (ls != null) {
        lists = (jsonDecode(ls) as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).map((e) => Item.fromJson(Map<String, dynamic>.from(e))).toList()));
      }
      hist = (jsonDecode(p!.getString('hist') ?? '[]') as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      errors['init'] = '$e';
    }
    for (final s in [...homeSecs, ...animeSecs]) {
      fetch(s);
    }
  }

  Future<void> fetch(String s) async {
    try {
      data[s] = await load(s);
      errors.remove(s);
    } catch (e) {
      errors[s] = 'Could not load: ${'$e'.split('\n').first}';
    }
    notifyListeners();
  }

  void prefs({ThemeMode? m, int? a}) {
    mode = m ?? mode;
    accent = a ?? accent;
    p?.setInt('mode', mode.index);
    p?.setInt('acc', accent);
    notifyListeners();
  }

  void _saveLists() => p?.setString('lists', jsonEncode(lists.map((k, v) => MapEntry(k, v.map((x) => x.toJson()).toList()))));
  bool inList(String n, Item i) => lists[n]!.any((x) => x.id == i.id);
  void toggleIn(String n, Item i) {
    inList(n, i) ? lists[n]!.removeWhere((x) => x.id == i.id) : lists[n]!.add(i);
    _saveLists();
    notifyListeners();
  }

  void newList(String n) {
    n = n.trim();
    if (n.isNotEmpty && n != 'My List' && !lists.containsKey(n)) lists[n] = [];
    _saveLists();
    notifyListeners();
  }

  void delList(String n) {
    lists.remove(n);
    _saveLists();
    notifyListeners();
  }

  void progress(Item i, int pos, int dur) {
    hist.removeWhere((h) => h['i']['id'] == i.id);
    if (dur > 0 && pos > 10 && pos < dur * 0.95) hist.insert(0, {'i': i.toJson(), 'p': pos, 'd': dur});
    if (hist.length > 20) hist = hist.sublist(0, 20);
    p?.setString('hist', jsonEncode(hist));
    Future.microtask(notifyListeners);
  }

  bool saved(Item i) => wl.any((x) => x.id == i.id);
  void toggle(Item i) {
    saved(i) ? wl.removeWhere((x) => x.id == i.id) : wl.add(i);
    p?.setStringList('wl', wl.map((x) => jsonEncode(x.toJson())).toList());
    notifyListeners();
  }

  void clearWl() {
    wl = [];
    p?.setStringList('wl', []);
    notifyListeners();
  }
}

final app = AppState();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorWidget.builder = (d) => Material(
        color: Colors.black,
        child: Padding(padding: const EdgeInsets.all(16), child: SingleChildScrollView(child: Text('${d.exception}', style: const TextStyle(color: Colors.redAccent)))));
    try {
      await app.init();
    } catch (e) {
      app.errors['init'] = '$e';
    }
    runApp(const PlayboxApp());
  }, (e, s) {});
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
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: accents[app.accent], scaffoldBackgroundColor: Colors.black, navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.black, indicatorColor: Colors.transparent, height: 66)),
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
class Pill extends StatelessWidget {
  final String t;
  final bool small;
  const Pill(this.t, {this.small = false, super.key});
  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 12, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Text(t, style: TextStyle(color: Colors.black, fontSize: small ? 10 : 12, fontWeight: FontWeight.w800)));
}

class Poster extends StatelessWidget {
  final Item item;
  final double w;
  const Poster(this.item, {this.w = 110, super.key});
  @override
  Widget build(BuildContext context) {
    final fb = DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1E2A), Color(0xFF0E0E14)])),
        child: Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(item.title, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)))));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
          width: w,
          height: w * 1.5,
          child: Stack(fit: StackFit.expand, children: [
            item.poster == null ? fb : Image.network(item.poster!, fit: BoxFit.cover, loadingBuilder: (c, ch, pr) => pr == null ? ch : fb, errorBuilder: (_, __, ___) => fb),
            if (item.lang != null) Positioned(top: 6, left: 6, child: Pill(item.lang!, small: true)),
            if (item.isNew)
              Positioned(
                  top: 6,
                  right: 6,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(10)), child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)))),
            if (item.rating > 0)
              Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(10)),
                      child: Text('★ ${item.rating.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))),
          ])),
    );
  }
}

void openDetail(BuildContext context, Item i) => Navigator.push(
    context,
    PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => DetailPage(i),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child))));

class PlayBtn extends StatelessWidget {
  final Item i;
  final bool inDetail, white;
  const PlayBtn(this.i, {this.inDetail = false, this.white = false, super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>?>(
      future: videoFor(i.title),
      builder: (c, s) {
        final ok = s.data != null;
        if (!ok && inDetail) return const SizedBox();
        return FilledButton.icon(
            style: white ? FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size(140, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)) : null,
            onPressed: () => ok ? Navigator.push(c, MaterialPageRoute(builder: (_) => PlayerPage(s.data!, i.title, onProgress: (p, d) => app.progress(i, p, d)))) : openDetail(c, i),
            icon: Icon(ok ? Icons.play_arrow : Icons.info_outline),
            label: Text(ok ? 'Play' : 'Details'));
      });
}

class Card1 extends StatelessWidget {
  final Item item;
  final double w;
  const Card1(this.item, {this.w = 112, super.key});
  @override
  Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(14), onTap: () => openDetail(context, item), child: Poster(item, w: w));
}

Widget chipRow(List<String> l, String sel, void Function(String) on) => SizedBox(
    height: 44,
    child: ListView(scrollDirection: Axis.horizontal, children: [
      for (final s in l)
        Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: sel == s, showCheckmark: false, shape: const StadiumBorder(), onSelected: (_) => on(s))),
    ]));

const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 180, crossAxisSpacing: 10, mainAxisSpacing: 10);

// ---------- Detail page ----------
class DetailPage extends StatelessWidget {
  final Item i;
  const DetailPage(this.i, {super.key});

  Future<List<Item>> recsOf(Map<String, dynamic>? d) async {
    if (i.kind == 'anime') {
      final g = i.extra.split(' · ').first;
      try {
        return (await anilist(genre: g.isEmpty ? null : g, sort: 'POPULARITY_DESC')).where((x) => x.id != i.id).toList();
      } catch (_) {
        return [];
      }
    }
    return ((d?['recommendations']?['results'] ?? []) as List).where((x) => x['poster_path'] != null).take(15).map<Item>((x) => _toItem(x, i.kind)).toList();
  }

  Widget people(BuildContext c, List l) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final x in l) ActionChip(label: Text('${x['name']}'), onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => PersonPage(x['id'] as int, '${x['name']}')))),
      ]);

  Widget sec(String t) => Padding(padding: const EdgeInsets.only(top: 28, bottom: 10), child: Text(t, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)));

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: detailsOf(i),
        builder: (context, snap) {
          final d = snap.data;
          List names(dynamic l) => ((l ?? []) as List).map((x) => x['name']).toList();
          final castL = ((d?['credits']?['cast'] ?? []) as List).take(10).toList();
          final dirL = i.kind == 'movie' ? ((d?['credits']?['crew'] ?? []) as List).where((x) => x['job'] == 'Director').toList() : ((d?['created_by'] ?? []) as List);
          final gens = i.kind == 'anime' ? i.extra.split(' · ').where((x) => x.isNotEmpty).toList() : names(d?['genres']);
          final country = i.kind == 'anime' ? 'Japan' : (names(d?['production_countries']).isNotEmpty ? names(d?['production_countries']).first : ((d?['origin_country'] ?? []) as List).join(', '));
          final votes = d?['vote_count'];
          final langsTxt = i.kind == 'anime' ? 'Japanese' : ((d?['spoken_languages'] ?? []) as List).map((x) => x['english_name']).join(', ');
          final bd = d?['backdrop_path'];
          const grey = TextStyle(fontSize: 18, color: Colors.white70);
          return Scaffold(
            floatingActionButton: FutureBuilder<Map<String, String>?>(
                future: videoFor(i.title),
                builder: (c, s) => FloatingActionButton.extended(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    icon: const Icon(Icons.play_arrow, size: 28),
                    label: const Text('Watch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    onPressed: () => s.data != null
                        ? Navigator.push(c, MaterialPageRoute(builder: (_) => PlayerPage(s.data!, i.title, onProgress: (p, d) => app.progress(i, p, d))))
                        : ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('No video is linked for this title yet.'))))),
            body: ListView(padding: EdgeInsets.zero, children: [
              SizedBox(
                  height: 470,
                  child: Stack(fit: StackFit.expand, children: [
                    if (bd != null)
                      Image.network('https://image.tmdb.org/t/p/w780$bd', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                    else if (i.poster != null)
                      ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: Image.network(i.poster!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black45, Colors.transparent, Colors.black], stops: [0, 0.45, 1]))),
                    SafeArea(
                        child: Align(
                            alignment: Alignment.topCenter,
                            child: Row(children: [
                              const BackButton(color: Colors.white),
                              const Spacer(),
                              IconButton(iconSize: 28, color: Colors.white, icon: const Icon(Icons.share_outlined), onPressed: () => Share.share('Check out ${i.title}${i.year.isEmpty ? '' : ' (${i.year})'} on Playbox. Rated ${i.rating.toStringAsFixed(1)}/10.')),
                              ListenableBuilder(
                                  listenable: app,
                                  builder: (_, __) => IconButton(iconSize: 30, color: Colors.white, icon: Icon(app.saved(i) ? Icons.bookmark : Icons.bookmark_border), onPressed: () => listSheet(context, i))),
                            ]))),
                    if (i.poster != null)
                      Positioned(left: 16, bottom: 12, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(i.poster!, width: 108, height: 162, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 108, height: 162)))),
                  ])),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 90),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 8, children: [
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFFFC107), borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star, size: 20, color: Colors.black), const SizedBox(width: 4), Text(i.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700))])),
                      Text(i.label.replaceAll('TV Show', 'Series'), style: grey),
                      if (i.year.isNotEmpty) Text(i.year, style: grey),
                      if (country.isNotEmpty) Text(country, style: grey),
                      if (votes != null) Text('$votes votes', style: grey),
                    ]),
                    const SizedBox(height: 18),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      FutureBuilder<String?>(
                          future: imdb(i),
                          builder: (_, s) => s.data == null
                              ? const SizedBox()
                              : Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFFFC107))), child: Text('IMDb ★ ${s.data}', style: const TextStyle(fontSize: 18, color: Color(0xFFFFC107))))),
                      for (final g in gens)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white54)), child: Text('$g', style: const TextStyle(fontSize: 18))),
                    ]),
                    sec('Storyline'),
                    Text(i.overview.isEmpty ? 'No description available.' : i.overview, style: const TextStyle(fontSize: 19, height: 1.5, color: Colors.white70)),
                    if (langsTxt.isNotEmpty) ...[sec('Languages'), Text(langsTxt, style: grey)],
                    if (dirL.isNotEmpty) ...[sec('Director'), people(context, dirL)],
                    if (castL.isNotEmpty) ...[sec('Cast'), people(context, castL)],
                    FutureBuilder<List<Item>>(
                        future: recsOf(d),
                        builder: (_, s) => (s.data ?? []).isEmpty
                            ? const SizedBox()
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                sec('You May Also Like'),
                                SizedBox(height: 168, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: s.data!.length, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (_, k) => Card1(s.data![k]))),
                              ])),
                  ])),
            ]),
          );
        },
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
        body: IndexedStack(index: tab, children: const [HomePage(), AnimeHome(), DownloadsPage(), SettingsPage()]),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
          NavigationDestination(icon: Icon(Icons.local_movies_outlined), selectedIcon: Icon(Icons.local_movies), label: 'Movie/Tv'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Anime'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ]),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final heroes = (app.data['Top Movies This Week'] ?? []).where((x) => x.poster != null).take(7).toList();
          return Stack(children: [
            ListView(padding: EdgeInsets.zero, children: [
              if (heroes.isNotEmpty) HeroCarousel(heroes) else const SizedBox(height: 360, child: Center(child: CircularProgressIndicator())),
              const SizedBox(height: 18),
              const ProviderRow(),
              if (app.hist.isNotEmpty) ContinueRail(List.of(app.hist)),
              for (final s in homeSecs) Rail(s),
              const SizedBox(height: 24),
            ]),
            const Positioned(top: 0, left: 0, right: 0, child: TopBar('Playbox')),
          ]);
        },
      );
}

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});
  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  String g = 'All', f = 'All', st = 'All';
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
      final r = st != 'All' ? await animeByStudio(st, page) : await anilist(genre: g == 'All' ? null : g, format: aFormats[f], page: page, sort: 'POPULARITY_DESC');
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
          chipRow(const ['All', 'MAPPA', 'Ufotable', 'Madhouse', 'Bones', 'Wit Studio', 'Kyoto Animation', 'Sunrise', 'Pierrot'], st, (v) {
            st = v;
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
  final fn = FocusNode();
  @override
  void initState() {
    super.initState();
    fn.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    fn.dispose();
    super.dispose();
  }

  Future<void> run(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final g = genres.keys.where((k) => k.toLowerCase() == q.trim().toLowerCase());
      final r = await Future.wait([tmdb('search/multi', {'query': q}, 'movie'), anilist(search: q), if (g.isNotEmpty) discover(g.first, 'All')]);
      results = [for (final x in r) ...x];
    } catch (_) {
      results = [];
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ac = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), boxShadow: fn.hasFocus ? [BoxShadow(color: ac.withOpacity(0.55), blurRadius: 16, spreadRadius: 1)] : []),
            child: TextField(
                focusNode: fn,
                textInputAction: TextInputAction.search,
                onSubmitted: run,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Title, actor, director or genre',
                    filled: true,
                    fillColor: const Color(0xFF111114),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFF2A2A30))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: ac))))),
        const SizedBox(height: 12),
        if (busy) const LinearProgressIndicator(),
        Expanded(
            child: results == null
                ? const Center(child: Text('Search and press enter'))
                : results!.isEmpty
                    ? const Center(child: Text('No results'))
                    : GridView.builder(gridDelegate: gridDelegate, itemCount: results!.length, itemBuilder: (_, i) => Card1(results![i], w: 120))),
      ]),
    );
  }
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

Widget tile(BuildContext c, IconData ic, String t, String? sub, VoidCallback on) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: Theme.of(c).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
    child: ListTile(
        onTap: on,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: Icon(ic),
        title: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: sub == null ? null : Text(sub),
        trailing: const Icon(Icons.chevron_right)));

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Center(child: Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
            const SizedBox(height: 20),
            tile(context, Icons.bookmark, 'My List', 'Your saved movies, series and anime', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('My List')), body: const ListsPage())))),
            const SizedBox(height: 14),
            const Text('Preferences', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Theme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                      segments: const [ButtonSegment(value: ThemeMode.system, label: Text('System')), ButtonSegment(value: ThemeMode.light, label: Text('Light')), ButtonSegment(value: ThemeMode.dark, label: Text('Dark'))],
                      selected: {app.mode},
                      onSelectionChanged: (s) => app.prefs(m: s.first)),
                  const SizedBox(height: 18),
                  const Text('Accent color', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(children: [
                    for (var i = 0; i < accents.length; i++)
                      GestureDetector(
                          onTap: () => app.prefs(a: i),
                          child: Container(margin: const EdgeInsets.only(right: 12), width: 36, height: 36, decoration: BoxDecoration(color: accents[i], shape: BoxShape.circle, border: Border.all(width: 3, color: app.accent == i ? Theme.of(context).colorScheme.onSurface : Colors.transparent)))),
                  ]),
                ])),
            const SizedBox(height: 22),
            const Text('App', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            tile(context, Icons.delete_outline, 'Clear My List', null, app.clearWl),
            tile(context, Icons.info_outline, 'About & Legal', null, () => showAboutDialog(context: context, applicationName: 'Playbox', applicationVersion: '1.0.0', children: const [Text('Data from TMDB, AniList and OMDb (IMDb ratings). This product uses the TMDB API but is not endorsed or certified by TMDB.')])),
            const SizedBox(height: 16),
            const Center(child: Text('Version 1.0.0', style: TextStyle(color: Colors.grey))),
          ]),
        ),
      );
}

// ---------- Full catalog page (infinite scroll) ----------
class SectionPage extends StatefulWidget {
  final String title;
  const SectionPage(this.title, {super.key});
  @override
  State<SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<SectionPage> {
  final items = <Item>[];
  int page = 1;
  bool busy = false, more = true;
  final sc = ScrollController();

  @override
  void initState() {
    super.initState();
    sc.addListener(() {
      if (sc.position.pixels > sc.position.maxScrollExtent - 400) fetch();
    });
    fetch();
  }

  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  Future<void> fetch() async {
    if (busy || !more) return;
    setState(() => busy = true);
    try {
      final r = await load(widget.title, page);
      final seen = items.map((x) => x.id).toSet();
      items.addAll(r.where((x) => seen.add(x.id)));
      page++;
      more = r.isNotEmpty && page <= 500;
    } catch (_) {
      more = false;
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: GridView.builder(
            controller: sc,
            padding: const EdgeInsets.all(16),
            gridDelegate: gridDelegate,
            itemCount: items.length + (busy ? 1 : 0),
            itemBuilder: (_, i) => i < items.length ? Card1(items[i], w: 120) : const Center(child: CircularProgressIndicator())),
      );
}

// ---------- Premium home pieces ----------
class TopBar extends StatelessWidget {
  final String title;
  const TopBar(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 6, left: 16, right: 4, bottom: 14),
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF22D3EE)])), child: const Icon(Icons.play_arrow_rounded, color: Colors.white)),
        Expanded(child: Center(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)))),
        IconButton(color: Colors.white, icon: const Icon(Icons.tune), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrowsePage()))),
        IconButton(color: Colors.white, icon: const Icon(Icons.search, size: 28), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Search')), body: const SearchPage())))),
      ]));
}

class ProviderRow extends StatelessWidget {
  const ProviderRow({super.key});
  static const cols = {'Prime Video': Color(0xFF00A8E1), 'Netflix': Color(0xFF1B1B1B), 'Sony LIV': Color(0xFF23233B), 'Crunchyroll': Color(0xFFF47521), 'JioHotstar': Color(0xFF4B2BE0)};
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 108,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        for (final e in cols.entries)
          Padding(
              padding: const EdgeInsets.only(right: 14),
              child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SectionPage(e.key))),
                  child: Column(children: [
                    CircleAvatar(radius: 34, backgroundColor: e.value, child: Text(e.key.split(' ').map((w) => w[0]).join(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                    const SizedBox(height: 6),
                    Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]))),
      ]));
}

class Top10Card extends StatelessWidget {
  final Item item;
  final int i;
  const Top10Card(this.item, this.i, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 196,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: -4, bottom: -22, child: Text('${i + 1}', style: TextStyle(fontSize: 150, height: 1, fontWeight: FontWeight.w900, foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white))),
        Positioned(right: 0, top: 0, child: Card1(item)),
      ]));
}

class Rail extends StatelessWidget {
  final String s;
  const Rail(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final top10 = s.startsWith('Top 10');
    final items = app.data[s];
    final err = app.errors[s];
    return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: Text(s, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                if (!top10)
                  InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SectionPage(s))), child: const Row(children: [Text('More', style: TextStyle(fontSize: 16)), Icon(Icons.chevron_right)])),
              ])),
          const SizedBox(height: 12),
          if (err != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Expanded(child: Text(err, maxLines: 3, overflow: TextOverflow.ellipsis)), TextButton(onPressed: () => app.fetch(s), child: const Text('Retry'))]))
          else if (items == null)
            const SizedBox(height: 168, child: Center(child: CircularProgressIndicator()))
          else
            SizedBox(
                height: top10 ? 190 : 168,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: top10 && items.length > 10 ? 10 : items.length,
                    separatorBuilder: (_, __) => SizedBox(width: top10 ? 6 : 12),
                    itemBuilder: (_, i) => top10 ? Top10Card(items[i], i) : Card1(items[i]))),
        ]));
  }
}

class HeroCarousel extends StatefulWidget {
  final List<Item> items;
  const HeroCarousel(this.items, {super.key});
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final pc = PageController();
  int i = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 6), (_) {
      if (pc.hasClients) pc.animateToPage((i + 1) % widget.items.length, duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  Widget slide(Item it) => GestureDetector(
        onTap: () => openDetail(context, it),
        child: Stack(fit: StackFit.expand, children: [
          Image.network(it.poster!.replaceFirst('/w500/', '/w780/'), fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF15151C))),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54, Colors.black], stops: [0.4, 0.75, 1]))),
          Positioned(
            left: 20,
            right: 20,
            bottom: 64,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text(it.label.toUpperCase(), style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700, letterSpacing: 2)),
                const SizedBox(width: 10),
                if (it.lang != null) Pill(it.lang!),
              ]),
              const SizedBox(height: 10),
              Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 10),
              Row(children: [
                Text(it.year, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                const Text('  •  ', style: TextStyle(color: Colors.white70)),
                const Icon(Icons.star, color: Color(0xFFFFC107), size: 20),
                Text(' ${it.rating.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white70, fontSize: 18)),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                PlayBtn(it, white: true),
                const SizedBox(width: 26),
                ListenableBuilder(
                    listenable: app,
                    builder: (_, __) => GestureDetector(
                        onTap: () => app.toggle(it),
                        child: Column(children: [Icon(app.saved(it) ? Icons.bookmark : Icons.bookmark_border, color: Colors.white70), const Text('My List', style: TextStyle(color: Colors.white70))]))),
              ]),
            ]),
          ),
          Positioned(
              right: 20,
              bottom: 26,
              child: Row(children: [
                Text('${(widget.items.indexOf(it) + 1).toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white70)),
                const SizedBox(width: 8),
                SizedBox(width: 110, height: 2, child: Stack(children: [Container(color: Colors.white24), FractionallySizedBox(widthFactor: (widget.items.indexOf(it) + 1) / widget.items.length, child: Container(color: Colors.white))])),
                const SizedBox(width: 8),
                Text(widget.items.length.toString().padLeft(2, '0'), style: const TextStyle(color: Colors.white70)),
              ])),
        ]),
      );

  @override
  Widget build(BuildContext context) => SizedBox(height: 560, child: PageView.builder(controller: pc, itemCount: widget.items.length, onPageChanged: (v) => setState(() => i = v), itemBuilder: (_, k) => slide(widget.items[k])));
}

class AnimeHome extends StatelessWidget {
  const AnimeHome({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final heroes = (app.data['Trending Anime'] ?? []).where((x) => x.poster != null).take(7).toList();
          return Stack(children: [
            ListView(padding: EdgeInsets.zero, children: [
              if (heroes.isNotEmpty) HeroCarousel(heroes) else const SizedBox(height: 360, child: Center(child: CircularProgressIndicator())),
              const SizedBox(height: 18),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: tile(context, Icons.tune, 'Browse by genre', 'Action, Romance, Mecha, Slice of Life and more', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Anime')), body: const AnimePage()))))),
              for (final s in animeSecs) Rail(s),
              const SizedBox(height: 24),
            ]),
            const Positioned(top: 0, left: 0, right: 0, child: TopBar('Anime')),
          ]);
        },
      );
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Downloads', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Videos you download appear here', style: TextStyle(color: Colors.grey)),
            const Expanded(child: Center(child: Icon(Icons.download_for_offline_outlined, size: 72, color: Colors.white24))),
          ])));
}

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String g = 'All', l = 'All', sort = 'Popular', year = 'All';
  List<Item> res = [];
  bool busy = false;
  int page = 1;
  @override
  void initState() {
    super.initState();
    go();
  }

  Future<void> go({bool more = false}) async {
    if (more) {
      page++;
    } else {
      page = 1;
      res = [];
    }
    setState(() => busy = true);
    try {
      res = [...res, ...await discover(g, l, page, sortMap[sort]!, year)];
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Browse')),
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              chipRow(['All', ...genres.keys], g, (v) {
                g = v;
                go();
              }),
              chipRow(['All', ...langs.keys], l, (v) {
                l = v;
                go();
              }),
              chipRow(sortMap.keys.toList(), sort, (v) {
                sort = v;
                go();
              }),
              chipRow(['All', for (var y = DateTime.now().year; y >= 2010; y--) '$y'], year, (v) {
                year = v;
                go();
              }),
              const SizedBox(height: 8),
              Expanded(
                  child: GridView.builder(
                      gridDelegate: gridDelegate,
                      itemCount: res.length + 1,
                      itemBuilder: (_, i) => i < res.length ? Card1(res[i], w: 120) : busy ? const Center(child: CircularProgressIndicator()) : Center(child: TextButton(onPressed: () => go(more: true), child: const Text('Load more'))))),
            ])),
      );
}

// ---------- Lists, history, filmography ----------
void listSheet(BuildContext context, Item i) {
  final ctl = TextEditingController();
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: ListenableBuilder(
              listenable: app,
              builder: (c, _) => SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Add to list', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    CheckboxListTile(contentPadding: EdgeInsets.zero, value: app.saved(i), title: const Text('My List'), onChanged: (_) => app.toggle(i)),
                    for (final n in app.lists.keys) CheckboxListTile(contentPadding: EdgeInsets.zero, value: app.inList(n, i), title: Text(n), onChanged: (_) => app.toggleIn(n, i)),
                    Row(children: [
                      Expanded(child: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'New list name'))),
                      TextButton(
                          onPressed: () {
                            app.newList(ctl.text);
                            ctl.clear();
                          },
                          child: const Text('Create')),
                    ]),
                  ])))));
}

class ListsPage extends StatefulWidget {
  const ListsPage({super.key});
  @override
  State<ListsPage> createState() => _ListsPageState();
}

class _ListsPageState extends State<ListsPage> {
  String sel = 'My List';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final names = ['My List', ...app.lists.keys];
        if (!names.contains(sel)) sel = 'My List';
        final items = sel == 'My List' ? app.wl : app.lists[sel]!;
        return Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: chipRow(names, sel, (v) => setState(() => sel = v))),
          if (sel != 'My List') TextButton.icon(onPressed: () => app.delList(sel), icon: const Icon(Icons.delete_outline), label: Text('Delete "$sel"')),
          Expanded(child: items.isEmpty ? const Center(child: Text('Nothing here yet')) : GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: gridDelegate, itemCount: items.length, itemBuilder: (_, k) => Card1(items[k], w: 120))),
        ]);
      });
}

class ContinueRail extends StatelessWidget {
  final List<Map<String, dynamic>> h;
  const ContinueRail(this.h, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Continue Watching', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
        const SizedBox(height: 12),
        SizedBox(
            height: 184,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: h.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, k) {
                  final it = Item.fromJson(Map<String, dynamic>.from(h[k]['i']));
                  final pr = ((h[k]['p'] as int) / (h[k]['d'] as int)).clamp(0.0, 1.0).toDouble();
                  return Column(children: [Card1(it), const SizedBox(height: 6), SizedBox(width: 112, child: LinearProgressIndicator(value: pr))]);
                })),
      ]));
}

class PersonPage extends StatelessWidget {
  final int id;
  final String name;
  const PersonPage(this.id, this.name, {super.key});
  Future<List<Item>> works() async {
    final r = await http.get(Uri.https('api.themoviedb.org', '/3/person/$id/combined_credits', {'api_key': tmdbKey}));
    final j = jsonDecode(r.body);
    final all = [...(j['cast'] ?? []) as List, ...(j['crew'] ?? []) as List].where((x) => x['poster_path'] != null && (x['media_type'] == 'movie' || x['media_type'] == 'tv')).toList();
    all.sort((a, b) => ((b['popularity'] ?? 0) as num).compareTo((a['popularity'] ?? 0) as num));
    final seen = <String>{};
    return all.map<Item>((x) => _toItem(x, '${x['media_type']}')).where((x) => seen.add(x.id)).take(60).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: FutureBuilder<List<Item>>(
            future: works(),
            builder: (_, s) => s.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : (s.data ?? []).isEmpty
                    ? const Center(child: Text('No titles found'))
                    : GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: gridDelegate, itemCount: s.data!.length, itemBuilder: (_, k) => Card1(s.data![k], w: 120))),
      );
}
