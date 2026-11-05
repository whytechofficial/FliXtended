import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/app_palette.dart';
import '../../design/app_tokens.dart';
import '../../models/named_list.dart';
import '../../provider/named_lists_provider.dart';
import '../../services/tmdb_list_import.dart';
import '../widgets/list_cards.dart';
import '../widgets/media_art.dart';
import '../widgets/named_list_dialogs.dart';
import '../widgets/page_kit.dart';
import 'named_list_detail_screen.dart';

/// Every named list, past the four the My screen shows inline. Reached
/// from the lists section's See all link once there are five or more.
/// The rows carry each list's cover thumbnail; creating and importing
/// work from the "+" icon at the top right, through the same sheet the
/// tab's "+" card opens.
class NamedListsScreen extends StatelessWidget {
  const NamedListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final namedLists = context.watch<NamedListsProvider>();
    return Scaffold(
      backgroundColor: palette.page,
      appBar: PageAppBar(
        title: tr('my_lists'),
        actions: <Widget>[
          IconButton(
            icon: Icon(PhosphorIcons.plus()),
            onPressed: () => showNamedListPlusSheet(
              context,
              onNewList: () => _createList(context),
              onImport: () => _importList(context),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(
            top: AppSpace.md,
            bottom: AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            if (namedLists.lists.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpace.gutter(context),
                  vertical: AppSpace.md,
                ),
                child: Text(
                  tr('no_lists_yet'),
                  style: AppType.body.copyWith(color: palette.mutedText),
                ),
              )
            else
              for (final list in namedLists.lists)
                ListRow(
                  leading: _ListThumbnail(list: list),
                  label: list.name,
                  subtitle: list.description.isNotEmpty
                      ? list.description
                      : listCountLabel(list),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => NamedListDetailScreen(listId: list.id),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _createList(BuildContext context) async {
    final form = await showNamedListNameDialog(
      context,
      title: tr('new_list'),
      confirmLabel: tr('create'),
    );
    if (form == null || !context.mounted) return;
    final created = await context.read<NamedListsProvider>().createList(
          form.name,
          description: form.description,
        );
    if (created == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NamedListDetailScreen(listId: created.id),
      ),
    );
  }

  Future<void> _importList(BuildContext context) async {
    final link = await showImportTmdbListDialog(context);
    if (link == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final list = await importListFromLink(context, link);
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NamedListDetailScreen(listId: list.id),
        ),
      );
    } on TmdbListImportException catch (error) {
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              tr(switch (error.error) {
                TmdbListImportError.invalidLink => 'import_invalid_link',
                TmdbListImportError.fetchFailed => 'import_failed',
                TmdbListImportError.emptyList => 'import_empty_list',
              }),
            ),
          ),
        );
    } catch (_) {
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('import_failed'))));
    }
  }
}

/// A list's cover thumbnail for a full-page row: the first title's
/// poster, or a list mark when the list is empty.
class _ListThumbnail extends StatelessWidget {
  const _ListThumbnail({required this.list});

  final NamedList list;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final first = list.items.isEmpty ? null : list.items.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: SizedBox(
        width: 44,
        height: 66,
        child: first == null
            ? ColoredBox(
                color: palette.surface,
                child: Icon(
                  PhosphorIcons.listDashes(),
                  color: palette.mutedText,
                  size: 22,
                ),
              )
            : MediaArt(
                item: first.toMediaItem(),
                path: first.posterPath,
                width: 44,
              ),
      ),
    );
  }
}
