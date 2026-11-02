import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_pagination.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';

class const ContactsListState({
  required final Contacts? data,
  required final bool loading,
  required final bool refreshing,
  required final Object? lichessError,
  required final Object? xiangqiError,
  required final XiangqiPagedState<Contact>? xiangqi,
  required final bool hasLichess,
  required final bool hasXiangqi,
}) {
  bool get hasError => lichessError != null || xiangqiError != null;
}

final contactsControllerProvider =
    NotifierProvider.autoDispose<ContactsController, ContactsListState>(
      ContactsController.new,
      name: 'ContactsControllerProvider',
    );

/// Both sources settle independently. Only their own account boundary can clear their cache.
class ContactsController() extends Notifier<ContactsListState> {
  UserId? _lichessOwner;
  int? _xiangqiOwner;
  Contacts? _lichess;
  XiangqiPagedState<Contact>? _xiangqi;
  Object? _identity;
  Future<void>? _refresh;

  @override
  ContactsListState build() {
    final me = ref.watch(authControllerProvider.select((auth) => auth?.user));
    final account = ref.watch(xiangqiAccountGenerationProvider);
    final ready = ref.watch(xiangqiSessionReadyProvider);
    final session = ready.isLoading ? null : ref.read(xiangqiSessionStoreProvider).current;
    final identity = (me?.id, account);
    if (_identity != identity) {
      _identity = identity;
      _refresh = null;
    }
    if (_lichessOwner != me?.id) {
      _lichessOwner = me?.id;
      _lichess = null;
    }
    if (_xiangqiOwner != account) {
      _xiangqiOwner = account;
      _xiangqi = null;
    }
    final lichess = me == null ? null : ref.watch(lichessContactsProvider);
    final xiangqi = session == null ? null : ref.watch(xiangqiContactsControllerProvider);
    Object? wrongOwner;
    if (lichess is AsyncData<Contacts> && !lichess.isLoading && !lichess.hasError) {
      if (lichess.value.me.id == me?.id) {
        _lichess = lichess.value;
      } else {
        wrongOwner = const FormatException('The inbox response belongs to another account.');
      }
    }
    if (xiangqi is AsyncData<XiangqiPagedState<Contact>> &&
        !xiangqi.isLoading &&
        !xiangqi.hasError) {
      _xiangqi = xiangqi.value;
    }
    final currentMe =
        me ?? (session == null ? null : xiangqiLightUser(session.userId, session.name));
    final data = currentMe == null
        ? null
        : Contacts(
            contacts: [...?_lichess?.contacts, ...?_xiangqi?.items].lock,
            me: currentMe,
            isBot: _lichess?.isBot ?? false,
          );
    return ContactsListState(
      data: data,
      loading: ready.isLoading || (lichess?.isLoading ?? false) || (xiangqi?.isLoading ?? false),
      refreshing: _refresh != null || (_xiangqi?.refreshing ?? false),
      lichessError: wrongOwner ?? lichess?.error,
      xiangqiError: xiangqi?.error ?? _xiangqi?.refreshError,
      xiangqi: _xiangqi,
      hasLichess: me != null,
      hasXiangqi: session != null,
    );
  }

  Future<void> refresh({bool failedOnly = false}) {
    if (_refresh case final active?) return active;
    final identity = _identity;
    final current = state;
    final requests = <Future<void>>[];
    if (current.hasLichess && (!failedOnly || current.lichessError != null)) {
      requests.add(
        ref
            .refresh(lichessContactsProvider.future)
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    if (current.hasXiangqi && (!failedOnly || current.xiangqiError != null)) {
      requests.add(ref.read(xiangqiContactsControllerProvider.notifier).refresh());
    }
    final future = Future.wait(requests).then<void>((_) {});
    _refresh = future;
    ref.invalidateSelf();
    unawaited(
      future.then<void>((_) {
        if (ref.mounted && identity == _identity && identical(_refresh, future)) {
          _refresh = null;
          ref.invalidateSelf();
        }
      }),
    );
    return future;
  }

  Future<void> getMore() => ref.read(xiangqiContactsControllerProvider.notifier).getMore();
}
