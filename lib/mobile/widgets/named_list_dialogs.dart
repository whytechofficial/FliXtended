import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../catalog/media_item.dart';
import '../../design/app_palette.dart';
import '../../design/app_tokens.dart';
import '../../models/named_list.dart';
import '../../provider/named_lists_provider.dart';
import '../../services/imdb_list_import.dart';
import '../../services/media_link.dart';
import '../../services/shared_list_service.dart';
import '../../services/tmdb_list_import.dart';
import '../screens/imdb_import_screen.dart';
import 'list_cards.dart';
import 'media_art.dart' show posterWidth;
import 'pill_button.dart';

/// The prompts for named lists: a name field for creating and renaming,
/// a link field for importing a public TMDB list, and the sheet that puts
/// a title into lists. Each returns what was entered, or null when
/// dismissed; the caller does the work and says what happened.

/// A name and a description for a list, starting from [initialName]
/// and [initialDescription] when editing. Null for a blank name or a
/// dismissed dialog. The description is upstream's "Add a description"
/// field: optional, shown under the list wherever lists are listed.
Future<({String name, String description})?> showNamedListNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? initialName,
  String? initialDescription,
}) {
  final controller = TextEditingController(text: initialName ?? '');
  final descriptionController =
      TextEditingController(text: initialDescription ?? '');
  ({String name, String description})? read() {
    final name = controller.text.trim();
    if (name.isEmpty) return null;
    return (name: name, description: descriptionController.text.trim());
  }

  return showDialog<({String name, String description})>(
    context: context,
    builder: (dialogContext) {
      final palette = AppPalette.of(dialogContext);
      return Dialog(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.hero),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.xxl,
              AppSpace.xl,
              AppSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppType.sectionHeader.copyWith(
                    fontFamily: AppType.bold,
                    color: palette.foreground,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppType.body.copyWith(color: palette.foreground),
                  decoration: InputDecoration(
                    hintText: tr('list_name_hint'),
                    hintStyle: AppType.body.copyWith(color: palette.mutedText),
                  ),
                  onSubmitted: (_) => Navigator.pop(dialogContext, read()),
                ),
                const SizedBox(height: AppSpace.lg),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppType.body.copyWith(color: palette.foreground),
                  decoration: InputDecoration(
                    hintText: tr('playlist_description'),
                    hintStyle: AppType.body.copyWith(color: palette.mutedText),
                  ),
                  onSubmitted: (_) => Navigator.pop(dialogContext, read()),
                ),
                const SizedBox(height: AppSpace.xxl),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PillButton(
                        label: tr('cancel'),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: PillButton(
                        label: confirmLabel,
                        primary: true,
                        onPressed: () => Navigator.pop(dialogContext, read()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A public TMDB list link to import. Null for a blank link or a
/// dismissed dialog; the caller parses it and reports failures.
Future<String?> showImportTmdbListDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final palette = AppPalette.of(dialogContext);
      return Dialog(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.hero),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.xxl,
              AppSpace.xl,
              AppSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tr('import_tmdb_list'),
                  style: AppType.sectionHeader.copyWith(
                    fontFamily: AppType.bold,
                    color: palette.foreground,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  tr('import_tmdb_list_note'),
                  style: AppType.body.copyWith(color: palette.mutedText),
                ),
                const SizedBox(height: AppSpace.lg),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  style: AppType.body.copyWith(color: palette.foreground),
                  decoration: InputDecoration(
                    hintText: tr('tmdb_list_link_hint'),
                    hintStyle: AppType.body.copyWith(color: palette.mutedText),
                  ),
                  onSubmitted: (_) {
                    final link = controller.text.trim();
                    Navigator.pop(dialogContext, link.isEmpty ? null : link);
                  },
                ),
                const SizedBox(height: AppSpace.xxl),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PillButton(
                        label: tr('cancel'),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: PillButton(
                        label: tr('import'),
                        primary: true,
                        onPressed: () {
                          final link = controller.text.trim();
                          Navigator.pop(
                            dialogContext,
                            link.isEmpty ? null : link,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The "+" sheet: exactly two options, used by the Your-lists card row's
/// "+" card and the full page's "+" icon. The callers' own create/import
/// flows run after the sheet closes, so this file never needs the detail
/// screen and no import cycle forms.
Future<void> showNamedListPlusSheet(
  BuildContext context, {
  required VoidCallback onNewList,
  required VoidCallback onImport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: AppSpace.md),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.mutedText,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                PhosphorIcons.plus(),
                color: palette.foreground,
              ),
              title: Text(
                tr('new_list'),
                style: AppType.body.copyWith(color: palette.foreground),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onNewList();
              },
            ),
            ListTile(
              leading: Icon(
                PhosphorIcons.downloadSimple(),
                color: palette.foreground,
              ),
              title: Text(
                tr('import_from_tmdb_imdb'),
                style: AppType.body.copyWith(color: palette.foreground),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onImport();
              },
            ),
            const SizedBox(height: AppSpace.md),
          ],
        ),
      );
    },
  );
}

/// Imports [link] the way [NamedListsProvider.importFromLink] does,
/// except an IMDb link goes through the browser import screen: IMDb
/// bot-walls plain requests, so only a real browser engine reads its
/// list pages. Same contract otherwise — the created list, or a
/// [TmdbListImportException] the caller reports as before. Backing out
/// of the browser screen reports as a failed fetch: there is no
/// cancelled error, and adding one would need a new user-facing string.
Future<NamedList> importListFromLink(BuildContext context, String link) async {
  if (ImdbListImport.parseId(link) != null) {
    final result = await Navigator.of(context).push<ImdbImportResult>(
      MaterialPageRoute<ImdbImportResult>(
        builder: (_) => ImdbImportScreen(link: link),
      ),
    );
    if (result?.list != null) return result!.list!;
    throw result?.error ??
        const TmdbListImportException(TmdbListImportError.fetchFailed);
  }
  return context.read<NamedListsProvider>().importFromLink(link);
}

/// The lists [item] can go into, as cards with a tick badge on the ones
/// already holding it, plus a "+" card that creates a list and puts the
/// title straight into it. Tapping a card toggles it and stays open, so
/// several lists can be ticked in one visit; the sheet closes from the
/// handle or the back gesture.
Future<void> showAddToListSheet(BuildContext context, MediaItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: AppSpace.md),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.mutedText,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter(sheetContext),
                  AppSpace.lg,
                  AppSpace.gutter(sheetContext),
                  AppSpace.sm,
                ),
                child: Text(
                  tr('add_to_list'),
                  style: AppType.sectionHeader.copyWith(
                    fontFamily: AppType.bold,
                    color: palette.foreground,
                  ),
                ),
              ),
              Flexible(
                child: Consumer<NamedListsProvider>(
                  builder: (context, lists, _) {
                    final containingIds = lists
                        .listsContaining(item)
                        .map((list) => list.id)
                        .toSet();
                    Future<void> createAndAdd() async {
                      final form = await showNamedListNameDialog(
                        sheetContext,
                        title: tr('new_list'),
                        confirmLabel: tr('create'),
                      );
                      if (form == null) return;
                      final created = await lists.createList(
                        form.name,
                        description: form.description,
                      );
                      if (created != null) {
                        await lists.addToList(created.id, item);
                      }
                    }

                    if (lists.lists.isEmpty) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpace.gutter(context),
                                vertical: AppSpace.lg,
                              ),
                              child: Text(
                                tr('no_lists_yet'),
                                style: AppType.body
                                    .copyWith(color: palette.mutedText),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpace.gutter(context),
                              ),
                              child: SizedBox(
                                width: posterWidth(context),
                                child: NamedListPlusCard(onTap: createAndAdd),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpace.gutter(context),
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.50,
                      ),
                      itemCount: lists.lists.length + 1,
                      itemBuilder: (context, index) {
                        if (index == lists.lists.length) {
                          return NamedListPlusCard(onTap: createAndAdd);
                        }
                        final list = lists.lists[index];
                        return NamedListSheetCard(
                          list: list,
                          contained: containingIds.contains(list.id),
                          onTap: () async {
                            if (containingIds.contains(list.id)) {
                              await lists.removeFromList(
                                list.id,
                                item.kind,
                                item.id,
                              );
                            } else {
                              await lists.addToList(list.id, item);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      );
    },
  );
}

/// The share sheet for one named list: a public/private toggle, the
/// link, and copy/share actions.
///
/// Public means a snapshot of the list lives in the public collection
/// for anyone with the link: they see its name, its titles and the
/// owner's name, and can save a copy. Only the owner can change it.
/// Private means no snapshot exists and the link opens nothing.
///
/// The toggle reads this device's flag first, then the cloud copy when
/// signed in, so a toggle made on another device is not contradicted
/// by stale state here.
Future<void> showListShareSheet(BuildContext context, NamedList list) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _ListShareSheet(list: list),
  );
}

