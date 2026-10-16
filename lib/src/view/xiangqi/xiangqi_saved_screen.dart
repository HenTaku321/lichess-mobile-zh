import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/saved/xiangqi_saved.dart';
import 'package:lichess_mobile/src/model/xiangqi/saved/xiangqi_saved_repository.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:material_ui/material_ui.dart';

/// The account's own content on xiangqi.com: the puzzles it has created and the notes it has saved,
/// each in a folder tree of its own.
///
/// ## What this is, and what it is not
///
/// It is the **library**, not the content. The puzzles are made in the board editor and published
/// through `puzzle/create`, and the notes are what a review can save — neither of which this app
/// does yet — so the library this screen draws is a library that is empty until one of those
/// arrives. What it does do is the whole of the folder tree: make, rename, delete, and look inside,
/// which is the machinery both of them will need.
///
/// ## The two vocabularies
///
/// A folder is filed under a **slug** in the URL (`puzzle`, `game_note`) and created with a
/// **number** in the body (`2`, `3`), and neither is derivable from the other — see
/// [XiangqiSavedKind]. The shipped client's own map spells the second slug `note`, which the server
/// answers `400 Invalid item type`; the wire's spelling is the one this app uses.
class const XiangqiSavedScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiSavedScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(xiangqiAuthControllerProvider)?.name;

    return DefaultTabController(
      length: XiangqiSavedKind.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitleText(
            '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiSaved}',
          ),
          bottom: TabBar(
            tabs: [
              for (final kind in XiangqiSavedKind.values) Tab(text: _kindLabel(context, kind)),
            ],
          ),
        ),
        body: username == null
            ? Center(
                child: Padding(
                  padding: Styles.bodySectionPadding,
                  child: Text(context.l10n.mobileXiangqiSignIn, textAlign: TextAlign.center),
                ),
              )
            : TabBarView(
                children: [
                  for (final kind in XiangqiSavedKind.values)
                    _KindTab(username: username, kind: kind),
                ],
              ),
      ),
    );
  }
}

/// One kind of content: its folders, and what is at the root of its tree.
class const _KindTab({required final String username, required final XiangqiSavedKind kind})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(xiangqiSavedFoldersProvider((username, kind, null)));

    return RefreshIndicator.adaptive(
      onRefresh: () => Future.wait<Object?>([
        // The folders and the content are two questions, and a pull asks both: a folder made on
        // another device is as much a reason to pull as a puzzle made on one.
        ref.refresh(xiangqiSavedFoldersProvider((username, kind, null)).future),
        switch (kind) {
          XiangqiSavedKind.puzzle => ref.refresh(xiangqiSavedPuzzlesProvider(username).future),
          XiangqiSavedKind.note => ref.refresh(xiangqiSavedNotesProvider(username).future),
        },
      ]),
      child: ListView(
        children: [
          ListSection(
            hasLeading: true,
            header: Text(context.l10n.mobileXiangqiSavedNewFolder),
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(context.l10n.mobileXiangqiSavedNewFolder),
                onTap: () => _makeFolder(context, ref, username, kind),
              ),
            ],
          ),
          switch (folders) {
            AsyncData(:final value) when value.folders.isNotEmpty => ListSection(
              hasLeading: true,
              children: [
                for (final folder in value.folders)
                  _FolderRow(folder: folder, username: username, kind: kind),
              ],
            ),
            AsyncError() => ListSection(
              hasLeading: true,
              children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
            ),
            _ => const ListSection(
              hasLeading: true,
              children: [ListTile(dense: true, title: Text('…'))],
            ),
          },
          if (kind == XiangqiSavedKind.puzzle)
            _Puzzles(username: username)
          else
            _Notes(username: username),
        ],
      ),
    );
  }
}

/// One folder: its name, and the two things that can be done to it.
class const _FolderRow({
  required final XiangqiSavedFolder folder,
  required final String username,
  required final XiangqiSavedKind kind,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l10n.mobileXiangqiSavedRename,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _renameFolder(context, ref, username, kind, folder),
          ),
          IconButton(
            tooltip: context.l10n.mobileXiangqiSavedDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteFolder(context, ref, username, kind, folder),
          ),
        ],
      ),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiSavedFolderScreen.buildRoute(username, kind, folder)),
    );
  }
}

