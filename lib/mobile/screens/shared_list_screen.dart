import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/app_palette.dart';
import '../../design/app_tokens.dart';
import '../../provider/named_lists_provider.dart';
import '../../services/shared_list_service.dart';
import '../widgets/page_kit.dart';
import '../widgets/pill_button.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_grid.dart';
import 'named_list_detail_screen.dart';

/// A named list opened from someone else's share link: read-only, with
/// the owner's name, and one action — saving a copy into the viewer's
/// own lists. The viewer can change nothing about the original; only
/// the owner can, from their own detail screen.
///
/// A link with no public snapshot behind it (private again, deleted,
/// or opened before the sharing rules were published) has nothing to
/// show, and says so rather than spinning forever.
class SharedListScreen extends StatelessWidget {
  const SharedListScreen({required this.listId, super.key});

  final String listId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<SharedListSnapshot?>(
      future: SharedListService.instance.fetchShared(listId),
      builder: (context, snapshot) {
        final shared = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: palette.page,
            appBar: PageAppBar(title: tr('my_lists')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (shared == null) {
          return Scaffold(
            backgroundColor: palette.page,
            appBar: PageAppBar(title: tr('my_lists')),
            body: SafeArea(
              child: EmptyState(
                icon: PhosphorIcons.listDashes(),
                title: tr('my_lists'),
                message: tr('shared_list_unavailable'),
              ),
            ),
          );
        }
        final list = shared.list;
        return Scaffold(
          backgroundColor: palette.page,
          appBar: PageAppBar(title: list.name),
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.gutter(context),
                    AppSpace.sm,
                    AppSpace.gutter(context),
                    0,
                  ),
                  child: Text(
                    tr('share_list_by', namedArgs: {'name': shared.ownerName}),
                    style: AppType.body.copyWith(color: palette.mutedText),
                  ),
                ),
                if (list.description.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.gutter(context),
                      AppSpace.sm,
                      AppSpace.gutter(context),
                      0,
                    ),
                    child: Text(
                      list.description,
                      style: AppType.body.copyWith(color: palette.mutedText),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.gutter(context),
                    AppSpace.md,
                    AppSpace.gutter(context),
                    AppSpace.sm,
                  ),
                  child: PillButton(
                    label: tr('save_a_copy'),
                    icon: PhosphorIcons.copy(),
                    primary: true,
                    onPressed: () => _saveCopy(context, shared),
                  ),
                ),
                if (list.items.isEmpty)
                  Expanded(
                    child: EmptyState(
                      icon: PhosphorIcons.listDashes(),
                      title: list.name,
                      message: tr('list_is_empty'),
                    ),
                  )
                else
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
                        final item = list.items[index].toMediaItem();
                        return LayoutBuilder(
                          builder: (context, constraints) => PosterCard(
                            item: item,
                            width: constraints.maxWidth,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveCopy(
    BuildContext context,
    SharedListSnapshot shared,
  ) async {
    final created =
        await context.read<NamedListsProvider>().saveSharedCopy(shared);
    if (!context.mounted || created == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('shared_list_saved'))));
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NamedListDetailScreen(listId: created.id),
      ),
    );
  }
}
