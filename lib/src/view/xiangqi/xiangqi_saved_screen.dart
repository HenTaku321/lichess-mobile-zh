import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/saved/xiangqi_saved.dart';
import 'package:lichess_mobile/src/model/xiangqi/saved/xiangqi_saved_repository.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refreshable_empty.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
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
    // **A real account**: the folder tree is filed under a username, and a guest's own name is not
    // one the server will answer for — measured on 2026-10-16, where `items/folders/<guest>/…` was a
    // `404` and the signed-in account's was a `200`.
    final session = ref.watch(xiangqiAuthControllerProvider);
    final username = session != null && !session.isGuest ? session.name : null;

    final generation = ref.watch(xiangqiAccountGenerationProvider);
    return DefaultTabController(
      length: XiangqiSavedKind.values.length,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return ListenableBuilder(
            listenable: tabs,
            builder: (context, _) {
              final kind = XiangqiSavedKind.values[tabs.index];
              return XiangqiRefreshScope(
                identity: (username, kind, generation),
                onRefresh: () => username == null
                    ? Future<void>.value()
                    : _refreshSavedKind(ref, username, kind),
                builder: (context, refresh, busy) => Scaffold(
                  appBar: AppBar(
                    title: AppBarTitleText(
                      '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiSaved}',
                    ),
                    bottom: TabBar(
                      tabs: [
                        for (final kind in XiangqiSavedKind.values)
                          Tab(text: _kindLabel(context, kind)),
                      ],
                    ),
                    actions: [
                      DesktopRefreshButton(
                        onRefresh: refresh,
                        busy: busy,
                        enabled:
                            username != null && !ref.watch(xiangqiSessionReadyProvider).isLoading,
                      ),
                    ],
                  ),
                  body: ref.watch(xiangqiSessionReadyProvider).isLoading
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : username == null
                      ? Center(
                          child: Padding(
                            padding: Styles.bodySectionPadding,
                            child: Text(
                              context.l10n.mobileXiangqiSignIn,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : TabBarView(
                          children: [
                            for (final kind in XiangqiSavedKind.values)
                              _KindTab(
                                username: username,
                                kind: kind,
                                onRefresh: refresh,
                                busy: busy,
                              ),
                          ],
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _refreshSavedKind(WidgetRef ref, String username, XiangqiSavedKind kind) async {
  final subscriptions = [
    ref.listenManual(xiangqiSavedFoldersProvider((username, kind, null)), (_, _) {}),
    switch (kind) {
      XiangqiSavedKind.puzzle => ref.listenManual(xiangqiSavedPuzzlesProvider(username), (_, _) {}),
      XiangqiSavedKind.note => ref.listenManual(xiangqiSavedNotesProvider(username), (_, _) {}),
    },
  ];
  try {
    await Future.wait<Object?>([
      ref.refresh(xiangqiSavedFoldersProvider((username, kind, null)).future),
      switch (kind) {
        XiangqiSavedKind.puzzle => ref.refresh(xiangqiSavedPuzzlesProvider(username).future),
        XiangqiSavedKind.note => ref.refresh(xiangqiSavedNotesProvider(username).future),
      },
    ]);
  } finally {
    for (final subscription in subscriptions) {
      subscription.close();
    }
  }
}

/// One kind of content: its folders, and what is at the root of its tree.
class const _KindTab({
  required final String username,
  required final XiangqiSavedKind kind,
  required final XiangqiRefresh onRefresh,
  required final bool busy,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(xiangqiSavedFoldersProvider((username, kind, null)));

    return XiangqiRetainedData(
      identity: (username, kind, ref.watch(xiangqiAccountGenerationProvider)),
      value: folders,
      builder: (context, folders) => RefreshIndicator.adaptive(
        onRefresh: () => onRefresh(request: () => _refreshSavedKind(ref, username, kind)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListSection(
              hasLeading: true,
              header: Text(context.l10n.mobileXiangqiSavedNewFolder),
              children: [_CreateFolderRow(username: username, kind: kind)],
            ),
            switch (folders) {
              AsyncData(:final value) when value.folders.isNotEmpty => ListSection(
                hasLeading: true,
                children: [
                  for (final folder in value.folders)
                    _FolderRow(folder: folder, username: username, kind: kind),
                ],
              ),
              AsyncData() => const SizedBox.shrink(),
              AsyncError() => ListSection(
                hasLeading: true,
                children: [
                  _RetryRow(
                    onRetry: () => onRefresh(
                      request: () =>
                          ref.refresh(xiangqiSavedFoldersProvider((username, kind, null)).future),
                    ),
                  ),
                ],
              ),
              _ => const ListSection(
                hasLeading: true,
                children: [ListTile(dense: true, title: Text('…'))],
              ),
            },
            if (kind == XiangqiSavedKind.puzzle)
              _Puzzles(username: username, onRefresh: onRefresh, busy: busy)
            else
              _Notes(username: username, onRefresh: onRefresh, busy: busy),
          ],
        ),
      ),
    );
  }
}

class const _CreateFolderRow({
  required final String username,
  required final XiangqiSavedKind kind,
  final String? parentId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CreateFolderRow> createState() => _CreateFolderRowState();
}

class _CreateFolderRowState() extends ConsumerState<_CreateFolderRow> {
  bool _busy = false;

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _makeFolder(context, ref, widget.username, widget.kind, parentId: widget.parentId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.create_new_folder_outlined),
    title: Text(context.l10n.mobileXiangqiSavedNewFolder),
    onTap: _busy ? null : _create,
  );
}

/// One folder: its name, and the two things that can be done to it.
class const _FolderRow({
  required final XiangqiSavedFolder folder,
  required final String username,
  required final XiangqiSavedKind kind,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState() extends ConsumerState<_FolderRow> {
  bool _busy = false;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final username = widget.username;
    final kind = widget.kind;
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l10n.mobileXiangqiSavedRename,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _busy
                ? null
                : () => _perform(() => _renameFolder(context, ref, username, kind, folder)),
          ),
          IconButton(
            tooltip: context.l10n.mobileXiangqiSavedDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy
                ? null
                : () => _perform(() => _deleteFolder(context, ref, username, kind, folder)),
          ),
        ],
      ),
      onTap: _busy
          ? null
          : () => Navigator.of(
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
    final session = ref.watch(xiangqiAuthControllerProvider);
    if (session == null || session.isGuest || session.name != username) {
      return Scaffold(
        appBar: AppBar(title: AppBarTitleText(folder.name)),
        body: Center(child: Text(context.l10n.mobileXiangqiSignIn)),
      );
    }
    final folders = ref.watch(xiangqiSavedFoldersProvider((username, kind, folder.id)));

    final identity = (username, kind, folder.id, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiSavedFoldersProvider((username, kind, folder.id)).future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: folders,
        builder: (context, folders) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(folder.name),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: folders.when(
            data: (folders) => folders.folders.isEmpty
                ? XiangqiRefreshableEmpty(
                    onRefresh: refresh,
                    child: Padding(
                      padding: Styles.bodySectionPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CreateFolderRow(username: username, kind: kind, parentId: folder.id),
                          Text(context.l10n.mobileXiangqiSavedEmpty),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator.adaptive(
                    onRefresh: refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _CreateFolderRow(username: username, kind: kind, parentId: folder.id),
                        ListSection(
                          hasLeading: true,
                          children: [
                            for (final child in folders.folders)
                              _FolderRow(folder: child, username: username, kind: kind),
                          ],
                        ),
                      ],
                    ),
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
                    FilledButton(onPressed: refresh, child: Text(context.l10n.retry)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The puzzles this account has created.
class const _Puzzles({
  required final String username,
  required final XiangqiRefresh onRefresh,
  required final bool busy,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzles = ref.watch(xiangqiSavedPuzzlesProvider(username));
    return XiangqiRetainedData(
      identity: (username, ref.watch(xiangqiAccountGenerationProvider)),
      value: puzzles,
      builder: (context, puzzles) => puzzles.when(
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
                  title: Text(puzzle.id, maxLines: 1, overflow: TextOverflow.ellipsis),
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
          children: [
            _RetryRow(
              onRetry: busy
                  ? null
                  : () => onRefresh(
                      request: () => ref.refresh(xiangqiSavedPuzzlesProvider(username).future),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The notes this account has saved.
class const _Notes({
  required final String username,
  required final XiangqiRefresh onRefresh,
  required final bool busy,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(xiangqiSavedNotesProvider(username));
    return XiangqiRetainedData(
      identity: (username, ref.watch(xiangqiAccountGenerationProvider)),
      value: notes,
      builder: (context, notes) => notes.when(
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
                  title: Text(
                    note.title ?? note.id ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: note.description == null
                      ? null
                      : Text(note.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
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
          children: [
            _RetryRow(
              onRetry: busy
                  ? null
                  : () => onRefresh(
                      request: () => ref.refresh(xiangqiSavedNotesProvider(username).future),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _RetryRow({required final VoidCallback? onRetry}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(context.l10n.mobileSomethingWentWrong),
    trailing: IconButton(
      tooltip: context.l10n.retry,
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
    ),
  );
}

/// Keep the editable draft in the dialog until the server acknowledges the write.
Future<void> _makeFolder(
  BuildContext context,
  WidgetRef ref,
  String username,
  XiangqiSavedKind kind, {
  String? parentId,
}) async {
  final title = context.l10n.mobileXiangqiSavedNewFolder;
  await _askForName(
    context,
    ref,
    title: title,
    submit: (name) => ref
        .read(xiangqiSavedRepositoryProvider)
        .createFolder(kind: kind, name: name, parentId: parentId),
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
  await _askForName(
    context,
    ref,
    title: title,
    initial: folder.name,
    submit: (name) =>
        ref.read(xiangqiSavedRepositoryProvider).renameFolder(id: folder.id, name: name),
  );
}

/// The contents' deletion semantics are unknown, so always confirm the destructive operation.
Future<void> _deleteFolder(
  BuildContext context,
  WidgetRef ref,
  String username,
  XiangqiSavedKind kind,
  XiangqiSavedFolder folder,
) async {
  final generation = ref.read(xiangqiAccountGenerationProvider);
  var confirmed = false;
  await showAdaptiveDialog<void>(
    context: context,
    builder: (dialogContext) => YesNoDialog(
      title: Text(context.l10n.mobileXiangqiSavedDelete),
      content: Text('${folder.name}\n${context.l10n.mobileAreYouSure}'),
      onYes: () {
        confirmed = true;
        Navigator.pop(dialogContext);
      },
      onNo: () => Navigator.pop(dialogContext),
    ),
  );
  if (!confirmed || !context.mounted || generation != ref.read(xiangqiAccountGenerationProvider)) {
    return;
  }
  await _run(
    context,
    ref,
    () => ref.read(xiangqiSavedRepositoryProvider).deleteFolder(folder.id),
    onDone: () {
      ref.invalidate(xiangqiSavedFoldersProvider);
      ref.invalidate(xiangqiSavedPuzzlesProvider(username));
      ref.invalidate(xiangqiSavedNotesProvider(username));
    },
  );
}

/// Asks for a name, and answers null when the reader backs out.
Future<void> _askForName(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? initial,
  required Future<void> Function(String) submit,
}) async {
  final generation = ref.read(xiangqiAccountGenerationProvider);
  await showAdaptiveDialog<void>(
    context: context,
    builder: (dialogContext) => _FolderNameDialog(
      title: title,
      initial: initial,
      submit: (name) async {
        if (!context.mounted || generation != ref.read(xiangqiAccountGenerationProvider)) {
          throw StateError('Account changed');
        }
        await submit(name);
        if (context.mounted && generation == ref.read(xiangqiAccountGenerationProvider)) {
          ref.invalidate(xiangqiSavedFoldersProvider);
        }
      },
    ),
  );
}

class const _FolderNameDialog({
  required final String title,
  final String? initial,
  required final Future<void> Function(String) submit,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState() extends ConsumerState<_FolderNameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;
  late final int _generation;

  @override
  void initState() {
    super.initState();
    _generation = ref.read(xiangqiAccountGenerationProvider);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        _generation != ref.read(xiangqiAccountGenerationProvider) ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(_name.text.trim());
      if (mounted && _generation == ref.read(xiangqiAccountGenerationProvider)) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted && _generation == ref.read(xiangqiAccountGenerationProvider)) {
        setState(() {
          _busy = false;
          _error = context.l10n.mobileSomethingWentWrong;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(xiangqiAccountGenerationProvider, (previous, next) {
      if (next != _generation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.pop(context);
        });
      }
    });
    return PopScope(
      canPop: !_busy,
      child: AlertDialog.adaptive(
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(labelText: context.l10n.mobileXiangqiSavedFolderName),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? context.l10n.required : null,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: ColorScheme.of(context).error)),
              if (_busy) const CircularProgressIndicator.adaptive(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(onPressed: _busy ? null : _save, child: Text(context.l10n.accept)),
        ],
      ),
    );
  }
}

/// Runs [action], says so when it fails, and refreshes when it does not.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required VoidCallback onDone,
}) async {
  final generation = ref.read(xiangqiAccountGenerationProvider);
  try {
    await action();
    if (!context.mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
    onDone();
  } catch (_) {
    if (!context.mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
    showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
  }
}

/// The name of [kind], in the reader's own language.
String _kindLabel(BuildContext context, XiangqiSavedKind kind) => switch (kind) {
  .puzzle => context.l10n.mobileXiangqiSavedPuzzles,
  .note => context.l10n.mobileXiangqiSavedNotes,
};
