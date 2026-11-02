import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';

/// Both account menus lead to the same inbox. A xiangqi-only real account may enter without
/// borrowing a lichess identity, but a signed-in lichess child's messaging restriction still wins.
final canOpenInboxProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(authControllerProvider) != null) {
    final account = ref.watch(accountProvider);
    // Do not temporarily expose messaging while the child's account is still being fetched.
    return account.hasValue && !(account.requireValue.kid ?? false);
  }
  return ref.watch(isXiangqiLoggedInProvider);
}, name: 'CanOpenInboxProvider');
