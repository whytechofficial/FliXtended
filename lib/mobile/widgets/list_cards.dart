import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/app_palette.dart';
import '../../design/app_tokens.dart';
import '../../models/named_list.dart';
import '../../models/offline_download.dart';
import 'media_art.dart';
import 'poster_card.dart';

/// "3 titles" / "1 title" for a list, as the rows already say.
String listCountLabel(NamedList list) => list.items.length == 1
    ? tr('list_count_one')
    : tr(
        'list_count_many',
        namedArgs: <String, String>{'count': '${list.items.length}'},
      );

/// A list's cover: its first title's poster, or a quiet panel with a list
/// mark when the list is empty or the first title has no artwork.
class NamedListCover extends StatelessWidget {
  const NamedListCover({required this.list, super.key});

  final NamedList list;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final first = list.items.isEmpty ? null : list.items.first;
    return AspectRatio(
      aspectRatio: PosterCard.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: first == null
            ? ColoredBox(
                color: palette.surface,
                child: Center(
                  child: Icon(
                    PhosphorIcons.listDashes(),
                    color: palette.mutedText,
                    size: 28,
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    MediaArt(
                      item: first.toMediaItem(),
                      path: first.posterPath,
                      width: constraints.maxWidth,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: palette.hairline, width: .5),
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A list as a card for a sideways row: cover poster, name underneath,
/// count under that. Names run to two lines, then cut with an ellipsis.
class NamedListCard extends StatelessWidget {
  const NamedListCard({required this.list, required this.onTap, super.key});

  final NamedList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: posterWidth(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NamedListCover(list: list),
            const SizedBox(height: 6),
            Text(
              list.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(color: palette.foreground),
            ),
            Text(
              listCountLabel(list),
              style: AppType.metadata.copyWith(color: palette.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "+" card that ends a card row or grid: a poster-sized panel with a
/// plus mark. It takes whatever width its parent gives it, so a sideways
/// row wraps it in a poster-width box and a grid cell sizes it.
/// Opens the sheet that creates a list or imports one.
class NamedListPlusCard extends StatelessWidget {
  const NamedListPlusCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Pressable(
      semanticLabel: tr('new_list'),
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: PosterCard.aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: palette.hairline),
          ),
          child: Center(
            child: Icon(
              PhosphorIcons.plus(),
              color: palette.foreground,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// A list as a card inside the Add-to-list grid: cover poster, name
/// underneath cut with an ellipsis, and a tick badge on the poster when
/// the title is already in the list.
class NamedListSheetCard extends StatelessWidget {
  const NamedListSheetCard({
    required this.list,
    required this.contained,
    required this.onTap,
    super.key,
  });

  final NamedList list;
  final bool contained;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            children: <Widget>[
              NamedListCover(list: list),
              if (contained)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        PhosphorIcons.check(PhosphorIconsStyle.bold),
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            list.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(color: palette.foreground),
          ),
        ],
      ),
    );
  }
}

/// A sideways row of list cards with a "+" card at the end, as the
/// Your-lists section shows it on the tab.
class NamedListsCardRow extends StatelessWidget {
  const NamedListsCardRow({
    required this.lists,
    required this.onList,
    required this.onPlus,
    super.key,
  });

  final List<NamedList> lists;
  final void Function(NamedList list) onList;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final width = posterWidth(context);
    return SizedBox(
      height: width / PosterCard.aspectRatio + 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter(context)),
        itemCount: lists.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == lists.length) {
            return SizedBox(
              width: width,
              child: NamedListPlusCard(onTap: onPlus),
            );
          }
          final list = lists[index];
          return NamedListCard(list: list, onTap: () => onList(list));
        },
      ),
    );
  }
}

/// A sideways row of download cards, as the tab's Downloads section
/// shows it.
class DownloadsCardRow extends StatelessWidget {
  const DownloadsCardRow({
    required this.downloads,
    required this.onDownload,
    super.key,
  });

  final List<OfflineDownload> downloads;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final width = posterWidth(context);
    return SizedBox(
      height: width / PosterCard.aspectRatio + 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter(context)),
        itemCount: downloads.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => DownloadPosterCard(
          download: downloads[index],
          onTap: onDownload,
        ),
      ),
    );
  }
}

/// A download as a card for a sideways row: poster, title underneath, and
/// its status with progress, so nothing the old row said is lost.
class DownloadPosterCard extends StatelessWidget {
  const DownloadPosterCard({
    required this.download,
    required this.onTap,
    super.key,
  });

  final OfflineDownload download;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final failed = download.state == OfflineDownloadState.failed;
    // Always determinate: a failed or queued item must not look busy.
    final progress = download.isComplete
        ? 1.0
        : (download.progress / 100).clamp(0.0, 1.0).toDouble();
    final url = download.posterUrl;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: posterWidth(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: PosterCard.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: url == null || url.isEmpty
                    ? ColoredBox(
                        color: palette.surface,
                        child: Center(
                          child: Icon(
                            PhosphorIcons.filmSlate(),
                            color: palette.mutedText,
                            size: 28,
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            ColoredBox(color: palette.surface),
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: palette.surface,
                          child: Center(
                            child: Icon(
                              PhosphorIcons.filmSlate(),
                              color: palette.mutedText,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              download.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(color: palette.foreground),
            ),
            Text(
              download.isComplete
                  ? tr('download_status_completed')
                  : '${tr('download_status_${download.state.name}')} · ${download.progress.round()}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.metadata.copyWith(
                color: failed
                    ? Theme.of(context).colorScheme.error
                    : palette.mutedText,
              ),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(AppRadii.chip),
              backgroundColor: palette.idleFill,
            ),
          ],
        ),
      ),
    );
  }
}
