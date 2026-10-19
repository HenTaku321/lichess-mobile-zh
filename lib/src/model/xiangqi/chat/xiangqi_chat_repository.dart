import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// The public chat rooms of `GET /api/chat_rooms/`.
///
/// Three of them, measured on 2026-10-19 — English, 中文 and Tiếng Việt — and the list is the whole
/// of the endpoint: no envelope, no paging, no session needed. What a room's `name` is for is
/// written down on [XiangqiChatRoom]: it is the address the socket is given, not a label.
final xiangqiChatRoomsProvider = FutureProvider.autoDispose<IList<XiangqiChatRoom>>((ref) async {
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for the chat rooms.');
  }
  final uri = xiangqiUri('chat_rooms/');
  final response = await ref
      .read(xiangqiClientProvider)
      .get(uri, headers: const {'Accept': 'application/json'});
  if (response.statusCode >= 400) {
    throw ServerException(response.statusCode, 'xiangqi.com chat_rooms/ failed.', uri, null);
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    throw const FormatException(
      'xiangqi.com answered chat_rooms/ with something that is not JSON.',
    );
  }
  return xiangqiChatRoomsFromJson(json);
}, name: 'XiangqiChatRoomsProvider');
