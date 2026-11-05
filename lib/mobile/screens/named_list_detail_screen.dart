import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../catalog/media_item.dart';
import '../../design/app_palette.dart';
import '../../design/app_tokens.dart';
import '../../provider/named_lists_provider.dart';
import '../widgets/named_list_dialogs.dart';
import '../widgets/page_kit.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_grid.dart';

/// One named list: its titles as posters, each with a remove button.
/// Tapping a poster opens its details, as everywhere else; the list
/// itself is renamed and deleted from the actions above.
class NamedListDetailScreen extends StatelessWidget {
  const NamedListDetailScreen({required this.listId, super.key});

  final String listId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lists = context.watch<NamedListsProvider>();
    final list = lists.listById(listId);

    return Scaffold(
      backgroundColor: palette.page,
      appBar: PageAppBar(
        title: list?.name ?? tr('my_lists'),
        actions: list == null
            ? null
            : <Widget>[
                IconButton(
                  tooltip: tr('share_list'),
                  color: palette.mutedText,
                  icon: Icon(PhosphorIcons.shareNetwork()),
                  onPressed: () => showListShareSheet(context, list),
                ),
                IconButton(
                  tooltip: tr('rename_list'),
                  color: palette.mutedText,
                  icon: Icon(PhosphorIcons.pencilSimple()),
                  onPressed: () =>
                      _rename(context, list.name, list.description),
                ),
                IconButton(
                  tooltip: tr('delete_list'),
                  color: palette.mutedText,
                  icon: Icon(PhosphorIcons.trash()),
                  onPressed: () => _delete(context, list.name),
                ),
              ],
      ),
      body: SafeArea(
        bottom: false,
        child: list == null
            ? EmptyState(
                icon: PhosphorIcons.listDashes(),
                title: tr('my_lists'),
                message: tr('list_not_found'),
              )
            : list.items.isEmpty
                ? EmptyState(
                    icon: PhosphorIcons.listDashes(),
                    title: list.name,
                    message: tr('list_is_empty'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (list.description.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            AppSpace.gutter(context),
                            AppSpace.sm,
                            AppSpace.gutter(context),
                            AppSpace.sm,
                          ),
                          child: Text(
                            list.description,
                            style:
                                AppType.body.copyWith(color: palette.mutedText),
                          ),
                        ),
                      Expanded(
                        child: GridView.builder(
                          padding: EdgeInsets.fromLTRB(
                            AppSpace.gutter(context),
                            AppSpace.sm,
                            AppSpace.gutter(context),
                            AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                          ),
                          gridDelegate: posterGridDelegate(context),
                          itemCount: list.items.length,
                          itemBuilder: (context, index) {
                            final entry = list.items[index];
                            final item = entry.toMediaItem();
                            return LayoutBuilder(
                              builder: (context, constraints) => Stack(
                                children: <Widget>[
                                  PosterCard(
                                    item: item,
                                    width: constraints.maxWidth,
                                  ),
                                  PositionedDirectional(
                                    top: 6,
                                    end: 6,
                                    child: _RemoveButton(
                                      onPressed: () =>
                                          _remove(context, list.id, item),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    String currentName,
    String currentDescription,
  ) async {
    final form = await showNamedListNameDialog(
      context,
      title: tr('rename_list'),
      confirmLabel: tr('save'),
      initialName: currentName,
      initialDescription: currentDescription,
    );
    if (form == null || !context.mounted) return;
    await context.read<NamedListsProvider>().updateListDetails(
          listId,
          form.name,
          form.description,
        );
  }

  Future<void> _delete(BuildContext context, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: PhosphorIcons.trash(),
      title: tr('delete_list'),
      message: tr(
        'delete_list_message',
        namedArgs: <String, String>{'name': name},
      ),
      confirmLabel: tr('delete'),
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<NamedListsProvider>().deleteList(listId);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _remove(
    BuildContext context,
    String listId,
    MediaItem item,
  ) async {
    await context.read<NamedListsProvider>().removeFromList(
          listId,
          item.kind,
          item.id,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('removed_from_list')),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

/// The small close button over a poster. A plain icon would vanish on a
/// bright poster, so it sits on a dimmed circle.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
