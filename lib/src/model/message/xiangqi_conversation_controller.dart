import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_pagination.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:logging/logging.dart';

final _logger = Logger('XiangqiConversation');

final _conversationPagesProvider = AsyncNotifierProvider.autoDispose
    .family<_ConversationPages, XiangqiPagedState<Message>, XiangqiConversationKey>(
      _ConversationPages.new,
    );

class _ConversationPages(final XiangqiConversationKey key) extends XiangqiPagedController<Message> {
  late XiangqiInboxRepository _repository;
  String? _self;

  @override
  Future<XiangqiPagedState<Message>> build() async {
    await ref.watch(xiangqiSessionReadyProvider.future);
    if (!ref.mounted) throw StateError('Conversation page load cancelled.');
    _repository = ref.watch(xiangqiInboxRepositoryProvider);
    _self = ref.read(xiangqiSessionStoreProvider).current?.userId;
    if (_self == null) throw const XiangqiInboxException('No xiangqi.com session.');
    return await super.build();
  }

  @override
  Future<XiangqiPage<Message>> loadPage(int page) async {
    final result = await _repository.loadMessagesPage(key.chatId, page);
    final self = xiangqiUserId(_self);
    final peer = xiangqiUserId(key.peerId);
    return result.withItems(
      result.items.where((message) => message.userId == self || message.userId == peer).toIList(),
    );
  }

  // An observed sender/text/date tuple can identify an overlapping row, not a delivery receipt.
  // No server message ID is synthesised from a local counter or clock.
  @override
  Object itemKey(Message item) => item;
}

final xiangqiConversationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<XiangqiConversationController, XiangqiConversationState, XiangqiConversationKey>(
      XiangqiConversationController.new,
      name: 'XiangqiConversationControllerProvider',
    );

