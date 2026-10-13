import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// The lichess side of the contacts list, on its own.
///
/// Split out from [contactsProvider] so that the merge has two sources to fail independently. Its
/// name and shape are the original [contactsProvider], unchanged: it is the lichess inbox endpoint
/// and nothing else.
final lichessContactsProvider = FutureProvider.autoDispose<Contacts>((ref) {
  return ref.watch(messageRepositoryProvider).loadContacts();
}, name: 'LichessContactsProvider');

/// The current user's contacts, from every backend, as one list.
///
/// This is the one screen where the two backends meet, so the two sources are merged and never
/// fused: a lichess contact and a xiangqi conversation become rows of one list, and each row keeps
/// its own backend's user object whole. A name, an avatar or a date is never carried across — the
/// two services have separate accounts with separate ids, and a display name that happens to match
/// is a coincidence, not an identity.
///
/// A source that throws loses its own rows and nothing else: the merged list renders whatever the
/// other source produced rather than an error. That is deliberate — an error screen would let the
/// user infer *which* backend failed, and which backend is which must never surface — so only a
/// failure of both sources is a failure of the list. When both go there is nothing left to show and
/// the lichess failure is the one thrown: the list is the lichess inbox with the xiangqi rows
/// appended, so that is the backend the error is about, and it is the same error a build without
/// xiangqi would have shown. A one-source failure is not announced at all — it is an ordinary
/// degraded state, not a crash.
///
/// `me` is a scalar and is not merged. The app has one identity, and it is the lichess account when
/// there is one — the user this list is *for* is the signed-in lichess user — falling back to the
/// xiangqi session only when there is no lichess account. The two are never blended into a
/// synthetic user, and a row's own `user` is always the peer, never this.
final contactsProvider = FutureProvider.autoDispose<Contacts>((ref) async {
  final lichessFuture = ref.watch(lichessContactsProvider.future);
  final xiangqiFuture = ref.watch(xiangqiContactsProvider.future);
  final authUser = ref.watch(authControllerProvider)?.user;

  Contacts? lichess;
  IList<Contact> xiangqi = const IListConst<Contact>([]);
  Object? lichessFailure;
  Object? xiangqiFailure;
  await Future.wait<void>([
    lichessFuture.then<void>(
      (value) => lichess = value,
      onError: (Object error) => lichessFailure = error,
    ),
    xiangqiFuture.then<void>(
      (value) => xiangqi = value,
      onError: (Object error) => xiangqiFailure = error,
    ),
  ]);

  if (lichessFailure != null && xiangqiFailure != null) {
    throw lichessFailure!;
  }

  // A source that failed is not announced; its rows are simply absent from what follows.
  final me = lichess?.me ?? authUser ?? await xiangqiSelfLightUser(ref);
  if (me == null) {
    // Neither backend could say who this user is, so there is no list to build. This is the same
    // state the unmerged provider was in before it could talk to xiangqi.com at all.
    throw StateError('Neither backend could identify the current user.');
  }

  return Contacts(
    contacts: [...?lichess?.contacts, ...xiangqi].lock,
    me: me,
    isBot: lichess?.isBot ?? false,
  );
}, name: 'ContactsProvider');

/// A provider for [MessageRepository].
final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(lichessClientProvider), ref.watch(aggregatorProvider));
}, name: 'MessageRepositoryProvider');

/// A provider that gets the unread messages count for the current user.
final unreadMessagesProvider = FutureProvider.autoDispose<UnreadMessages>((ref) {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) {
    return Future.value((unread: 0, lichess: false));
  }
  final aggregator = ref.watch(aggregatorProvider);
  return aggregator.readJson(
    Uri(path: '/inbox/unread-count'),
    atomicMapper: (Map<String, dynamic> json) {
      return (unread: json['unread'] as int, lichess: json['lichess'] as bool? ?? false);
    },
  );
}, name: 'UnreadMessagesProvider');

class const MessageRepository(final LichessClient client, final Aggregator aggregator) {
  Future<UnreadMessages> unreadMessages() {
    return aggregator.readJson(
      Uri(path: '/inbox/unread-count'),
      headers: {'Accept': 'application/json'},
      atomicMapper: (Map<String, dynamic> json) =>
          (unread: json['unread'] as int, lichess: json['lichess'] as bool? ?? false),
    );
  }

  Future<Contacts> loadContacts() {
    return client.readJson(
      Uri(path: '/inbox'),
      headers: {'Accept': 'application/json'},
      mapper: (Map<String, dynamic> json) => Contacts.fromServerJson(json),
    );
  }

  Future<ConversationData> loadConvo(UserId userId) {
    return client.readJson(
      Uri(path: '/inbox/$userId'),
      headers: {'Accept': 'application/json'},
      mapper: (Map<String, dynamic> json) => ConversationData.fromServerJson(json),
    );
  }

  Future<ConversationData> getMore(UserId userId, DateTime before) {
    return client.readJson(
      Uri(
        path: '/inbox/$userId',
        queryParameters: {'before': before.millisecondsSinceEpoch.toString()},
      ),
      headers: {'Accept': 'application/json'},
      mapper: (Map<String, dynamic> json) => ConversationData.fromServerJson(json),
    );
  }

  Future<SearchResult> search(String query) {
    return client.readJson(
      Uri(path: '/inbox/search', queryParameters: {'q': query}),
      headers: {'Accept': 'application/json'},
      mapper: (Map<String, dynamic> json) => SearchResult.fromJson(json),
    );
  }
}