class _ListShareSheet extends StatefulWidget {
  const _ListShareSheet({required this.list});

  final NamedList list;

  @override
  State<_ListShareSheet> createState() => _ListShareSheetState();
}

class _ListShareSheetState extends State<_ListShareSheet> {
  bool _isPublic = false;
  bool _busy = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _resolvePublic();
  }

  Future<void> _resolvePublic() async {
    var isPublic = false;
    try {
      isPublic = await SharedListService.instance.isPublic(widget.list.id);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        isPublic = await SharedListService.instance
            .isSharedOnCloud(widget.list.id, user.uid);
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isPublic = isPublic;
        _checking = false;
      });
    }
  }

  String get _url => MediaLink.sharedListUrl(widget.list.id).toString();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        final published =
            await SharedListService.instance.publish(widget.list);
        if (!published) {
          _snack(tr('playlist_share_sign_in'));
          return;
        }
        setState(() => _isPublic = true);
      } else {
        final unpublished =
            await SharedListService.instance.unpublish(widget.list.id);
        if (!unpublished) {
          _snack(tr('share_list_failed'));
          return;
        }
        setState(() => _isPublic = false);
      }
    } catch (_) {
      _snack(tr('share_list_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: AppSpace.md),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.mutedText,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter(context),
              AppSpace.lg,
              AppSpace.gutter(context),
              AppSpace.sm,
            ),
            child: Text(
              tr('share_list'),
              style: AppType.sectionHeader.copyWith(
                fontFamily: AppType.bold,
                color: palette.foreground,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter(context)),
            child: Text(
              tr('share_list_explanation'),
              style: AppType.body.copyWith(color: palette.mutedText),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SwitchListTile(
            title: Text(
              tr('share_list_public'),
              style: AppType.body.copyWith(color: palette.foreground),
            ),
            value: _isPublic,
            onChanged: _checking || _busy ? null : _toggle,
            activeThumbColor: palette.focusFill,
          ),
          if (_isPublic) ...<Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter(context),
                AppSpace.sm,
                AppSpace.gutter(context),
                AppSpace.sm,
              ),
              child: SelectableText(
                _url,
                style: AppType.body.copyWith(color: palette.foreground),
              ),
            ),
            ListTile(
              leading: Icon(
                PhosphorIcons.copy(),
                color: palette.foreground,
              ),
              title: Text(
                tr('copy_link'),
                style: AppType.body.copyWith(color: palette.foreground),
              ),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _url));
                _snack(tr('link_copied'));
              },
            ),
            ListTile(
              leading: Icon(
                PhosphorIcons.shareNetwork(),
                color: palette.foreground,
              ),
              title: Text(
                tr('share'),
                style: AppType.body.copyWith(color: palette.foreground),
              ),
              onTap: () => Share.share(
                tr(
                  'share_list_message',
                  namedArgs: <String, String>{
                    'name': widget.list.name,
                    'url': _url,
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
        ],
      ),
    );
  }
}
