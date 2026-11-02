import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';

/// In-memory unsent drafts outlive a room route, not its account. Keeping this separate from the
/// autoDispose chat controller allows the old room's socket and subscriptions to close normally.
final xiangqiChatDraftsProvider =
    NotifierProvider<XiangqiChatDrafts, IMap<XiangqiChatRoomKey, String>>(
      XiangqiChatDrafts.new,
      name: 'XiangqiChatDraftsProvider',
    );

class XiangqiChatDrafts() extends Notifier<IMap<XiangqiChatRoomKey, String>> {
  @override
  IMap<XiangqiChatRoomKey, String> build() {
    ref.watch(xiangqiAccountGenerationProvider);
    return const IMapConst({});
  }

  void remember(XiangqiChatRoomKey room, String text) {
    if ((state[room] ?? '') == text) return;
    state = text.isEmpty ? state.remove(room) : state.add(room, text);
  }
}
