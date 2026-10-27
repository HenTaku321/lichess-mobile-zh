import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart'
    show XiangqiAuthStorage, xiangqiAuthStorageProvider;

/// One in-memory authority for HTTP, sockets and the account UI. Storage writes are serialised;
/// generation checks prevent a response from a signed-out session replacing a newer account.
class XiangqiSessionStore(final XiangqiAuthStorage storage) {
  final _changes = StreamController<XiangqiSession?>.broadcast(sync: true);
  Future<void> _writes = Future<void>.value();
  late final Future<void> ready = _restore();
  XiangqiSession? _session;
  int _generation = 0;
  int _accountGeneration = 0;

  Stream<XiangqiSession?> get changes => _changes.stream;
  int get generation => _generation;
  int get accountGeneration => _accountGeneration;
  XiangqiSession? get current => _session;

  Future<int> beginOperation() async {
    await ready;
    return ++_generation;
  }

  Future<void> _restore() async {
    final version = _generation;
    final saved = await storage.read();
    if (version == _generation) {
      _session = saved;
      if (saved != null) _accountGeneration++;
    }
  }

  Future<XiangqiSession?> read() async {
    await ready;
    return _session;
  }

  Future<bool> write(XiangqiSession? session, {int? expectedGeneration}) async {
    await ready;
    if (expectedGeneration != null && expectedGeneration != _generation) return false;
    final identityChanged =
        _session?.userId != session?.userId || _session?.isGuest != session?.isGuest;
    _generation++;
    if (identityChanged) _accountGeneration++;
    _session = session;
    if (!_changes.isClosed) _changes.add(session);
    final write = _writes.then((_) => session == null ? storage.delete() : storage.write(session));
    _writes = write.catchError((Object _) {});
    await write;
    return true;
  }

  Future<void> reload() async {
    await ready;
    await _writes;
    final version = _generation;
    final saved = await storage.read();
    if (version == _generation && saved != _session) {
      _generation++;
      if (_session?.userId != saved?.userId || _session?.isGuest != saved?.isGuest) {
        _accountGeneration++;
      }
      _session = saved;
      if (!_changes.isClosed) _changes.add(saved);
    }
  }

  void dispose() {
    unawaited(_changes.close());
  }
}

final xiangqiSessionStoreProvider = Provider<XiangqiSessionStore>((ref) {
  final store = XiangqiSessionStore(ref.read(xiangqiAuthStorageProvider));
  ref.onDispose(store.dispose);
  return store;
}, name: 'XiangqiSessionStoreProvider');

/// Await this before deciding that a cold-start account is absent.
final xiangqiSessionReadyProvider = FutureProvider<void>((ref) {
  return ref.read(xiangqiSessionStoreProvider).ready;
}, name: 'XiangqiSessionReadyProvider');
