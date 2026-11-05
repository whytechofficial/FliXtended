import 'names.dart';

/// A title's category for provider ordering: what its production
/// country and genre say it is, so the sources most likely to carry it
/// are tried first. Anything unrecognized stays general and keeps the
/// configured order untouched.
enum TitleCategory { general, indian, anime, turkish }

/// The category of a title from its production countries, genres and
/// languages, all as names ("India", "Animation", "Japanese") — the
/// shape the playback metadata carries them in. Codes ("IN", "ja")
/// are accepted too, in case a caller passes those instead.
///
/// Indian wins over anime over Turkish when a title matches more than
/// one, following the order the categories were asked for; in practice
/// the sets barely overlap, since anime also needs a Japanese origin
/// or language.
TitleCategory categoryForTitle({
  required List<String> countries,
  required List<String> genres,
  required List<String> languages,
}) {
  final countrySet = countries
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  final genreSet = genres
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  final languageSet = languages
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (countrySet.contains('india') || countrySet.contains('in')) {
    return TitleCategory.indian;
  }
  final isAnimation = genreSet.contains('animation');
  final isJapanese = countrySet.contains('japan') ||
      countrySet.contains('jp') ||
      languageSet.contains('japanese') ||
      languageSet.contains('ja');
  if (isAnimation && isJapanese) return TitleCategory.anime;
  if (countrySet.contains('turkey') || countrySet.contains('tr')) {
    return TitleCategory.turkish;
  }
  return TitleCategory.general;
}

/// The providers tried first for each category, by codeName, in try
/// order. Metemma has no baked-in codeName — the backend advertises it
/// under that display name — so it is matched by name, after Maychew,
/// in the order the server status screen lists the anime sources.
const Map<TitleCategory, List<String>> _categoryPriorityCodes =
    <TitleCategory, List<String>>{
  TitleCategory.indian: <String>[
    'scraper:aethoflix', // Karamara
    'direct:castle', // Hampi
    'direct:netmirror', // Nalanda
    'direct:mxplayer', // Dholavira
  ],
  TitleCategory.anime: <String>[
    'scraper:animekai', // Lalibela
    'scraper:animeyy', // Magdala
    'scraper:animepahe', // Maychew
  ],
  TitleCategory.turkish: <String>[
    'scraper:yoturkish', // Sebastopol
  ],
};

/// Re-sorts [ordered] so a title's category providers come first, in
/// their priority order, with every other provider following in its
/// existing relative order. Nothing is hidden: a priority provider
/// that is down simply falls through to the rest, as before. A
/// general title returns the input order unchanged.
List<VideoProvider> applyCategoryOrder(
  List<VideoProvider> ordered, {
  required List<String> countries,
  required List<String> genres,
  required List<String> languages,
}) {
  final category = categoryForTitle(
    countries: countries,
    genres: genres,
    languages: languages,
  );
  if (category == TitleCategory.general) return ordered;
  final remaining = ordered.toList(growable: true);
  final first = <VideoProvider>[];
  for (final code in _categoryPriorityCodes[category]!) {
    final index = remaining.indexWhere((provider) => provider.codeName == code);
    if (index >= 0) first.add(remaining.removeAt(index));
  }
  if (category == TitleCategory.anime) {
    final index = remaining.indexWhere(
      (provider) => provider.displayName.trim().toLowerCase() == 'metemma',
    );
    if (index >= 0) first.add(remaining.removeAt(index));
  }
  return <VideoProvider>[...first, ...remaining];
}
