/// The languages with a regional Top 10 row on Home, in the order shown:
/// Malayalam, Tamil, Hindi, Telugu. The website's "Trending in your
/// language" rows are their other half.
///
/// Lives in its own file so both the home feed and the catalog controller
/// can use it: the home feed imports the catalog controller, so the enum
/// cannot live in the home feed file without an import cycle.
enum RegionalLanguage {
  malayalam('ml', 'Malayalam'),
  tamil('ta', 'Tamil'),
  hindi('hi', 'Hindi'),
  telugu('te', 'Telugu');

  const RegionalLanguage(this.code, this.name);

  /// TMDB's original-language code.
  final String code;

  /// The name shown in the row's title.
  final String name;
}
