import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';

/// Owns a private transport for protocols whose response events have no request identity.
///
/// Reply-bearing reads are serialised. All emissions share a second, serial pacing gate, so
/// fire-and-forget commands can run during a read without sending a burst. A failed read retires
/// the client and its broadcast stream, not just the underlying WebSocket channel.
class XiangqiSocketRequestQueue({
  required final XiangqiSocketClient _socket,
  final Duration timeout = const Duration(seconds: 20),
  final Duration spacing = Duration.zero,
}) {
  XiangqiSocketClient _fork() => _socket.fork();
  final Queue<_SocketRead<dynamic>> _queue = Queue();
  final Set<_SocketRead<dynamic>> _reads = {};
  final Map<Object, _SocketRead<dynamic>> _pending = {};
  final Set<_SocketSend> _sends = {};
  final _events = StreamController<XiangqiSocketEvent>.broadcast();
  final _resets = StreamController<void>.broadcast();

  XiangqiSocketClient? _client;
  StreamSubscription<XiangqiSocketEvent>? _subscription;
  StreamSubscription<XiangqiConnectionStatus>? _statusSubscription;
  _SocketRead<dynamic>? _active;
  Future<void> _sendTail = Future<void>.value();
  DateTime? _lastEmitAt;
  Timer? _spacingTimer;
  Completer<void>? _spacingWait;
  int _transportGeneration = 0;
  bool _hadConnection = false;
  bool _pumping = false;
  bool _disposed = false;

  Stream<XiangqiSocketEvent> get events => _events.stream;
  Stream<void> get resets => _resets.stream;
  bool get isConnected => _client?.isConnected ?? false;

  Future<T> read<T>({
    required String event,
    required Object? data,
    required String response,
    required T Function(Object? data) decode,
    Object? key,
    bool ack = false,
    bool Function()? isCurrent,
    Future<void> Function()? prepare,
  }) {
    if (_disposed) return Future.error(const XiangqiSocketException('Request queue disposed.'));
    final existing = key == null ? null : _pending[key];
    if (existing != null) return existing.result.future as Future<T>;
    final request = _SocketRead<T>(event, data, response, decode, key, ack, isCurrent, prepare);
    // Keep internal cancellation from becoming an unhandled asynchronous error when a screen
    // disappears before its caller can observe the future. Awaiting the original still throws.
    request.result.future.ignore();
    request.timer = Timer(timeout, () {
      _failRead(request, TimeoutException('xiangqi.com $event timed out.', timeout));
    });
    _reads.add(request);
    if (key != null) _pending[key] = request;
    _queue.add(request);
    unawaited(_pump());
    return request.result.future;
  }

  Future<void> sendNoAck(
    String event, {
    Object? data,
    bool Function()? isCurrent,
    Future<void> Function()? prepare,
  }) => _send(event, data, isCurrent: isCurrent, prepare: prepare);

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final request = _queue.removeFirst();
        if (request.result.isCompleted) continue;
        _active = request;
        try {
          await _send(request.event, request.data, request: request);
          await request.result.future;
        } on Object catch (error, stackTrace) {
          _failRead(request, error, stackTrace);
        } finally {
          if (identical(_active, request)) _active = null;
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _send(
    String event,
    Object? data, {
    _SocketRead<dynamic>? request,
    bool Function()? isCurrent,
    Future<void> Function()? prepare,
  }) {
    if (_disposed) return Future.error(const XiangqiSocketException('Request queue disposed.'));
    final send = _SocketSend(isCurrent);
    request?.send = send;
    send.result.future.ignore();
    _sends.add(send);
    send.timer = Timer(timeout, () {
      if (!send.result.isCompleted) {
        send.result.completeError(TimeoutException('xiangqi.com $event timed out.', timeout));
      }
    });
    _sendTail = _sendTail.then<void>((_) async {
      try {
        _checkSend(send, request);
        final preparation = request?.prepare ?? prepare;
        if (preparation != null) {
          await _awaitStep(preparation(), send);
          _checkSend(send, request);
        }
        final socket = await _awaitStep(_connected(), send);
        final generation = _transportGeneration;
        _checkSend(send, request);
        await _awaitStep(_waitForSpacing(), send);
        _checkSend(send, request);
        if (generation != _transportGeneration || !identical(socket, _client)) {
          throw const XiangqiSocketException('The request transport changed before sending.');
        }
        _lastEmitAt = clock.now();
        request?.emitted = true;
        if (request != null && request.ack) {
          // A business reply may arrive before the ACK, and is the decisive result. A missing ACK
          // for an already completed request must not retire the next request's transport.
          unawaited(
            socket
                .emit(event, data: data)
                .then<void>(
                  (_) {},
                  onError: (Object error, StackTrace stackTrace) {
                    if (generation == _transportGeneration && !request.result.isCompleted) {
                      _failRead(request, error, stackTrace);
                    }
                  },
                ),
          );
        } else {
          socket.emitNoAck(event, data: data);
        }
        if (!send.result.isCompleted) send.result.complete();
      } on Object catch (error, stackTrace) {
        if (!send.result.isCompleted) send.result.completeError(error, stackTrace);
        if (request != null) _failRead(request, error, stackTrace);
      } finally {
        send.timer?.cancel();
        _sends.remove(send);
      }
    });
    return send.result.future;
  }

  void _checkSend(_SocketSend send, _SocketRead<dynamic>? request) {
    if (_disposed ||
        send.result.isCompleted ||
        (request?.result.isCompleted ?? false) ||
        !(send.isCurrent?.call() ?? true) ||
        !(request?.isCurrent?.call() ?? true)) {
      throw const XiangqiSocketException('Request cancelled before sending.');
    }
  }

  Future<T> _awaitStep<T>(Future<T> step, _SocketSend send) => Future.any([
    step,
    send.result.future.then<T>((_) {
      throw const XiangqiSocketException('Request cancelled before sending.');
    }),
  ]);

  Future<XiangqiSocketClient> _connected() async {
    if (_disposed) throw const XiangqiSocketException('Request queue disposed.');
    final socket = _client ??= _fork();
    final generation = _transportGeneration;
    _subscription ??= socket.stream.listen((event) {
      if (_disposed || generation != _transportGeneration) return;
      final request = _active;
      if (request != null && request.emitted && event.name == request.response) {
        if (request.result.isCompleted) return;
        try {
          if (!(request.isCurrent?.call() ?? true)) {
            throw const XiangqiSocketException('The request identity changed.');
          }
          final result = request.decode(event.data);
          _finishRead(request);
          request.result.complete(result);
        } on Object catch (error, stackTrace) {
          _failRead(request, error, stackTrace);
        }
      } else if (!_events.isClosed) {
        _events.add(event);
      }
    });
    _statusSubscription ??= socket.statusStream.listen((status) {
      if (_disposed || generation != _transportGeneration) return;
      if (status == XiangqiConnectionStatus.connected) _hadConnection = true;
      if (_hadConnection &&
          (status == XiangqiConnectionStatus.closed ||
              status == XiangqiConnectionStatus.reconnecting)) {
        final request = _active;
        if (request != null && !request.result.isCompleted) {
          _failRead(request, const XiangqiSocketException('The request connection was lost.'));
        } else {
          _retireTransport();
        }
      }
    });
    await socket.connect();
    if (_disposed || generation != _transportGeneration || !identical(socket, _client)) {
      throw const XiangqiSocketException('The request connection was cancelled.');
    }
    return socket;
  }

  Future<void> _waitForSpacing() async {
    final last = _lastEmitAt;
    if (last == null) return;
    final wait = spacing - clock.now().difference(last);
    if (wait <= Duration.zero) return;
    final completer = _spacingWait = Completer<void>();
    _spacingTimer = Timer(wait, () {
      _spacingTimer = null;
      _spacingWait = null;
      completer.complete();
    });
    await completer.future;
  }

  void _finishRead(_SocketRead<dynamic> request) {
    request.timer?.cancel();
    _reads.remove(request);
    _queue.remove(request);
    if (request.key != null && identical(_pending[request.key], request)) {
      _pending.remove(request.key);
    }
  }

  void _failRead(_SocketRead<dynamic> request, Object error, [StackTrace? stackTrace]) {
    if (request.result.isCompleted) return;
    _finishRead(request);
    // A queued, unsent read cannot have a late response and must not disturb the active read.
    if (identical(_active, request)) _retireTransport(notify: false);
    request.result.completeError(error, stackTrace);
    final send = request.send;
    if (send != null && !send.result.isCompleted) {
      send.result.completeError(error, stackTrace);
    }
  }

  void _retireTransport({bool notify = true}) {
    final socket = _client;
    _client = null;
    _transportGeneration++;
    _hadConnection = false;
    unawaited(_subscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    _subscription = null;
    _statusSubscription = null;
    _spacingTimer?.cancel();
    _spacingTimer = null;
    final wait = _spacingWait;
    _spacingWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
    if (socket != null) {
      unawaited(socket.dispose());
      if (notify && !_disposed && !_resets.isClosed) _resets.add(null);
    }
  }

  void dispose({String? lastEvent, Object? lastData}) {
    if (_disposed) return;
    if (lastEvent != null && (_client?.isConnected ?? false)) {
      try {
        _client!.emitNoAck(lastEvent, data: lastData);
      } on Object {
        // Teardown is best effort; closing this private transport is the authoritative cleanup.
      }
    }
    _disposed = true;
    for (final request in _reads.toList()) {
      _finishRead(request);
      if (!request.result.isCompleted) {
        request.result.completeError(const XiangqiSocketException('Request queue disposed.'));
      }
    }
    _queue.clear();
    _pending.clear();
    for (final send in _sends.toList()) {
      send.timer?.cancel();
      if (!send.result.isCompleted) {
        send.result.completeError(const XiangqiSocketException('Request queue disposed.'));
      }
    }
    _sends.clear();
    _retireTransport();
    unawaited(_events.close());
    unawaited(_resets.close());
  }
}

class _SocketRead<T>(
  final String event,
  final Object? data,
  final String response,
  final T Function(Object? data) decode,
  final Object? key,
  final bool ack,
  final bool Function()? isCurrent,
  final Future<void> Function()? prepare,
) {
  final result = Completer<T>();
  Timer? timer;
  bool emitted = false;
  _SocketSend? send;
}

class _SocketSend(final bool Function()? isCurrent) {
  final result = Completer<void>();
  Timer? timer;
}