/// What is inside one folder.
class const XiangqiSavedFolderScreen({
  required final String username,
  required final XiangqiSavedKind kind,
  required final XiangqiSavedFolder folder,
  super.key,
}) extends ConsumerWidget {
  static Route<void> buildRoute(
    String username,
    XiangqiSavedKind kind,
    XiangqiSavedFolder folder,
  ) => buildScreenRoute(
    screen: XiangqiSavedFolderScreen(username: username, kind: kind, folder: folder),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(xiangqiSavedFoldersProvider((username, kind, folder.id)));

    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(folder.name)),
      body: folders.when(
        data: (folders) => folders.folders.isEmpty
            ? Center(
                child: Padding(
                  padding: Styles.bodySectionPadding,
                  child: Text(context.l10n.mobileXiangqiSavedEmpty),
                ),
              )
            : ListView(
                children: [
                  ListSection(
                    hasLeading: true,
                    children: [
                      for (final child in folders.folders)
                        _FolderRow(folder: child, username: username, kind: kind),
                    ],
                  ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: Styles.bodySectionPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
                const SizedBox(height: 16.0),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(xiangqiSavedFoldersProvider((username, kind, folder.id))),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The puzzles this account has created.
class const _Puzzles({required final String username}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(xiangqiSavedPuzzlesProvider(username))
        .when(
          data: (puzzles) => ListSection(
            hasLeading: true,
            header: Text(context.l10n.mobileXiangqiSavedPuzzles),
            children: [
              if (puzzles.puzzles.isEmpty)
                ListTile(dense: true, title: Text(context.l10n.mobileXiangqiSavedEmpty))
              else
                for (final puzzle in puzzles.puzzles)
                  ListTile(
                    dense: true,
                    title: Text(puzzle.id),
                    subtitle: Text(
                      [
                        if (puzzle.rating != null) '${puzzle.rating}',
                        if (puzzle.createdOn != null) puzzle.createdOn!,
                      ].join(' · '),
                    ),
                  ),
            ],
          ),
          loading: () => ListSection.loading(itemsNumber: 3, header: true, hasLeading: true),
          error: (error, stackTrace) => ListSection(
            hasLeading: true,
            header: Text(context.l10n.mobileXiangqiSavedPuzzles),
            children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
          ),
        );
  }
}

/// The notes this account has saved.
class const _Notes({required final String username}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(xiangqiSavedNotesProvider(username))
        .when(
          data: (notes) => ListSection(
            hasLeading: true,
            header: Text(context.l10n.mobileXiangqiSavedNotes),
            children: [
              if (notes.notes.isEmpty)
                ListTile(dense: true, title: Text(context.l10n.mobileXiangqiSavedEmpty))
              else
                for (final note in notes.notes)
                  ListTile(
                    dense: true,
                    title: Text(note.title ?? note.id ?? ''),
                    subtitle: note.description == null ? null : Text(note.description!),
                    // A note is a game gone through, so the way into one is the review screen — the
                    // same screen a finished game opens onto.
                    onTap: note.id == null
                        ? null
                        : () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).push(XiangqiReviewScreen.buildRoute(note.id!)),
                  ),
            ],
          ),
          loading: () => ListSection.loading(itemsNumber: 3, header: true, hasLeading: true),
          error: (error, stackTrace) => ListSection(
            hasLeading: true,
            header: Text(context.l10n.mobileXiangqiSavedNotes),
            children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
          ),
        );
  }
}

/// Asks for a name and makes a folder with it.
Future<void> _makeFolder(
  BuildContext context,
  WidgetRef ref,
  String username,
  XiangqiSavedKind kind,
) async {
  final title = context.l10n.mobileXiangqiSavedNewFolder;
  final name = await _askForName(context, title: title);
  if (name == null || !context.mounted) return;
  await _run(
    context,
    ref,
    () => ref.read(xiangqiSavedRepositoryProvider).createFolder(kind: kind, name: name),
    onDone: () => ref.invalidate(xiangqiSavedFoldersProvider((username, kind, null))),
  );
}

/// Asks for a new name and renames the folder to it.
Future<void> _renameFolder(
  BuildContext context,
  WidgetRef ref,
  String username,
  XiangqiSavedKind kind,
  XiangqiSavedFolder folder,
) async {
  final title = context.l10n.mobileXiangqiSavedRename;
  final name = await _askForName(context, title: title, initial: folder.name);
  if (name == null || !context.mounted) return;
  await _run(
    context,
    ref,
    () => ref.read(xiangqiSavedRepositoryProvider).renameFolder(id: folder.id, name: name),
    onDone: () => ref.invalidate(xiangqiSavedFoldersProvider((username, kind, null))),
  );
}

/// Deletes the folder, without asking.
///
/// The same shape the site's own client has: a folder is a name and a place in a tree, and the one
/// this app can make is empty until the content that goes in it exists. A confirmation for an empty
/// folder would be a dialogue about nothing.
Future<void> _deleteFolder(
  BuildContext context,
  WidgetRef ref,
  String username,
  XiangqiSavedKind kind,
  XiangqiSavedFolder folder,
) => _run(
  context,
  ref,
  () => ref.read(xiangqiSavedRepositoryProvider).deleteFolder(folder.id),
  onDone: () => ref.invalidate(xiangqiSavedFoldersProvider((username, kind, null))),
);

/// Asks for a name, and answers null when the reader backs out.
Future<String?> _askForName(BuildContext context, {required String title, String? initial}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.mobileXiangqiSavedFolderName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.cancel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(context.l10n.accept),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Runs [action], says so when it fails, and refreshes when it does not.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required VoidCallback onDone,
}) async {
  try {
    await action();
    onDone();
  } catch (_) {
    if (!context.mounted) return;
    showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
  }
}

/// The name of [kind], in the reader's own language.
String _kindLabel(BuildContext context, XiangqiSavedKind kind) => switch (kind) {
  .puzzle => context.l10n.mobileXiangqiSavedPuzzles,
  .note => context.l10n.mobileXiangqiSavedNotes,
};
