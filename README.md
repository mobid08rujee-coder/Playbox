# Playbox

A personal app for browsing trending movies, series and anime. It shows metadata only and does not host or stream any video.

## Features
- Sections: Hollywood, Bollywood, Anime, Series, K-Drama
- Search across movies, series and anime
- Watchlist saved on the device
- Light and dark themes, accent colors
- Playback and download preferences (audio language, subtitles, quality)

## Data sources
- Movies and TV: TMDB
- Anime: AniList

This product uses the TMDB API but is not endorsed or certified by TMDB.

## Build
1. Get a free TMDB API key (v3) at themoviedb.org.
2. Add it to this repo as a secret named `TMDB_KEY` (Settings → Secrets and variables → Actions).
3. Open the Actions tab, run **Build APK**, then download `playbox-apk` from the finished run.

To build locally instead:

```
flutter pub get
flutter run --dart-define=TMDB_KEY=YOUR_KEY
```

Android release builds need the INTERNET permission in `AndroidManifest.xml`. The GitHub workflow adds it for you.