/// Paged history and transient local rows have separate lifetimes. Reading older pages never
/// rebuilds the composer, clears an optimistic send, or changes the conversation's account.
class XiangqiConversationController(final XiangqiConversationKey key)
    extends AsyncNotifier<XiangqiConversationState> {
  int _generation = 0;
  bool _built = false;
  bool _sending = false;
  bool _resyncQueued = false;
  Future<void>? _refresh;
  final List<Message> _overlays = [];
  final List<_LocalMessage> _local = [];

  bool _current(int generation) => ref.mounted && generation == _generation;

  @override
  Future<XiangqiConversationState> build() async {
    final generation = ++_generation;
    _sending = false;
    _resyncQueued = false;
    _refresh = null;
    _overlays.clear();
    _local.clear();
    ref.onDispose(() => _generation++);
    await ref.watch(xiangqiSessionReadyProvider.future);
    if (!_current(generation)) throw StateError('Conversation load cancelled.');
    ref.watch(xiangqiAccountGenerationProvider);
    final repository = ref.watch(xiangqiInboxRepositoryProvider);
    final session = ref.read(xiangqiSessionStoreProvider).current;
    if (session == null) throw const XiangqiInboxException('No xiangqi.com session.');
    final self = xiangqiLightUser(session.userId, session.name);
    final pagesProvider = _conversationPagesProvider(key);
    // Explicit resync/rebuild starts a fresh first page. A Lichess identity change, by contrast,
    // updates only the scalar display identity and must not reset this Xiangqi page range.
    if (_built) ref.invalidate(pagesProvider);
    _built = true;
    ref.listen(authControllerProvider, (_, auth) {
      if (_current(generation) && state.hasValue && !state.isLoading) {
        state = AsyncData(state.requireValue.copyWith(me: auth?.user ?? self));
      }
    });
    ref.listen(pagesProvider, (_, next) {
      if (_current(generation) && state.hasValue && !state.isLoading && next.hasValue) {
        _publish(next.requireValue);
      }
    });
    final pages = await ref.read(pagesProvider.future);
    if (!_current(generation)) throw StateError('Conversation load cancelled.');
    final incoming = repository.conversationUpdates(key, self.id).listen((update) {
      if (_current(generation)) _onIncoming(update);
    });
    final resets = repository.connectionResets.listen((_) {
      if (_current(generation) && state.hasValue && !state.requireValue.pagination.busy) {
        unawaited(refresh());
      }
    });
    ref.onDispose(() {
      unawaited(incoming.cancel());
      unawaited(resets.cancel());
    });
    unawaited(repository.markRead(key.chatId).catchError((Object _) {}));
    return XiangqiConversationState(
      me: ref.read(authControllerProvider)?.user ?? self,
      selfId: self.id,
      pagination: pages,
      convo: Convo(
        user: key.peer,
        messages: pages.items,
        relations: (inward: null, outward: null),
        postable: true,
      ),
    );
  }

  void _publish(XiangqiPagedState<Message> pages) {
    if (!state.hasValue || state.isLoading) return;
    final messages = <Message>[..._overlays];
    for (final message in pages.items) {
      if (!messages.contains(message)) messages.add(message);
    }
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        pagination: pages,
        convo: current.convo.copyWith(messages: messages.lock),
      ),
    );
  }

  Future<void> getMore() => ref.read(_conversationPagesProvider(key).notifier).getMore();

  Future<void> refresh() => _startRefresh(retry: false);
  Future<void> retryRefresh() => _startRefresh(retry: true);

  Future<void> _startRefresh({required bool retry}) {
    if (_refresh case final active?) return active;
    if (!state.hasValue || state.isLoading) {
      ref.invalidateSelf();
      return Future<void>.value();
    }
    final generation = _generation;
    final oldRows = _overlays.toList();
    final emitted = _local.where((local) => local.emitted).toList();
    final pager = ref.read(_conversationPagesProvider(key).notifier);
    final future = (retry ? pager.retryRefresh() : pager.refresh()).then<void>((_) {
      if (!_current(generation)) return;
      final pages = ref.read(_conversationPagesProvider(key)).value;
      if (pages == null || pages.refreshError != null) return;
      // Only a fresh authoritative history replaces locally emitted rows. A text-only echo is
      // never used to stamp a server date onto a guessed optimistic message or to claim delivery.
      _local.removeWhere(emitted.contains);
      _overlays.removeWhere(
        (row) =>
            emitted.any((local) => identical(local.message, row)) ||
            (oldRows.contains(row) && !_local.any((local) => identical(local.message, row))),
      );
      _publish(pages);
    });
    _refresh = future;
    unawaited(
      future.then<void>((_) {
        if (!_current(generation) || !identical(_refresh, future)) return;
        _refresh = null;
        final queued = _resyncQueued;
        _resyncQueued = false;
        if (queued && state.value?.pagination.refreshError == null) unawaited(refresh());
      }),
    );
    return future;
  }

  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !state.hasValue || state.isLoading || _sending) return false;
    final generation = _generation;
    _sending = true;
    final current = state.requireValue;
    final local = _LocalMessage(Message(userId: current.selfId, text: trimmed, date: clock.now()));
    _local.add(local);
    _overlays.insert(0, local.message);
    _publish(current.pagination);
    try {
      await ref
          .read(xiangqiInboxRepositoryProvider)
          .sendMessage(
            chatId: key.chatId,
            peerId: key.peerId,
            peerName: key.peer.name,
            text: trimmed,
            onEmitted: () => local.emitted = true,
          );
      return _current(generation);
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not send to chat ${key.chatId}.', error, stackTrace);
      if (!_current(generation)) return false;
      _local.remove(local);
      _overlays.removeWhere((row) => identical(row, local.message));
      if (state.hasValue && !state.isLoading) _publish(state.requireValue.pagination);
      return false;
    } finally {
      if (_current(generation)) _sending = false;
    }
  }

  void _onIncoming(XiangqiInboxUpdate update) {
    if (!state.hasValue || state.isLoading) return;
    if (update.needsRefresh) {
      if (_refresh != null) {
        _resyncQueued = true;
      } else {
        unawaited(refresh());
      }
      return;
    }
    final message = update.message!;
    final current = state.requireValue;
    if (message.userId != xiangqiUserId(key.peerId)) return;
    if (!_overlays.contains(message) && !current.convo.messages.contains(message)) {
      _overlays.insert(0, message);
      _publish(current.pagination);
    }
    unawaited(
      ref.read(xiangqiInboxRepositoryProvider).markRead(key.chatId).catchError((Object _) {}),
    );
  }
}

class _LocalMessage(final Message message) {
  bool emitted = false;
}
