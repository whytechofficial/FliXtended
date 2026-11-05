import '../catalog/media_item.dart';

/// A named list of titles, and one entry in it.
///
/// A list is the user's own grouping — "Rainy day films", "To watch with
/// family" — as opposed to My List, which is the one flat bookmark set.
/// An entry keeps the display fields its row needs, so a list renders
/// without refetching every title. The maps are the storage shape, shared
/// by the local database now and by sync later, so neither side invents
/// its own.
class NamedList {
  NamedList({
    required this.id,
    required this.name,
    required this.createdAt,
    String? updatedAt,
    this.description = '',
    this.items = const <NamedListItem>[],
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String name;
  final String createdAt;

  /// A short note on what the list is for, as upstream's New list sheet
  /// offers with "Add a description". Empty when the user wrote none.
  final String description;

  /// The last rename, in UTC so two devices compare it the same way
  /// whatever their timezones are. It is the only thing a sync conflict
  /// over the name looks at: item changes union, so they never need it.
  final String updatedAt;
  final List<NamedListItem> items;

  NamedList copyWith({
    String? name,
    String? description,
    String? updatedAt,
    List<NamedListItem>? items,
  }) =>
      NamedList(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        description: description ?? this.description,
        items: items ?? this.items,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'items': items.map((item) => item.toMap(id)).toList(),
      };

  static NamedList fromMap(
    Map<String, Object?> map, [
    List<NamedListItem>? items,
  ]) {
    final rawItems = map['items'];
    final parsedItems = items ??
        (rawItems is List
            ? rawItems
                .whereType<Map<String, Object?>>()
                .map(NamedListItem.fromMap)
                .toList()
            : const <NamedListItem>[]);
    return NamedList(
      id: map['id'] as String,
      name: map['name'] as String,
      // Lists written before descriptions existed, and cloud documents
      // from older builds, carry no description key at all.
      description: map['description'] as String? ?? '',
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String?,
      items: parsedItems,
    );
  }
}

class NamedListItem {
  NamedListItem({
    required this.kind,
    required this.tmdbId,
    required this.title,
    required this.dateAdded,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.releaseDate,
    this.rating,
  });

  /// A title on its way into a list, from a row the app already shows.
  factory NamedListItem.fromMediaItem(MediaItem item) => NamedListItem(
        kind: item.kind,
        tmdbId: item.id,
        title: item.title,
        posterPath: item.posterPath,
        backdropPath: item.backdropPath,
        overview: item.overview,
        releaseDate: item.releaseDate,
        rating: item.rating?.toDouble(),
        dateAdded: DateTime.now().toString(),
      );

  final MediaKind kind;
  final int tmdbId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final String? releaseDate;
  final double? rating;

  /// Stored as DateTime.toString(), which sorts as text, as My List does.
  final String dateAdded;

  Map<String, Object?> toMap(String listId) => <String, Object?>{
        'list_id': listId,
        'kind': kind.name,
        'tmdb_id': tmdbId,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'overview': overview,
        'release_date': releaseDate,
        'vote_average': rating,
        'date_added': dateAdded,
      };

  static NamedListItem fromMap(Map<String, Object?> map) => NamedListItem(
        kind: MediaKind.values.byName(map['kind'] as String),
        tmdbId: map['tmdb_id'] as int,
        title: map['title'] as String,
        posterPath: map['poster_path'] as String?,
        backdropPath: map['backdrop_path'] as String?,
        overview: map['overview'] as String?,
        releaseDate: map['release_date'] as String?,
        rating: (map['vote_average'] as num?)?.toDouble(),
        dateAdded: map['date_added'] as String,
      );

  MediaItem toMediaItem() => MediaItem(
        kind: kind,
        id: tmdbId,
        title: title,
        overview: overview ?? '',
        posterPath: posterPath,
        backdropPath: backdropPath,
        rating: rating?.toDouble(),
        releaseDate: releaseDate,
      );
}
